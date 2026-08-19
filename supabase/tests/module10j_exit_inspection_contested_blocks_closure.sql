-- ============================================================================
-- TEST — Module 10j (état des lieux de sortie contesté bloque la clôture).
--
-- 1. Sortie finalisée NON contestée -> exit_inspection_done = true,
--    transition actif -> termine autorisée (non-régression).
-- 2. Sortie finalisée CONTESTÉE -> exit_inspection_done = false, transition
--    refusée avec le nouveau slug lease.closure.exit_inspection_contested.
-- 3. Aucune sortie -> exit_inspection_done = false, transition refusée
--    avec le slug existant lease.closure.missing_exit_inspection
--    (non-régression sur le cas déjà couvert).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les tests précédents (BEGIN/
-- ROLLBACK, helpers pg_temp, force_lease_status).
--
-- Les property_inspections de fixture sont insérées directement à
-- document_status='finalise' (aucun trigger BEFORE UPDATE OF document_
-- status — 6g/6h/6i, prevent_tenant_finalizing, set_finalized_at — ne se
-- déclenche à l'INSERT, seulement à l'UPDATE) : pas besoin de désactiver
-- de trigger pour cette fixture, contrairement à force_lease_status.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10j_exit_inspection_contested_blocks_closure.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques aux tests précédents).
-- ----------------------------------------------------------------------------

create table pg_temp.test_results (
  id     serial primary key,
  name   text not null,
  status text not null check (status in ('PASS', 'FAIL')),
  detail text
);

create or replace function pg_temp.record(p_name text, p_status text, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into pg_temp.test_results (name, status, detail) values (p_name, p_status, p_detail);
  raise notice '[%] % %', p_status, p_name, coalesce('— ' || p_detail, '');
end;
$$;

create or replace function pg_temp.check_bool(p_name text, p_got boolean, p_expected boolean)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('attendu=%L, obtenu=%L', p_expected, p_got));
  end if;
end;
$$;

create or replace function pg_temp.check_detail(p_name text, p_got text, p_expected text)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('détail attendu=%L, obtenu=%L', p_expected, p_got));
  end if;
end;
$$;

create or replace function pg_temp.act_as(p_pg_role text, p_user_id uuid)
returns void language plpgsql as $$
begin
  execute format('set local role %I', p_pg_role);
  if p_user_id is null then
    perform set_config('request.jwt.claims', '{}', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_user_id::text, 'role', p_pg_role)::text,
      true
    );
  end if;
end;
$$;

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

-- Même helper que supabase/tests/module10_lease_lifecycle.sql /
-- module10i_closure_reference_date.sql : amène un bail brouillon à
-- 'actif' sans repasser par tout le parcours d'approbation (déjà prouvé
-- ailleurs) — fixture uniquement.
create or replace function pg_temp.force_lease_status(p_lease uuid, p_status text)
returns void language plpgsql as $$
begin
  alter table public.leases disable trigger trg_leases_validate_status_transition;
  update public.leases set status = p_status where id = p_lease;
  alter table public.leases enable trigger trg_leases_validate_status_transition;
end;
$$;

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — 3 baux (1 bien chacun, contrainte "un seul bail actif/
--    brouillon par bien", Module 10b), amenés à 'actif' puis équipés
--    chacun d'un scénario de sortie différent.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_prop_ok      uuid;
  v_prop_contest uuid;
  v_prop_none    uuid;
  v_lease_ok     uuid;
  v_lease_contest uuid;
  v_lease_none   uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10j', 'test-org-10j-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10j@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10j'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10j@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10j'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10j OK', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_ok;
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10j Contest', '2 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_contest;
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10j None', '3 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_none;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, keys_returned_at,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_ok, v_tenant_id, current_date - 60, current_date - 5, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_ok;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, keys_returned_at,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_contest, v_tenant_id, current_date - 60, current_date - 5, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_contest;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, keys_returned_at,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_none, v_tenant_id, current_date - 60, current_date - 5, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_none;

  perform pg_temp.force_lease_status(v_lease_ok, 'actif');
  perform pg_temp.force_lease_status(v_lease_contest, 'actif');
  perform pg_temp.force_lease_status(v_lease_none, 'actif');

  -- Sortie finalisée NON contestée. INSERT direct à document_status=
  -- 'finalise' : aucun trigger BEFORE UPDATE OF document_status ne se
  -- déclenche à l'INSERT (voir en-tête).
  insert into public.property_inspections (
    organization_id, lease_id, inspection_type, inspection_date, document_status,
    tenant_validation_status, tenant_validation_at, conducted_by, finalized_at
  ) values (
    v_org_id, v_lease_ok, 'sortie', current_date - 5, 'finalise',
    'valide', now(), v_staff_id, now()
  );

  -- Sortie finalisée CONTESTÉE.
  insert into public.property_inspections (
    organization_id, lease_id, inspection_type, inspection_date, document_status,
    tenant_validation_status, tenant_validation_at, conducted_by, finalized_at
  ) values (
    v_org_id, v_lease_contest, 'sortie', current_date - 5, 'finalise',
    'conteste', now(), v_staff_id, now()
  );

  -- v_lease_none : aucune property_inspections.

  create table pg_temp.fixtures as
  select
    v_staff_id       as staff_id,
    v_lease_ok       as lease_ok,
    v_lease_contest  as lease_contest,
    v_lease_none     as lease_none;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — SORTIE NON CONTESTÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f       record;
  v_done  boolean;
  v_status text;
begin
  select * into f from pg_temp.fixtures;

  select exit_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_ok;
  perform pg_temp.check_bool('1a exit_inspection_done (sortie non contestée) -> true', v_done, true);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set status = 'termine' where id = f.lease_ok;
    perform pg_temp.record('1b transition actif -> termine (sortie non contestée) -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('1b transition actif -> termine (sortie non contestée) -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
  perform pg_temp.act_as_owner();

  select status into v_status from public.leases where id = f.lease_ok;
  perform pg_temp.check_detail('1c leases.status = termine après succès', v_status, 'termine');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — SORTIE CONTESTÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_done   boolean;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  select exit_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_contest;
  perform pg_temp.check_bool('2a exit_inspection_done (sortie contestée) -> false', v_done, false);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set status = 'termine' where id = f.lease_contest;
    perform pg_temp.record('2b transition actif -> termine (sortie contestée) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2b transition actif -> termine (sortie contestée) -> refusée', v_detail, 'lease.closure.exit_inspection_contested');
  end;
  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — AUCUNE SORTIE (non-régression).
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_done   boolean;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  select exit_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_none;
  perform pg_temp.check_bool('3a exit_inspection_done (aucune sortie) -> false', v_done, false);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set status = 'termine' where id = f.lease_none;
    perform pg_temp.record('3b transition actif -> termine (aucune sortie) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3b transition actif -> termine (aucune sortie) -> refusée', v_detail, 'lease.closure.missing_exit_inspection');
  end;
  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. RÉSUMÉ.
-- ----------------------------------------------------------------------------

select
  count(*) filter (where status = 'PASS') as passed,
  count(*) filter (where status = 'FAIL') as failed,
  count(*)                                as total
from pg_temp.test_results;

select id, name, status, detail
from pg_temp.test_results
order by id;

do $$
declare
  v_failed int;
begin
  select count(*) into v_failed from pg_temp.test_results where status = 'FAIL';
  if v_failed > 0 then
    raise warning '% test(s) en échec — voir le résumé ci-dessus.', v_failed;
  else
    raise notice 'Tous les tests sont passés.';
  end if;
end;
$$;

rollback;
