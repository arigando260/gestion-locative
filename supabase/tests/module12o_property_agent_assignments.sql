-- ============================================================================
-- TEST — Module 12o (table property_agent_assignments, RLS, fonction
-- private.agent_property_scope).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Fixtures : org_a (admin_a réel) + org_b (admin_b réel, uniquement pour le
-- test FK cross-org). Un agent et un comptable réels dans org_a, créés via
-- le VRAI parcours d'invitation staff (staff_invitations +
-- handle_new_user(), Module 12m/12n -- désormais possible, contrairement
-- aux tests précédents qui devaient contourner l'absence de ce mécanisme).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805640000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12o_property_agent_assignments.sql
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
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a       uuid;
  v_org_b       uuid;
  v_admin_a     uuid := gen_random_uuid();
  v_admin_b     uuid := gen_random_uuid();
  v_agent_a     uuid := gen_random_uuid();
  v_comptable_a uuid := gen_random_uuid();
  v_property_a1 uuid;
  v_property_b1 uuid;
  v_token_agent      text := encode(gen_random_bytes(32), 'hex');
  v_token_comptable   text := encode(gen_random_bytes(32), 'hex');
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_a, 'admin-12o@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12o A',
      'organization_country', 'BJ', 'organization_phone', '90000040', 'full_name', 'Admin 12o A'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_a from public.profiles where id = v_admin_a;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_b, 'admin-12o-b@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12o B',
      'organization_country', 'BJ', 'organization_phone', '90000041', 'full_name', 'Admin 12o B'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_b from public.profiles where id = v_admin_b;

  -- Agent et comptable réels dans org_a, via le vrai parcours d'invitation
  -- staff (Module 12m/12n).
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'agent-12o@example.com', 'agent', encode(extensions.digest(v_token_agent, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_agent_a, 'agent-12o@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_agent, 'full_name', 'Agent 12o A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'comptable-12o@example.com', 'comptable', encode(extensions.digest(v_token_comptable, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_comptable_a, 'comptable-12o@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_comptable, 'full_name', 'Comptable 12o A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (v_org_a, 'Bien Test12o A1', 500000, 'longue_duree', 'BJ', 'Cotonou', 'Fidjrosse', 'Test 12o')
  returning id into v_property_a1;

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (v_org_b, 'Bien Test12o B1', 400000, 'longue_duree', 'BJ', 'Cotonou', 'Akpakpa', 'Test 12o')
  returning id into v_property_b1;

  create table pg_temp.fixtures as
  select
    v_org_a as org_a, v_org_b as org_b,
    v_admin_a as admin_a, v_admin_b as admin_b,
    v_agent_a as agent_a, v_comptable_a as comptable_a,
    v_property_a1 as property_a1, v_property_b1 as property_b1;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. FK COMPOSITE — assignation cross-org refusée dans les deux sens.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();

  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_b1, f.agent_a, f.admin_a);
    perform pg_temp.record('2a bien d''une autre organisation -> refusé (FK property_org)', 'FAIL', 'succès inattendu');
  exception when foreign_key_violation then
    perform pg_temp.record('2a bien d''une autre organisation -> refusé (FK property_org)', 'PASS');
  when others then
    perform pg_temp.record('2a bien d''une autre organisation -> refusé (FK property_org)', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_a1, f.admin_b, f.admin_a);
    perform pg_temp.record('2b agent d''une autre organisation -> refusé (FK agent_org)', 'FAIL', 'succès inattendu');
  exception when foreign_key_violation then
    perform pg_temp.record('2b agent d''une autre organisation -> refusé (FK agent_org)', 'PASS');
  when others then
    perform pg_temp.record('2b agent d''une autre organisation -> refusé (FK agent_org)', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. agent_property_scope() — admin/comptable toujours true, agent non
--    assigné false.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_result boolean;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  select private.agent_property_scope(f.property_a1) into v_result;
  if v_result = true then
    perform pg_temp.record('3a admin -> agent_property_scope() = true (sans assignation)', 'PASS');
  else
    perform pg_temp.record('3a admin -> agent_property_scope() = true (sans assignation)', 'FAIL', format('obtenu=%L', v_result));
  end if;

  perform pg_temp.act_as('authenticated', f.comptable_a);
  select private.agent_property_scope(f.property_a1) into v_result;
  if v_result = true then
    perform pg_temp.record('3b comptable -> agent_property_scope() = true (sans assignation)', 'PASS');
  else
    perform pg_temp.record('3b comptable -> agent_property_scope() = true (sans assignation)', 'FAIL', format('obtenu=%L', v_result));
  end if;

  perform pg_temp.act_as('authenticated', f.agent_a);
  select private.agent_property_scope(f.property_a1) into v_result;
  if v_result = false then
    perform pg_temp.record('3c agent non assigné -> agent_property_scope() = false', 'PASS');
  else
    perform pg_temp.record('3c agent non assigné -> agent_property_scope() = false', 'FAIL', format('obtenu=%L', v_result));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. INSERT — admin autorisé, agent/comptable refusés (permission).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_a1, f.agent_a, f.agent_a);
    perform pg_temp.record('4a agent (sans permission create) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('4a agent (sans permission create) -> refusé', 'PASS');
  end;

  perform pg_temp.act_as('authenticated', f.comptable_a);
  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_a1, f.agent_a, f.comptable_a);
    perform pg_temp.record('4b comptable (sans permission create) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('4b comptable (sans permission create) -> refusé', 'PASS');
  end;

  perform pg_temp.act_as('authenticated', f.admin_a);
  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_a1, f.agent_a, f.admin_a);
    perform pg_temp.record('4c admin -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('4c admin -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. agent_property_scope() — agent maintenant assigné -> true.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_result boolean;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  select private.agent_property_scope(f.property_a1) into v_result;
  if v_result = true then
    perform pg_temp.record('5 agent assigné -> agent_property_scope() = true', 'PASS');
  else
    perform pg_temp.record('5 agent assigné -> agent_property_scope() = true', 'FAIL', format('obtenu=%L', v_result));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. CHECK CONSTRAINT — doublon (même property_id + agent_id) refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  begin
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (f.org_a, f.property_a1, f.agent_a, f.admin_a);
    perform pg_temp.record('6 doublon (même bien, même agent) -> refusé', 'FAIL', 'succès inattendu');
  exception when unique_violation then
    perform pg_temp.record('6 doublon (même bien, même agent) -> refusé', 'PASS');
  when others then
    perform pg_temp.record('6 doublon (même bien, même agent) -> refusé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SELECT — tout interne de org_a voit l'assignation, org_b n'en voit
--    aucune.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  select count(*) into v_count from public.property_agent_assignments where organization_id = f.org_a;
  if v_count = 1 then
    perform pg_temp.record('7a agent voit l''assignation de son organisation', 'PASS');
  else
    perform pg_temp.record('7a agent voit l''assignation de son organisation', 'FAIL', format('%s ligne(s)', v_count));
  end if;

  perform pg_temp.act_as('authenticated', f.admin_b);
  select count(*) into v_count from public.property_agent_assignments where organization_id = f.org_a;
  if v_count = 0 then
    perform pg_temp.record('7b admin B ne voit aucune assignation de l''organisation A', 'PASS');
  else
    perform pg_temp.record('7b admin B ne voit aucune assignation de l''organisation A', 'FAIL', format('%s ligne(s)', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. DELETE — agent refusé, admin autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  delete from public.property_agent_assignments where organization_id = f.org_a and property_id = f.property_a1 and agent_id = f.agent_a;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.property_agent_assignments where organization_id = f.org_a and property_id = f.property_a1 and agent_id = f.agent_a;
  if v_count = 1 then
    perform pg_temp.record('8a agent (sans permission delete) -> aucune ligne supprimée', 'PASS');
  else
    perform pg_temp.record('8a agent (sans permission delete) -> aucune ligne supprimée', 'FAIL', format('%s ligne(s) restante(s)', v_count));
  end if;

  perform pg_temp.act_as('authenticated', f.admin_a);
  delete from public.property_agent_assignments where organization_id = f.org_a and property_id = f.property_a1 and agent_id = f.agent_a;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.property_agent_assignments where organization_id = f.org_a and property_id = f.property_a1 and agent_id = f.agent_a;
  if v_count = 0 then
    perform pg_temp.record('8b admin -> suppression autorisée', 'PASS');
  else
    perform pg_temp.record('8b admin -> suppression autorisée', 'FAIL', format('%s ligne(s) restante(s)', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. RÉSUMÉ.
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
