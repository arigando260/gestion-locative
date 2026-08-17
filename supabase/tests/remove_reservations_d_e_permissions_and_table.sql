-- ============================================================================
-- TEST — Retrait des réservations, PASSES D (permissions) + E (table).
--
-- Confirme l'absence totale du resource 'reservations' (catalogue et
-- octrois) et de la table public.reservations elle-même, et vérifie que le
-- seeding automatique des permissions d'une nouvelle organisation
-- (handle_new_organization, Module 1) continue de fonctionner normalement
-- sans 'reservations' mais avec le reste du catalogue intact (non-
-- régression) — y compris my_permissions, lue par le front pour tout
-- contrôle d'accès à l'écran.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module9_billing_documents.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que ces migrations soient appliquées)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_d_e_permissions_and_table.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module8_lease_termination_consensus.sql).
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

create or replace function pg_temp.check_count(p_name text, p_got bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_got = p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('lignes attendues=%s, obtenues=%s', p_expected, p_got));
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

select pg_temp.act_as_owner();

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. CATALOGUE — resource 'reservations' totalement absent, globalement.
-- ----------------------------------------------------------------------------

do $$
declare
  v_count bigint;
begin
  select count(*) into v_count from public.permissions where resource = 'reservations';
  perform pg_temp.check_count('1 permissions : 0 ligne resource=reservations', v_count, 0);

  select count(*) into v_count from public.role_permissions where resource = 'reservations';
  perform pg_temp.check_count('2 role_permissions : 0 ligne resource=reservations', v_count, 0);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. TABLE — public.reservations n'existe plus.
-- ----------------------------------------------------------------------------

do $$
declare
  v_exists boolean;
begin
  v_exists := to_regclass('public.reservations') is not null;
  if v_exists then
    perform pg_temp.record('3 public.reservations absente', 'FAIL', 'la table existe encore');
  else
    perform pg_temp.record('3 public.reservations absente', 'PASS');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. FIXTURE — nouvelle organisation, pour vérifier le seeding automatique
--    des permissions (handle_new_organization, Module 1) sans 'reservations'
--    mais avec le reste du catalogue intact.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id   uuid;
  v_staff_id uuid := gen_random_uuid();
  v_admin_role_id uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org RemoveResa DE', 'test-org-remove-resa-de-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-remove-resa-de@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test Remove Resa DE'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select r.id into v_admin_role_id
  from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into public.user_roles (user_id, role_id) values (v_staff_id, v_admin_role_id);

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_admin_role_id as admin_role_id;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 4. SEEDING DU RÔLE ADMIN D'UNE NOUVELLE ORGANISATION.
-- ----------------------------------------------------------------------------

do $$
declare
  f       record;
  v_count bigint;
begin
  select * into f from pg_temp.fixtures;

  select count(*) into v_count
  from public.role_permissions
  where role_id = f.admin_role_id and resource = 'reservations';
  perform pg_temp.check_count('4 nouvel admin : 0 permission reservations (catalogue propre)', v_count, 0);

  select count(*) into v_count
  from public.role_permissions
  where role_id = f.admin_role_id and resource = 'leases' and action = 'create';
  perform pg_temp.check_count('5 nouvel admin : permission leases/create toujours seedée (non-régression)', v_count, 1);
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. my_permissions — toujours utilisable par le front pour cette nouvelle
--    organisation, sans erreur, avec le reste du catalogue visible.
-- ----------------------------------------------------------------------------

do $$
declare
  f       record;
  v_count bigint;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  select count(*) into v_count
  from public.my_permissions
  where resource = 'leases' and action = 'create';
  perform pg_temp.check_count('6 my_permissions expose toujours leases/create pour ce staff', v_count, 1);

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. RÉSUMÉ.
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
