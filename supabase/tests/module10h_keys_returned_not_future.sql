-- ============================================================================
-- TEST — Module 10h (leases_keys_returned_not_future).
--
-- 1. keys_returned_at = aujourd'hui -> acceptée.
-- 2. keys_returned_at = demain -> refusée (23514, contrainte
--    leases_keys_returned_not_future).
--
-- Ne re-teste pas leases_keys_returned_after_start (Module 6, borne basse) :
-- déjà couverte ailleurs, aucune interaction entre les deux contraintes.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les tests précédents (helpers
-- pg_temp, act_as/act_as_owner, BEGIN/ROLLBACK).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10h_keys_returned_not_future.sql
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
-- 1. FIXTURES — un bail, start_date largement dans le passé pour isoler
--    ce test de leases_keys_returned_after_start.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
  v_prop_id   uuid;
  v_lease_id  uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10h', 'test-org-10h-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10h@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10h@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10h', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date - 365, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  create table pg_temp.fixtures as
  select v_staff_id as staff_id, v_lease_id as lease_id;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — keys_returned_at = AUJOURD'HUI -> ACCEPTÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.leases set keys_returned_at = current_date where id = f.lease_id;
    perform pg_temp.record('1 keys_returned_at = aujourd''hui -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('1 keys_returned_at = aujourd''hui -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — keys_returned_at = DEMAIN -> REFUSÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sqlstate   text;
  v_constraint text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.leases set keys_returned_at = current_date + 1 where id = f.lease_id;
    perform pg_temp.record('2 keys_returned_at = demain -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'leases_keys_returned_not_future' then
      perform pg_temp.record('2 keys_returned_at = demain -> refusée', 'PASS');
    else
      perform pg_temp.record(
        '2 keys_returned_at = demain -> refusée', 'FAIL',
        format('sqlstate/constraint attendus 23514/leases_keys_returned_not_future, obtenus %s/%s', v_sqlstate, v_constraint)
      );
    end if;
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. RÉSUMÉ.
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
