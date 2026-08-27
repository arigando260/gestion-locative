-- ============================================================================
-- TEST — Module 12q (public.create_property() : contourne le piège
-- RETURNING/RLS pour un agent, auto-assignation, garde-fous).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Fixtures : org_a (admin_a réel) + org_b (admin_b réel, uniquement pour le
-- test organization_id falsifié). agent_a (agent pur), combo_a (agent +
-- admin cumulés -- simulé en ajoutant une seconde ligne user_roles à un
-- compte agent réel, schéma many-to-many déjà en place), comptable_a (pour
-- le test "sans properties:create").
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805660000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12q_create_property_rpc.sql
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

select pg_temp.act_as_owner();

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a         uuid;
  v_org_b         uuid;
  v_admin_a       uuid := gen_random_uuid();
  v_admin_b       uuid := gen_random_uuid();
  v_agent_a       uuid := gen_random_uuid();
  v_combo_a       uuid := gen_random_uuid();
  v_comptable_a   uuid := gen_random_uuid();
  v_token_agent     text := encode(gen_random_bytes(32), 'hex');
  v_token_combo     text := encode(gen_random_bytes(32), 'hex');
  v_token_comptable text := encode(gen_random_bytes(32), 'hex');
  v_admin_role_a  uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_a, 'admin-12q@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12q A',
      'organization_country', 'BJ', 'organization_phone', '90000060', 'full_name', 'Admin 12q A'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_a from public.profiles where id = v_admin_a;
  select id into v_admin_role_a from public.roles where organization_id = v_org_a and code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_b, 'admin-12q-b@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12q B',
      'organization_country', 'BJ', 'organization_phone', '90000061', 'full_name', 'Admin 12q B'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_b from public.profiles where id = v_admin_b;

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'agent-12q@example.com', 'agent', encode(extensions.digest(v_token_agent, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_agent_a, 'agent-12q@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_agent, 'full_name', 'Agent 12q A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- combo_a : agent réel via le vrai parcours, PUIS cumul du rôle admin
  -- ajouté directement (user_roles est many-to-many par schéma, aucun
  -- écran ne permet ce cumul aujourd'hui -- simulation délibérée demandée).
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'combo-12q@example.com', 'agent', encode(extensions.digest(v_token_combo, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_combo_a, 'combo-12q@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_combo, 'full_name', 'Combo 12q A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id) values (v_combo_a, v_admin_role_a);

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'comptable-12q@example.com', 'comptable', encode(extensions.digest(v_token_comptable, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_comptable_a, 'comptable-12q@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_comptable, 'full_name', 'Comptable 12q A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select
    v_org_a as org_a, v_org_b as org_b,
    v_admin_a as admin_a, v_agent_a as agent_a, v_combo_a as combo_a, v_comptable_a as comptable_a;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. AGENT PUR — création réussie, ligne complète reçue, assignation posée.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_property public.properties;
  v_assignment_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  begin
    select * into v_property from public.create_property(
      f.org_a, 'Bien Test12q Agent', 'BJ', 'Cotonou', 'Fidjrosse', 'Test 12q', 55000, 'longue_duree'
    );
    perform pg_temp.record('2a agent crée un bien -> aucune erreur RETURNING, ligne reçue', 'PASS');
  exception when others then
    perform pg_temp.record('2a agent crée un bien -> aucune erreur RETURNING, ligne reçue', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  if v_property.name = 'Bien Test12q Agent' and v_property.organization_id = f.org_a then
    perform pg_temp.record('2b ligne retournée correcte (name, organization_id)', 'PASS');
  else
    perform pg_temp.record('2b ligne retournée correcte (name, organization_id)', 'FAIL', format('name=%L org=%L', v_property.name, v_property.organization_id));
  end if;

  perform pg_temp.act_as_owner();
  select count(*) into v_assignment_count
  from public.property_agent_assignments
  where property_id = v_property.id and agent_id = f.agent_a;
  if v_assignment_count = 1 then
    perform pg_temp.record('2c assignation automatique posée pour l''agent créateur', 'PASS');
  else
    perform pg_temp.record('2c assignation automatique posée pour l''agent créateur', 'FAIL', format('%s ligne(s)', v_assignment_count));
  end if;

  -- Confirme que le SELECT direct (pas seulement le RETURNING de la RPC)
  -- voit désormais bien la ligne -- preuve que l'assignation a bien été
  -- posée AVANT, pas juste que la RPC l'a court-circuité une fois.
  perform pg_temp.act_as('authenticated', f.agent_a);
  perform 1 from public.properties where id = v_property.id;
  if found then
    perform pg_temp.record('2d le bien est visible en SELECT direct pour l''agent juste après', 'PASS');
  else
    perform pg_temp.record('2d le bien est visible en SELECT direct pour l''agent juste après', 'FAIL');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. AGENT + ADMIN CUMULÉS — création réussie, PAS d'auto-assignation
--    superflue (le rôle le plus large gagne, cohérent avec
--    agent_property_scope()).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_property public.properties;
  v_assignment_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.combo_a);
  select * into v_property from public.create_property(
    f.org_a, 'Bien Test12q Combo', 'BJ', 'Cotonou', 'Akpakpa', 'Test 12q', 60000, 'longue_duree'
  );

  perform pg_temp.act_as_owner();
  select count(*) into v_assignment_count
  from public.property_agent_assignments
  where property_id = v_property.id and agent_id = f.combo_a;
  if v_assignment_count = 0 then
    perform pg_temp.record('3 compte agent+admin cumulés -> aucune auto-assignation superflue', 'PASS');
  else
    perform pg_temp.record('3 compte agent+admin cumulés -> aucune auto-assignation superflue', 'FAIL', format('%s ligne(s) inattendue(s)', v_assignment_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. ORGANIZATION_ID FALSIFIÉ — refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  begin
    perform public.create_property(
      f.org_b, 'Ne doit pas exister', 'BJ', 'Cotonou', 'Test', null, 50000, 'longue_duree'
    );
    perform pg_temp.record('4 organization_id falsifié (org_b) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 organization_id falsifié (org_b) -> refusé', v_detail, 'create_property.organization_mismatch');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SANS properties:create — refusé (comptable).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.comptable_a);
  begin
    perform public.create_property(
      f.org_a, 'Ne doit pas exister non plus', 'BJ', 'Cotonou', 'Test', null, 50000, 'longue_duree'
    );
    perform pg_temp.record('5 comptable (sans properties:create) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5 comptable (sans properties:create) -> refusé', v_detail, 'create_property.permission_denied');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. ADMIN — création réussie, pas d'assignation (n'en a pas besoin).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_property public.properties;
  v_assignment_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  select * into v_property from public.create_property(
    f.org_a, 'Bien Test12q Admin', 'BJ', 'Cotonou', 'Test', null, 50000, 'longue_duree'
  );

  perform pg_temp.act_as_owner();
  select count(*) into v_assignment_count
  from public.property_agent_assignments
  where property_id = v_property.id;
  if v_property.id is not null and v_assignment_count = 0 then
    perform pg_temp.record('6 admin crée un bien -> succès, aucune assignation posée', 'PASS');
  else
    perform pg_temp.record('6 admin crée un bien -> succès, aucune assignation posée', 'FAIL', format('property_id=%L assignations=%s', v_property.id, v_assignment_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. RÉSUMÉ.
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
