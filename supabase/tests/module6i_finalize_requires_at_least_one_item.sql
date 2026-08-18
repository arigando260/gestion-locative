-- ============================================================================
-- TEST — Module 6i (au moins un constat requis à la finalisation).
--
-- Refus sans item, acceptation avec au moins un, non-régression sur
-- observations déjà requis (Module 6g — une inspection avec un item mais
-- sans observations doit toujours être refusée, pour la raison 6g, pas 6i).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module6g_finalize_requires_observations.sql (bascule de
-- session nécessaire : finaliser passe par private.prevent_tenant_
-- finalizing_inspection, Module 6, qui revérifie has_permission sur la
-- session courante).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module6i_finalize_requires_at_least_one_item.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module6g_finalize_requires_observations.sql).
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

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — deux baux/inspections brouillon : inspection_main a des
--    observations déjà renseignées (isole le check 6i du check 6g) mais
--    aucun item ; inspection_no_observations a un item mais aucune
--    observation (isole le check 6g, régression).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id                  uuid;
  v_staff_id                uuid := gen_random_uuid();
  v_tenant_id               uuid := gen_random_uuid();
  v_prop_id                 uuid;
  v_lease_id                uuid;
  v_inspection_main         uuid;
  v_inspection_no_obs       uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 6i', 'test-org-6i-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-6i@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 6i'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-6i@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 6i'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6i', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, observations)
  values (v_org_id, v_lease_id, 'entree', current_date, 'brouillon', v_staff_id, 'Observations déjà renseignées')
  returning id into v_inspection_main;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_id, 'sortie', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_no_obs;

  insert into public.inspection_items (organization_id, inspection_id, zone, condition)
  values (v_org_id, v_inspection_no_obs, 'Salon', 'bon');

  create table pg_temp.fixtures as
  select
    v_staff_id           as staff_id,
    v_inspection_main    as inspection_main,
    v_inspection_no_obs  as inspection_no_obs;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — FINALISATION REFUSÉE SANS AUCUN ITEM.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections set document_status = 'finalise' where id = f.inspection_main;
    perform pg_temp.record('1 finalisation sans aucun item -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('1 finalisation sans aucun item -> refusée', v_detail, 'property_inspection.finalize.requires_at_least_one_item');
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — FINALISATION ACCEPTÉE AVEC AU MOINS UN ITEM.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_status text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.inspection_items (organization_id, inspection_id, zone, condition)
  select organization_id, id, 'Cuisine', 'bon' from public.property_inspections where id = f.inspection_main;

  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections set document_status = 'finalise' where id = f.inspection_main;
    perform pg_temp.record('2 finalisation avec au moins un item -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('2 finalisation avec au moins un item -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();

  select document_status into v_status from public.property_inspections where id = f.inspection_main;
  perform pg_temp.check_detail('2b document_status = finalise après succès', v_status, 'finalise');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — RÉGRESSION : observations toujours requis (Module 6g),
--    un item présent ne suffit pas à contourner ce check-là.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections set document_status = 'finalise' where id = f.inspection_no_obs;
    perform pg_temp.record('3 finalisation avec item mais sans observations -> refusée (régression 6g)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 finalisation avec item mais sans observations -> refusée (régression 6g)', v_detail, 'property_inspection.finalize.observations_required');
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
