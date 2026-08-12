-- ============================================================================
-- TEST — Module 5c (génération automatique des échéances à la création d'un
-- bail, trigger AFTER INSERT sur leases).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents (module6e/module8/module2c/module9) : transaction begin/
-- rollback, helpers pg_temp, identité simulée via pg_temp.act_as(), résumé
-- PASS/FAIL avant le ROLLBACK final.
--
-- 3 scénarios :
--   1. Bail mensuel sans end_date, créé par un agent -> 12 échéances déjà
--      présentes juste après l'INSERT, sans appel manuel au RPC.
--   2. Bail avec end_date à 2 mois -> génération bornée exactement à
--      end_date (2 échéances, pas 12) : le trigger délègue entièrement
--      l'horizon à generate_payment_schedules_for_lease, sans le dupliquer.
--   3. Rôle personnalisé avec leases:create mais SANS payment_schedules:
--      create -> la création du bail échoue intégralement (RLS bloque
--      l'INSERT dans payment_schedules déclenché par le trigger), et
--      aucune ligne ne persiste dans leases pour l'id tenté — preuve de
--      l'atomicité transactionnelle.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 5c soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module5c_auto_generate_schedules_on_lease_creation.sql
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
-- 1. FIXTURES — org (admin/agent/comptable auto-seedés), un rôle personnalisé
-- avec leases:create SANS payment_schedules:create, un locataire, 3 biens
-- (un par scénario).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id           uuid;
  v_agent_id         uuid;
  v_agent_user_id    uuid := gen_random_uuid();
  v_custom_role_id   uuid;
  v_custom_user_id   uuid := gen_random_uuid();
  v_tenant_id        uuid := gen_random_uuid();
  v_prop_a           uuid;
  v_prop_b           uuid;
  v_prop_c           uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 5c', 'test-org-5c-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  select id into v_agent_id from public.roles
  where organization_id = v_org_id and code = 'agent';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_agent_user_id, 'agent-5c@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Agent Test 5c'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id) values (v_agent_user_id, v_agent_id);

  -- Rôle personnalisé délibérément incomplet : autorisé à créer un bail,
  -- mais pas à créer d'échéance — c'est précisément le cas testé par le
  -- scénario 3 (aucune UI ne permet aujourd'hui de fabriquer un tel rôle,
  -- mais rien ne l'empêche structurellement en base).
  insert into public.roles (organization_id, code, name, description, is_system)
  values (v_org_id, 'sans_generation', 'Sans génération (test)', 'leases:create sans payment_schedules:create', false)
  returning id into v_custom_role_id;

  insert into public.role_permissions (role_id, resource, action)
  values (v_custom_role_id, 'leases', 'create');

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_custom_user_id, 'custom-5c@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Sans Génération'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id) values (v_custom_user_id, v_custom_role_id);

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-5c@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 5c'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 5c — A', '1 rue du Test', 500000, 'longue_duree') returning id into v_prop_a;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 5c — B', '2 rue du Test', 500000, 'longue_duree') returning id into v_prop_b;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 5c — C', '3 rue du Test', 500000, 'longue_duree') returning id into v_prop_c;

  create table pg_temp.fixtures as
  select
    v_org_id        as org_id,
    v_agent_user_id as agent_user_id,
    v_custom_user_id as custom_user_id,
    v_tenant_id     as tenant_id,
    v_prop_a        as prop_a,
    v_prop_b        as prop_b,
    v_prop_c        as prop_c;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — bail mensuel sans end_date -> 12 échéances générées
-- automatiquement dès l'INSERT, sans appel manuel au RPC.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_id uuid;
  v_count int;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_user_id);

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, rent_amount,
    payment_frequency, security_deposit_amount, payment_timing
  ) values (
    f.org_id, f.prop_a, f.tenant_id, current_date, 100000,
    'mensuel', 200000, 'postpaye'
  )
  returning id into v_lease_id;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_schedules where lease_id = v_lease_id;

  perform pg_temp.record(
    '1 bail mensuel sans end_date -> 12 échéances générées automatiquement',
    case when v_count = 12 then 'PASS' else 'FAIL' end,
    case when v_count = 12 then null else format('%s échéance(s) trouvée(s), 12 attendues', v_count) end
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — bail avec end_date à 2 mois -> génération bornée
-- exactement à end_date (2 échéances, pas 12).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_id uuid;
  v_count int;
  v_max_period_end date;
  v_end_date date := (current_date + interval '2 months')::date;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_user_id);

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, end_date, rent_amount,
    payment_frequency, security_deposit_amount, payment_timing
  ) values (
    f.org_id, f.prop_b, f.tenant_id, current_date, v_end_date, 100000,
    'mensuel', 200000, 'postpaye'
  )
  returning id into v_lease_id;

  perform pg_temp.act_as_owner();
  select count(*), max(period_end_date) into v_count, v_max_period_end
  from public.payment_schedules where lease_id = v_lease_id;

  perform pg_temp.record(
    '2 bail avec end_date à 2 mois -> génération bornée (2 échéances, pas 12)',
    case when v_count = 2 and v_max_period_end = v_end_date then 'PASS' else 'FAIL' end,
    case when v_count = 2 and v_max_period_end = v_end_date then null
      else format('count=%s (attendu 2), max(period_end_date)=%s (attendu %s)', v_count, v_max_period_end, v_end_date)
    end
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — rôle avec leases:create SANS payment_schedules:create ->
-- la création du bail échoue intégralement (RLS bloque l'INSERT dans
-- payment_schedules déclenché par le trigger), aucune ligne ne persiste
-- dans leases pour l'id tenté.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_attempted_id uuid := gen_random_uuid();
  v_count int;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.custom_user_id);

  begin
    insert into public.leases (
      id, organization_id, property_id, tenant_account_id, start_date, rent_amount,
      payment_frequency, security_deposit_amount, payment_timing
    ) values (
      v_attempted_id, f.org_id, f.prop_c, f.tenant_id, current_date, 100000,
      'mensuel', 200000, 'postpaye'
    );
    perform pg_temp.record(
      '3a création de bail par un rôle sans payment_schedules:create -> échec attendu',
      'FAIL', 'succès inattendu (aucune exception levée)'
    );
  exception when others then
    perform pg_temp.record(
      '3a création de bail par un rôle sans payment_schedules:create -> échec attendu',
      'PASS'
    );
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.leases where id = v_attempted_id;

  perform pg_temp.record(
    '3b aucune ligne leases persistée après l''échec (atomicité)',
    case when v_count = 0 then 'PASS' else 'FAIL' end,
    case when v_count = 0 then null else format('%s ligne(s) trouvée(s) alors qu''aucune n''était attendue', v_count) end
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. RÉSUMÉ.
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
