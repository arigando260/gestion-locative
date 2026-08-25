-- ============================================================================
-- TEST — Module 12h (accept_tenant_invitation_existing_account).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805570000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12h_accept_tenant_invitation_existing_account.sql
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

grant select, insert on pg_temp.test_results to authenticated, service_role, anon;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
--
-- - Un locataire reel (org A, via le vrai flux d'inscription) + une
--   invitation de l'org B pour son email (scenario heureux).
-- - Un deuxieme locataire reel (org A2) pour tester le rejet "mauvais
--   compte connecte".
-- - Un compte STAFF (org C, vrai flux d'inscription interne) dont l'email
--   correspond a une invitation, mais qui n'a pas de tenant_accounts --
--   pour tester la garde specifique.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a   uuid;
  v_org_a2  uuid;
  v_org_b   uuid;
  v_org_c   uuid;
  v_tenant  uuid := gen_random_uuid();
  v_tenant2 uuid := gen_random_uuid();
  v_staff   uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org12h A', 'test-org12h-a-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_a;

  insert into public.organizations (name, slug, country_code)
  values ('Test Org12h A2', 'test-org12h-a2-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_a2;

  insert into public.organizations (name, slug, country_code)
  values ('Test Org12h B', 'test-org12h-b-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_b;

  -- Locataire 1, deja rattache a org A -- futur "compte existant" pour le
  -- scenario heureux (rattachement a org B).
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_a, 'tenant-happy-12h@example.com', encode(digest('token-setup-happy', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant, 'tenant-happy-12h@example.com',
    jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-setup-happy', 'full_name', 'Tenant Happy 12h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- Locataire 2, rattache a org A2 -- va tenter d'accepter l'invitation
  -- destinee au locataire 1 (mauvais compte connecte).
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_a2, 'tenant-wrong-12h@example.com', encode(digest('token-setup-wrong', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant2, 'tenant-wrong-12h@example.com',
    jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-setup-wrong', 'full_name', 'Tenant Wrong 12h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- Compte STAFF (pas locataire) dont l'email va correspondre a une
  -- invitation -- pour tester la garde tenant_accounts.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff, 'staff-collision-12h@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_name', 'Test Org12h StaffOnly', 'organization_country', 'BJ', 'organization_phone', '90444444', 'full_name', 'Staff Collision 12h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_c from public.profiles where id = v_staff;

  -- Invitations sur org B : la cible du scenario heureux, plus une pour le
  -- staff (email correspondant, aucun tenant_accounts). org B n'a
  -- elle-meme aucun profil staff (jamais de vrai signup interne dessus) --
  -- invited_by n'a pas besoin d'appartenir a org B (aucune contrainte en
  -- ce sens en base), n'importe quel profil valide suffit ici.
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_b, 'tenant-happy-12h@example.com', encode(digest('token-accept-happy', 'sha256'), 'hex'), p.id, now() + interval '7 days'
  from public.profiles p limit 1;

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (v_org_b, 'staff-collision-12h@example.com', encode(digest('token-accept-staffonly', 'sha256'), 'hex'), v_staff, now() + interval '7 days');

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  select v_org_b, 'tenant-happy-12h@example.com', encode(digest('token-accept-expired', 'sha256'), 'hex'), p.id, now() - interval '1 day'
  from public.profiles p limit 1;

  create table pg_temp.fixtures as
  select v_org_a as org_a, v_org_a2 as org_a2, v_org_b as org_b, v_org_c as org_c,
         v_tenant as tenant_id, v_tenant2 as tenant2_id, v_staff as staff_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — anon (pas de session) -> refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  perform pg_temp.act_as('anon', null);
  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-happy');
    perform pg_temp.record('1 pas de session -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('1 pas de session -> refusé', v_detail, 'tenant_invitation.accept_existing.not_authenticated');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — jeton invalide/expiré -> refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  perform pg_temp.act_as_owner();
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-expired');
    perform pg_temp.record('2 jeton expiré -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 jeton expiré -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;

  begin
    perform public.accept_tenant_invitation_existing_account('token-completely-unknown');
    perform pg_temp.record('2b jeton inconnu -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2b jeton inconnu -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — mauvais compte connecté (email ne correspond pas) ->
--    refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  perform pg_temp.act_as_owner();
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant2_id);

  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-happy');
    perform pg_temp.record('3 mauvais compte connecté -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 mauvais compte connecté -> refusé', v_detail, 'tenant_invitation.accept.email_mismatch');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — compte STAFF sans tenant_accounts, email correspondant
--    -> refusé par la garde dédiée, pas une violation de clé étrangère
--    brute.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  perform pg_temp.act_as_owner();
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-staffonly');
    perform pg_temp.record('4 compte staff sans tenant_accounts -> refusé proprement', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 compte staff sans tenant_accounts -> refusé proprement', v_detail, 'tenant_invitation.accept_existing.not_a_tenant_account');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — chemin heureux : bon compte, bon jeton -> rattachement
--    créé, invitation acceptée.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_membership_status text;
  v_invitation_status text;
begin
  perform pg_temp.act_as_owner();
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-happy');
    perform pg_temp.record('5a acceptation avec le bon compte -> aucune exception', 'PASS');
  exception when others then
    perform pg_temp.record('5a acceptation avec le bon compte -> aucune exception', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();

  select status into v_membership_status
  from public.tenant_organization_memberships
  where tenant_account_id = f.tenant_id and organization_id = f.org_b;
  if v_membership_status = 'actif' then
    perform pg_temp.record('5b rattachement à org B créé, statut actif', 'PASS');
  else
    perform pg_temp.record('5b rattachement à org B créé, statut actif', 'FAIL', format('status=%L', v_membership_status));
  end if;

  select status into v_invitation_status
  from public.tenant_invitations
  where token_hash = encode(digest('token-accept-happy', 'sha256'), 'hex');
  if v_invitation_status = 'acceptee' then
    perform pg_temp.record('5c invitation marquée acceptée', 'PASS');
  else
    perform pg_temp.record('5c invitation marquée acceptée', 'FAIL', format('status=%L', v_invitation_status));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIO 6 — réemploi du même jeton (déjà accepté) -> refusé, même
--    slug que jeton invalide/expiré (usage unique garanti).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  perform pg_temp.act_as_owner();
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    perform public.accept_tenant_invitation_existing_account('token-accept-happy');
    perform pg_temp.record('6 réemploi d''un jeton déjà accepté -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6 réemploi d''un jeton déjà accepté -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. RÉSUMÉ.
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
