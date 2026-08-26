-- ============================================================================
-- TEST — Module 12l (roles_select : ajout de is_internal(), durcissement
-- défensif — voir le commentaire de la migration pour le correctif du
-- diagnostic initial, qui supposait à tort une fuite active).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp (dont act_as(), pour simuler un rôle non
-- superuser), résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805610000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12l_roles_select_is_internal.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

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
-- 1. POLICY — vérification structurelle : is_internal() apparaît bien dans
--    la définition vivante de roles_select.
-- ----------------------------------------------------------------------------

do $$
declare
  v_qual text;
begin
  select qual into v_qual
  from pg_policies
  where schemaname = 'public' and tablename = 'roles' and policyname = 'roles_select';

  if v_qual ilike '%is_internal%' then
    perform pg_temp.record('1 roles_select contient is_internal() dans sa définition', 'PASS');
  else
    perform pg_temp.record('1 roles_select contient is_internal() dans sa définition', 'FAIL', format('qual=%L', v_qual));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. FIXTURES — une organisation (admin réel via handle_new_user, roles
--    admin/agent/comptable auto-seedés) et un locataire, réellement invité
--    (tenant_invitations + jeton, même chemin que private.handle_new_user
--    en production) et acceptant via le trigger normal -- pas de bypass de
--    trg_handle_new_user nécessaire : le rôle "postgres" de ce projet
--    (SUPABASE_DB_URL) n'est pas propriétaire de auth.users, une désactivation
--    directe du trigger échoue ("must be owner of table users").
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_admin_user   uuid := gen_random_uuid();
  v_tenant_user  uuid := gen_random_uuid();
  v_raw_token    text := encode(gen_random_bytes(32), 'hex');
  v_token_hash   text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_user, 'admin-roles12l@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_name', 'Org Test 12l',
      'organization_country', 'BJ',
      'organization_phone', '90000005',
      'full_name', 'Admin Test 12l'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_admin_user;

  v_token_hash := encode(extensions.digest(v_raw_token, 'sha256'), 'hex');

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (v_org_id, 'tenant-roles12l@example.com', v_token_hash, v_admin_user, now() + interval '7 days');

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_user, 'tenant-roles12l@example.com',
    jsonb_build_object(
      'account_type', 'tenant',
      'invitation_token', v_raw_token,
      'full_name', 'Tenant Test 12l'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select
    v_org_id      as org_id,
    v_admin_user  as admin_user,
    v_tenant_user as tenant_user;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 3. COMPORTEMENT — l'admin voit les 3 rôles système de son organisation
--    (comportement staff inchangé), le locataire réellement invité et
--    rattaché à cette même organisation n'en voit aucun.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_user);
  select count(*) into v_count from public.roles where organization_id = f.org_id;
  if v_count = 3 then
    perform pg_temp.record('2a admin voit les 3 rôles système de son organisation', 'PASS');
  else
    perform pg_temp.record('2a admin voit les 3 rôles système de son organisation', 'FAIL', format('%s ligne(s)', v_count));
  end if;

  perform pg_temp.act_as('authenticated', f.tenant_user);
  select count(*) into v_count from public.roles where organization_id = f.org_id;
  if v_count = 0 then
    perform pg_temp.record('2b locataire ne voit aucun rôle de l''organisation qui gère son bail', 'PASS');
  else
    perform pg_temp.record('2b locataire ne voit aucun rôle de l''organisation qui gère son bail', 'FAIL', format('%s ligne(s)', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. RÉSUMÉ.
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
