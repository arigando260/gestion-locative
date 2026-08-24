-- ============================================================================
-- TEST — Module 12e (correction de private.handle_new_user() : inscription
-- organisation self-service + acceptation d'invitation locataire).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Migration critique côté sécurité : couvre le chemin heureux (inscription
-- interne atomique), la preuve que organization_id fourni par le client est
-- totalement ignoré (le correctif Phase 1), et les 4 rejets côté invitation
-- locataire (jeton absent/inconnu/expiré, email non correspondant, réemploi
-- d'un jeton déjà accepté).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805540000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12e_handle_new_user_signup.sql
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

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

select pg_temp.act_as_owner();

-- ----------------------------------------------------------------------------
-- 1. INSCRIPTION INTERNE — chemin heureux : org + profil + rôle admin +
--    abonnement starter/essai créés atomiquement.
-- ----------------------------------------------------------------------------

do $$
declare
  v_user_id      uuid := gen_random_uuid();
  v_org_id       uuid;
  v_role_count   int;
  v_is_admin     boolean;
  v_sub_status   text;
  v_plan_code    text;
  v_org_country  text;
  v_org_phone    text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_user_id, 'victim-admin@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_name', 'Victim Org',
      'organization_country', 'BJ',
      'organization_phone', '90000000',
      'full_name', 'Victim Admin'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_user_id;

  if v_org_id is null then
    perform pg_temp.record('1a profil créé avec une organisation associée', 'FAIL', 'aucun profil trouvé');
  else
    perform pg_temp.record('1a profil créé avec une organisation associée', 'PASS');
  end if;

  select country_code, phone into v_org_country, v_org_phone from public.organizations where id = v_org_id;
  if v_org_country = 'BJ' and v_org_phone = '90000000' then
    perform pg_temp.record('1b organisation créée avec pays/téléphone corrects', 'PASS');
  else
    perform pg_temp.record('1b organisation créée avec pays/téléphone corrects', 'FAIL', format('country=%L phone=%L', v_org_country, v_org_phone));
  end if;

  select count(*) into v_role_count from public.roles where organization_id = v_org_id;
  if v_role_count = 3 then
    perform pg_temp.record('1c 3 rôles système créés (admin/agent/comptable)', 'PASS');
  else
    perform pg_temp.record('1c 3 rôles système créés (admin/agent/comptable)', 'FAIL', format('%s rôle(s)', v_role_count));
  end if;

  select exists (
    select 1 from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = v_user_id and r.code = 'admin' and r.organization_id = v_org_id
  ) into v_is_admin;
  if v_is_admin then
    perform pg_temp.record('1d utilisateur affecté au rôle admin de sa nouvelle organisation', 'PASS');
  else
    perform pg_temp.record('1d utilisateur affecté au rôle admin de sa nouvelle organisation', 'FAIL');
  end if;

  select os.status, sp.code into v_sub_status, v_plan_code
  from public.organization_subscriptions os
  join public.subscription_plans sp on sp.id = os.plan_id
  where os.organization_id = v_org_id;
  if v_sub_status = 'essai' and v_plan_code = 'starter' then
    perform pg_temp.record('1e abonnement starter/essai créé automatiquement', 'PASS');
  else
    perform pg_temp.record('1e abonnement starter/essai créé automatiquement', 'FAIL', format('status=%L plan=%L', v_sub_status, v_plan_code));
  end if;

  create table pg_temp.fixtures as select v_user_id as victim_admin_id, v_org_id as victim_org_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. TENTATIVE DE FALSIFICATION — organization_id fourni par le client est
--    ignoré : une NOUVELLE organisation est créée, jamais un rattachement
--    à l'organisation "victime".
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_attacker_id  uuid := gen_random_uuid();
  v_attacker_org uuid;
begin
  select * into f from pg_temp.fixtures;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_attacker_id, 'attacker@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_id', f.victim_org_id,   -- falsifié : tente de rejoindre l'org victime
      'organization_name', 'Attacker Org',
      'organization_country', 'BJ',
      'organization_phone', '90111111',
      'full_name', 'Attacker'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_attacker_org from public.profiles where id = v_attacker_id;

  if v_attacker_org is distinct from f.victim_org_id and v_attacker_org is not null then
    perform pg_temp.record('2a organization_id falsifié ignoré -> nouvelle organisation distincte créée', 'PASS');
  else
    perform pg_temp.record('2a organization_id falsifié ignoré -> nouvelle organisation distincte créée', 'FAIL', format('org obtenue=%L (org victime=%L)', v_attacker_org, f.victim_org_id));
  end if;

  if not exists (
    select 1 from public.organizations where id = v_attacker_org and name = 'Attacker Org'
  ) then
    perform pg_temp.record('2b la nouvelle organisation porte bien le nom fourni ("Attacker Org")', 'FAIL');
  else
    perform pg_temp.record('2b la nouvelle organisation porte bien le nom fourni ("Attacker Org")', 'PASS');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. INSCRIPTION INTERNE INCOMPLÈTE — pays manquant -> refusée avec le bon
--    slug.
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'incomplete@example.com',
      jsonb_build_object(
        'account_type', 'internal',
        'organization_name', 'Org Incomplete',
        'organization_phone', '90222222'
        -- organization_country volontairement absent
      ),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('3 inscription interne sans pays -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 inscription interne sans pays -> refusée', v_detail, 'handle_new_user.internal.organization_country_missing');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. INVITATION LOCATAIRE — chemin heureux.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_inv_id      uuid;
  v_tenant_id   uuid := gen_random_uuid();
  v_membership  record;
  v_inv_status  text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (f.victim_org_id, 'tenant-ok@example.com', encode(digest('token-ok', 'sha256'), 'hex'), f.victim_admin_id, now() + interval '7 days')
  returning id into v_inv_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-ok@example.com',
    jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-ok', 'full_name', 'Tenant OK', 'phone', '91000000'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select tenant_account_id, organization_id, status into v_membership
  from public.tenant_organization_memberships
  where tenant_account_id = v_tenant_id;

  if v_membership.organization_id = f.victim_org_id and v_membership.status = 'actif' then
    perform pg_temp.record('4a locataire rattaché à l''organisation invitante, statut actif', 'PASS');
  else
    perform pg_temp.record('4a locataire rattaché à l''organisation invitante, statut actif', 'FAIL', format('%s', row_to_json(v_membership)));
  end if;

  select status into v_inv_status from public.tenant_invitations where id = v_inv_id;
  if v_inv_status = 'acceptee' then
    perform pg_temp.record('4b invitation marquée acceptée', 'PASS');
  else
    perform pg_temp.record('4b invitation marquée acceptée', 'FAIL', format('status=%L', v_inv_status));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. JETON INCONNU -> refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'tenant-bad@example.com',
      jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-does-not-exist'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('5 jeton inconnu -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5 jeton inconnu -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. JETON EXPIRÉ -> refusé, même slug.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (f.victim_org_id, 'tenant-expired@example.com', encode(digest('token-expired', 'sha256'), 'hex'), f.victim_admin_id, now() - interval '1 day');

  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'tenant-expired@example.com',
      jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-expired'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('6 jeton expiré -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6 jeton expiré -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. EMAIL NE CORRESPONDANT PAS À L'INVITATION -> refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (f.victim_org_id, 'intended@example.com', encode(digest('token-mismatch', 'sha256'), 'hex'), f.victim_admin_id, now() + interval '7 days');

  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'wrong@example.com',
      jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-mismatch'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('7 email ne correspondant pas à l''invitation -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7 email ne correspondant pas à l''invitation -> refusé', v_detail, 'tenant_invitation.accept.email_mismatch');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. AUCUN JETON FOURNI -> refusé, bon slug.
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'tenant-no-token@example.com',
      jsonb_build_object('account_type', 'tenant'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('8 aucun jeton fourni -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('8 aucun jeton fourni -> refusé', v_detail, 'handle_new_user.tenant.invitation_token_missing');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. RÉEMPLOI D'UN JETON DÉJÀ ACCEPTÉ (scénario 4) -> refusé, usage unique
--    garanti.
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  begin
    -- Email different de celui du scenario 4 : on veut isoler le rejet sur
    -- le statut du jeton (deja accepte), pas sur la contrainte d'unicite
    -- d'auth.users.email qui interceptait sinon la tentative avant meme que
    -- le trigger ne s'execute.
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'tenant-ok-reuse-attempt@example.com',
      jsonb_build_object('account_type', 'tenant', 'invitation_token', 'token-ok'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('9 réemploi d''un jeton déjà accepté -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('9 réemploi d''un jeton déjà accepté -> refusé', v_detail, 'tenant_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 10. RÉSUMÉ.
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
