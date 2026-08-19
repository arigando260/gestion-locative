-- ============================================================================
-- TEST — Module 10k (entry_inspection_done tient compte de la contestation).
--
-- 1. Entrée finalisée NON contestée -> entry_inspection_done = true
--    (non-régression).
-- 2. Entrée finalisée CONTESTÉE -> entry_inspection_done = false.
-- 3. Aucune entrée -> entry_inspection_done = false (non-régression).
--
-- Pas de test de transition de statut de bail ici (contrairement à 10j) :
-- private.validate_lease_status_transition() n'est pas modifié, l'entrée
-- n'a jamais conditionné aucune transition.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les tests précédents (BEGIN/
-- ROLLBACK, helpers pg_temp, force_lease_status).
--
-- Les property_inspections de fixture sont insérées directement à
-- document_status='finalise' (aucun trigger BEFORE UPDATE OF document_
-- status ne se déclenche à l'INSERT). Pour le type 'entree' spécifiquement,
-- trg_property_inspections_validate_entry_date (BEFORE INSERT) exige
-- inspection_date <= lease.start_date — respecté ci-dessous.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10k_entry_inspection_contested_status.sql
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

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

-- Même helper que les tests précédents : amène un bail brouillon à 'actif'
-- sans repasser par le parcours d'approbation (déjà prouvé ailleurs) —
-- fixture uniquement.
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
--    chacun d'un scénario d'entrée différent.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_prop_ok      uuid;
  v_prop_contest uuid;
  v_prop_none    uuid;
  v_lease_ok      uuid;
  v_lease_contest uuid;
  v_lease_none    uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10k', 'test-org-10k-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10k@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10k'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10k@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10k'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10k OK', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_ok;
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10k Contest', '2 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_contest;
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10k None', '3 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_none;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_ok, v_tenant_id, current_date - 60, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_ok;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_contest, v_tenant_id, current_date - 60, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_contest;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_none, v_tenant_id, current_date - 60, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_none;

  perform pg_temp.force_lease_status(v_lease_ok, 'actif');
  perform pg_temp.force_lease_status(v_lease_contest, 'actif');
  perform pg_temp.force_lease_status(v_lease_none, 'actif');

  -- Entrée finalisée NON contestée. inspection_date <= start_date
  -- (trg_property_inspections_validate_entry_date, BEFORE INSERT pour ce
  -- type). INSERT direct à document_status='finalise' : aucun trigger
  -- BEFORE UPDATE OF document_status ne se déclenche à l'INSERT.
  insert into public.property_inspections (
    organization_id, lease_id, inspection_type, inspection_date, document_status,
    tenant_validation_status, tenant_validation_at, conducted_by, finalized_at
  ) values (
    v_org_id, v_lease_ok, 'entree', current_date - 60, 'finalise',
    'valide', now(), v_staff_id, now()
  );

  -- Entrée finalisée CONTESTÉE.
  insert into public.property_inspections (
    organization_id, lease_id, inspection_type, inspection_date, document_status,
    tenant_validation_status, tenant_validation_at, conducted_by, finalized_at
  ) values (
    v_org_id, v_lease_contest, 'entree', current_date - 60, 'finalise',
    'conteste', now(), v_staff_id, now()
  );

  -- v_lease_none : aucune property_inspections.

  create table pg_temp.fixtures as
  select
    v_lease_ok       as lease_ok,
    v_lease_contest  as lease_contest,
    v_lease_none     as lease_none;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIOS.
-- ----------------------------------------------------------------------------

do $$
declare
  f      record;
  v_done boolean;
begin
  select * into f from pg_temp.fixtures;

  select entry_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_ok;
  perform pg_temp.check_bool('1 entry_inspection_done (entrée non contestée) -> true', v_done, true);

  select entry_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_contest;
  perform pg_temp.check_bool('2 entry_inspection_done (entrée contestée) -> false', v_done, false);

  select entry_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease_none;
  perform pg_temp.check_bool('3 entry_inspection_done (aucune entrée) -> false', v_done, false);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. RÉSUMÉ.
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
