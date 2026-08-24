-- ============================================================================
-- TEST — harmonisation des policies SELECT sur leases, payment_schedules,
-- deposit_ledger (migration 20260805480000_harmonize_select_has_permission_read.sql).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents (module6e/
-- module7b/module8/module9) : transaction begin/rollback, helpers pg_temp,
-- identité simulée via pg_temp.act_as(), résumé PASS/FAIL avant le
-- ROLLBACK final.
--
-- Objectif : un rôle interne SANS la permission read sur ces 3 ressources ne
-- doit plus rien voir malgré is_internal()=true (régression volontaire du
-- correctif) ; les 3 rôles système (admin/agent/comptable), qui ont tous
-- read par défaut, ne doivent voir aucune régression.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805480000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/harmonize_select_has_permission_read.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques aux scripts précédents).
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

select pg_temp.act_as_owner();

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — org (seed automatique admin/agent/comptable), un 4e rôle
--    interne sans aucune permission, un staff par rôle, un bien/bail/
--    échéance/mouvement de caution.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id          uuid;
  v_prop            uuid;
  v_lease           uuid;
  v_tenant_id       uuid := gen_random_uuid();
  v_admin_role      uuid;
  v_agent_role      uuid;
  v_comptable_role  uuid;
  v_restricted_role uuid;
  v_admin_user      uuid := gen_random_uuid();
  v_agent_user      uuid := gen_random_uuid();
  v_comptable_user  uuid := gen_random_uuid();
  v_restricted_user uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug)
  values ('Test Org RLS Read Gap', 'test-org-rls-read-gap-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  select id into v_admin_role from public.roles where organization_id = v_org_id and code = 'admin';
  select id into v_agent_role from public.roles where organization_id = v_org_id and code = 'agent';
  select id into v_comptable_role from public.roles where organization_id = v_org_id and code = 'comptable';

  insert into public.roles (organization_id, code, name, description, is_system)
  values (v_org_id, 'test_restricted', 'Test Restreint', 'Role de test sans aucune permission', false)
  returning id into v_restricted_role;
  -- Volontairement : aucune ligne role_permissions pour ce role.

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values
    (v_admin_user, 'admin-rlsgap@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Admin Test'), '{}'::jsonb, 'authenticated', 'authenticated'),
    (v_agent_user, 'agent-rlsgap@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Agent Test'), '{}'::jsonb, 'authenticated', 'authenticated'),
    (v_comptable_user, 'comptable-rlsgap@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Comptable Test'), '{}'::jsonb, 'authenticated', 'authenticated'),
    (v_restricted_user, 'restricted-rlsgap@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Restricted Test'), '{}'::jsonb, 'authenticated', 'authenticated');

  insert into public.user_roles (user_id, role_id) values
    (v_admin_user, v_admin_role),
    (v_agent_user, v_agent_role),
    (v_comptable_user, v_comptable_role),
    (v_restricted_user, v_restricted_role);

  -- Locataire réel (pas un simple uuid) : le trigger de validation du bail
  -- exige un rattachement actif (tenant_organization_memberships) à
  -- l'organisation, que handle_new_user pose automatiquement quand
  -- organization_id est fourni dans les métadonnées.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (v_tenant_id, 'tenant-rlsgap@example.com', jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test'), '{}'::jsonb, 'authenticated', 'authenticated');

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien Test RLS Read Gap', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop;

  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date)
  values (v_org_id, v_lease, current_date, current_date + interval '1 month', 100000, current_date + interval '1 month');

  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (v_org_id, v_lease, 'avance_garantie', 'depot_initial', 200000);

  create table pg_temp.fixtures as
  select
    v_org_id          as org_id,
    v_lease           as lease_id,
    v_admin_user      as admin_user,
    v_agent_user      as agent_user,
    v_comptable_user  as comptable_user,
    v_restricted_user as restricted_user;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIOS — pour chaque table (leases / payment_schedules /
--    deposit_ledger), pour chaque acteur, on compte les lignes visibles.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
  v_actor record;
  v_table text;
  actors  uuid[];
  actor_names text[];
  actor_expects int[];
begin
  select * into f from pg_temp.fixtures;

  actors      := array[f.admin_user, f.agent_user, f.comptable_user, f.restricted_user];
  actor_names := array['admin', 'agent', 'comptable', 'restricted'];
  actor_expects := array[1, 1, 1, 0];

  foreach v_table in array array['leases', 'payment_schedules', 'deposit_ledger']
  loop
    for i in 1..array_length(actors, 1) loop
      perform pg_temp.act_as('authenticated', actors[i]);

      execute format(
        'select count(*) from public.%I where organization_id = %L',
        v_table, f.org_id
      ) into v_count;

      if v_count = actor_expects[i] then
        perform pg_temp.record(
          format('%s / role %s -> %s ligne(s) visible(s) (attendu %s)', v_table, actor_names[i], v_count, actor_expects[i]),
          'PASS'
        );
      else
        perform pg_temp.record(
          format('%s / role %s -> %s ligne(s) visible(s) (attendu %s)', v_table, actor_names[i], v_count, actor_expects[i]),
          'FAIL',
          format('obtenu=%s attendu=%s', v_count, actor_expects[i])
        );
      end if;
    end loop;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. RÉSUMÉ.
-- ----------------------------------------------------------------------------

select pg_temp.act_as_owner();

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
