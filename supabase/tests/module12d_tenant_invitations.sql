-- ============================================================================
-- TEST — Module 12d (table tenant_invitations, RLS, aperçu pré-inscription).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805530000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12d_tenant_invitations.sql
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

grant select, insert on pg_temp.test_results to authenticated, service_role, anon;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — deux organisations (A et B), chacune avec un staff admin
--    (toutes permissions) et un staff restreint (aucune permission).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a         uuid;
  v_org_b         uuid;
  v_admin_role_a  uuid;
  v_restricted_a  uuid;
  v_admin_user_a  uuid := gen_random_uuid();
  v_restricted_user_a uuid := gen_random_uuid();
  v_admin_role_b  uuid;
  v_admin_user_b  uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org12d A', 'test-org12d-a-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_a;

  insert into public.organizations (name, slug, country_code)
  values ('Test Org12d B', 'test-org12d-b-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_b;

  select id into v_admin_role_a from public.roles where organization_id = v_org_a and code = 'admin';
  select id into v_admin_role_b from public.roles where organization_id = v_org_b and code = 'admin';

  insert into public.roles (organization_id, code, name, description, is_system)
  values (v_org_a, 'test_restricted', 'Test Restreint', 'Sans permission', false)
  returning id into v_restricted_a;
  -- Volontairement aucune ligne role_permissions pour ce role.

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values
    (v_admin_user_a, 'admin-org12da@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_a, 'full_name', 'Admin A'), '{}'::jsonb, 'authenticated', 'authenticated'),
    (v_restricted_user_a, 'restricted-org12da@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_a, 'full_name', 'Restreint A'), '{}'::jsonb, 'authenticated', 'authenticated'),
    (v_admin_user_b, 'admin-org12db@example.com', jsonb_build_object('account_type', 'internal', 'organization_id', v_org_b, 'full_name', 'Admin B'), '{}'::jsonb, 'authenticated', 'authenticated');

  insert into public.user_roles (user_id, role_id) values
    (v_admin_user_a, v_admin_role_a),
    (v_restricted_user_a, v_restricted_a),
    (v_admin_user_b, v_admin_role_b);

  create table pg_temp.fixtures as
  select
    v_org_a as org_a, v_org_b as org_b,
    v_admin_user_a as admin_a, v_restricted_user_a as restricted_a, v_admin_user_b as admin_b;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO — admin A crée une invitation pour son organisation ->
--    autorisé. Restreint A ne peut pas -> refusé (RLS).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  begin
    insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
    values (f.org_a, 'locataire-a@example.com', encode(digest('token-a-' || f.org_a::text, 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');
    perform pg_temp.record('2a admin A crée une invitation pour son organisation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2a admin A crée une invitation pour son organisation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.restricted_a);
  begin
    insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
    values (f.org_a, 'autre@example.com', encode(digest('token-restricted-' || f.org_a::text, 'sha256'), 'hex'), f.restricted_a, now() + interval '7 days');
    perform pg_temp.record('2b staff sans permission create -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('2b staff sans permission create -> refusé', 'PASS');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO — isolation cross-org : admin B ne voit pas les invitations
--    de l'organisation A.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_b);
  select count(*) into v_count from public.tenant_invitations where organization_id = f.org_a;

  if v_count = 0 then
    perform pg_temp.record('3 admin B ne voit aucune invitation de l''organisation A', 'PASS');
  else
    perform pg_temp.record('3 admin B ne voit aucune invitation de l''organisation A', 'FAIL', format('%s ligne(s) visible(s)', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO — révocation par admin A (UPDATE status), refusée pour
--    restreint A.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_inv_id uuid;
  v_status text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select id into v_inv_id from public.tenant_invitations where organization_id = f.org_a limit 1;

  perform pg_temp.act_as('authenticated', f.restricted_a);
  update public.tenant_invitations set status = 'revoquee' where id = v_inv_id;
  perform pg_temp.act_as_owner();
  select status into v_status from public.tenant_invitations where id = v_inv_id;
  if v_status = 'en_attente' then
    perform pg_temp.record('4a staff sans permission update -> aucune ligne modifiée', 'PASS');
  else
    perform pg_temp.record('4a staff sans permission update -> aucune ligne modifiée', 'FAIL', format('status=%L', v_status));
  end if;

  perform pg_temp.act_as('authenticated', f.admin_a);
  update public.tenant_invitations set status = 'revoquee' where id = v_inv_id;
  perform pg_temp.act_as_owner();
  select status into v_status from public.tenant_invitations where id = v_inv_id;
  if v_status = 'revoquee' then
    perform pg_temp.record('4b admin A révoque l''invitation -> autorisé', 'PASS');
  else
    perform pg_temp.record('4b admin A révoque l''invitation -> autorisé', 'FAIL', format('status=%L', v_status));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO — aucune policy DELETE : suppression toujours refusée, même
--    par l'admin de l'organisation.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_inv_id uuid;
  v_count_before int;
  v_count_after int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select id into v_inv_id from public.tenant_invitations where organization_id = f.org_a limit 1;
  select count(*) into v_count_before from public.tenant_invitations where id = v_inv_id;

  perform pg_temp.act_as('authenticated', f.admin_a);
  delete from public.tenant_invitations where id = v_inv_id;

  perform pg_temp.act_as_owner();
  select count(*) into v_count_after from public.tenant_invitations where id = v_inv_id;

  if v_count_before = 1 and v_count_after = 1 then
    perform pg_temp.record('5 aucune policy DELETE -> ligne toujours présente après tentative de suppression', 'PASS');
  else
    perform pg_temp.record('5 aucune policy DELETE -> ligne toujours présente après tentative de suppression', 'FAIL', format('avant=%s apres=%s', v_count_before, v_count_after));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO — aperçu pré-inscription, appelé SANS session (anon), jeton
--    valide vs jeton inconnu.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_token text := 'raw-token-preview-test';
  v_inv_id uuid;
  v_org_name text;
  v_none int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (f.org_a, 'preview@example.com', encode(digest(v_token, 'sha256'), 'hex'), f.admin_a, now() + interval '7 days')
  returning id into v_inv_id;

  perform pg_temp.act_as('anon', null);

  select organization_name into v_org_name
  from public.get_tenant_invitation_preview(v_token);

  if v_org_name = 'Test Org12d A' then
    perform pg_temp.record('6a aperçu (anon, jeton valide) -> nom d''organisation correct', 'PASS');
  else
    perform pg_temp.record('6a aperçu (anon, jeton valide) -> nom d''organisation correct', 'FAIL', format('obtenu=%L', v_org_name));
  end if;

  select count(*) into v_none from public.get_tenant_invitation_preview('jeton-qui-nexiste-pas');
  if v_none = 0 then
    perform pg_temp.record('6b aperçu (anon, jeton inconnu) -> aucun résultat', 'PASS');
  else
    perform pg_temp.record('6b aperçu (anon, jeton inconnu) -> aucun résultat', 'FAIL', format('%s ligne(s)', v_none));
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
