-- ============================================================================
-- TEST — Module 12g (check_tenant_invitation_existing_account).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805560000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12g_check_tenant_invitation_existing_account.sql
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

grant select, insert on pg_temp.test_results to authenticated, service_role, anon;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — un locataire réellement créé (via le vrai flux
--    d'inscription par invitation, org A), puis 3 invitations de test sur
--    l'organisation B : même email (compte existant), email neuf (pas de
--    compte), et une invitation expirée sur l'email existant.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a  uuid;
  v_org_b  uuid;
  v_tenant uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org12g A', 'test-org12g-a-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_a;

  insert into public.organizations (name, slug, country_code)
  values ('Test Org12g B', 'test-org12g-b-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_b;

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_a, 'existing-tenant-12g@example.com', encode(digest('token-fixture-setup-a', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  -- Vrai flux d'inscription : passe reellement par private.handle_new_user(),
  -- cree un authentique tenant_accounts (pas un insert manuel qui
  -- contournerait la logique reelle).
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant, 'existing-tenant-12g@example.com',
    jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-fixture-setup-a', 'full_name', 'Existing Tenant 12g'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- Invitation B1 : meme email, pour tester check() = true.
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_b, 'existing-tenant-12g@example.com', encode(digest('token-check-existing', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  -- Invitation B2 : email neuf, pour tester check() = false.
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_b, 'brand-new-12g@example.com', encode(digest('token-check-new', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  -- Invitation B3 : meme email existant, mais EXPIREE -- check() doit
  -- rester false malgre le compte existant, car le jeton lui-meme n'est
  -- plus valide.
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_b, 'existing-tenant-12g@example.com', encode(digest('token-check-expired', 'sha256'), 'hex'), p.id, now() - interval '1 day'
  from public.profiles p limit 1;

  create table pg_temp.fixtures as select v_org_a as org_a, v_org_b as org_b, v_tenant as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIOS — appelés en tant que anon (pas de session), comme le
--    ferait /invite/accept avant inscription.
-- ----------------------------------------------------------------------------

do $$
declare
  v_result boolean;
begin
  perform pg_temp.act_as('anon', null);

  select public.check_tenant_invitation_existing_account('token-check-existing') into v_result;
  if v_result is true then
    perform pg_temp.record('1 email deja locataire (jeton valide) -> true', 'PASS');
  else
    perform pg_temp.record('1 email deja locataire (jeton valide) -> true', 'FAIL', format('obtenu=%s', v_result));
  end if;

  select public.check_tenant_invitation_existing_account('token-check-new') into v_result;
  if v_result is false then
    perform pg_temp.record('2 email jamais vu (jeton valide) -> false', 'PASS');
  else
    perform pg_temp.record('2 email jamais vu (jeton valide) -> false', 'FAIL', format('obtenu=%s', v_result));
  end if;

  select public.check_tenant_invitation_existing_account('token-check-expired') into v_result;
  if v_result is false then
    perform pg_temp.record('3 email deja locataire mais jeton expire -> false', 'PASS');
  else
    perform pg_temp.record('3 email deja locataire mais jeton expire -> false', 'FAIL', format('obtenu=%s', v_result));
  end if;

  select public.check_tenant_invitation_existing_account('token-does-not-exist-at-all') into v_result;
  if v_result is false then
    perform pg_temp.record('4 jeton totalement inconnu -> false', 'PASS');
  else
    perform pg_temp.record('4 jeton totalement inconnu -> false', 'FAIL', format('obtenu=%s', v_result));
  end if;
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

select id, name, status, detail from pg_temp.test_results order by id;

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
