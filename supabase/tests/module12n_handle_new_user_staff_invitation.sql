-- ============================================================================
-- TEST — Module 12n (private.handle_new_user() : rattachement à une
-- organisation existante via staff_invitations).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805630000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12n_handle_new_user_staff_invitation.sql
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

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

select pg_temp.act_as_owner();

-- ----------------------------------------------------------------------------
-- 1. FIXTURE — une organisation (admin réel, chemin inchangé) + 5
--    invitations couvrant chaque scénario.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id      uuid;
  v_admin_user  uuid := gen_random_uuid();
  v_org_count_before int;
begin
  select count(*) into v_org_count_before from public.organizations;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_user, 'admin-12n@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12n',
      'organization_country', 'BJ', 'organization_phone', '90000020', 'full_name', 'Admin 12n'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_id from public.profiles where id = v_admin_user;

  if v_org_id is not null then
    perform pg_temp.record('1a chemin sans jeton (inchangé) : nouvelle organisation créée normalement', 'PASS');
  else
    perform pg_temp.record('1a chemin sans jeton (inchangé) : nouvelle organisation créée normalement', 'FAIL', 'aucun profil créé');
  end if;

  -- Invitation valide, role_code=agent.
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'agent-12n@example.com', 'agent', encode(extensions.digest('token-12n-agent', 'sha256'), 'hex'), v_admin_user, now() + interval '7 days');

  -- Invitation valide, role_code=admin (un deuxième admin pour la même organisation).
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'admin2-12n@example.com', 'admin', encode(extensions.digest('token-12n-admin2', 'sha256'), 'hex'), v_admin_user, now() + interval '7 days');

  -- Invitation valide mais pour un email différent (test email_mismatch).
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'destinataire-attendu@example.com', 'comptable', encode(extensions.digest('token-12n-mismatch', 'sha256'), 'hex'), v_admin_user, now() + interval '7 days');

  -- Invitation déjà expirée.
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'expiree-12n@example.com', 'agent', encode(extensions.digest('token-12n-expired', 'sha256'), 'hex'), v_admin_user, now() - interval '1 hour');

  -- Invitation déjà acceptée (pour tester le réemploi).
  insert into public.staff_invitations (organization_id, email, role_code, status, token_hash, invited_by, expires_at, accepted_at, accepted_by)
  values (v_org_id, 'deja-acceptee-12n@example.com', 'agent', 'acceptee', encode(extensions.digest('token-12n-reused', 'sha256'), 'hex'), v_admin_user, now() + interval '7 days', now(), v_admin_user);

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_admin_user as admin_user, v_org_count_before as org_count_before;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. CHEMIN HEUREUX — role_code=agent : rattachement à l'organisation
--    EXISTANTE (aucune nouvelle organisation créée), bon rôle, invitation
--    marquée acceptée.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_new_user       uuid := gen_random_uuid();
  v_profile_org_id uuid;
  v_role_code      text;
  v_inv_status     text;
  v_inv_accepted_by uuid;
  v_org_count_after int;
begin
  select * into f from pg_temp.fixtures;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_new_user, 'agent-12n@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-12n-agent', 'full_name', 'Agent Invité 12n'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_profile_org_id from public.profiles where id = v_new_user;
  if v_profile_org_id = f.org_id then
    perform pg_temp.record('2a profil créé rattaché à l''organisation EXISTANTE (pas une nouvelle)', 'PASS');
  else
    perform pg_temp.record('2a profil créé rattaché à l''organisation EXISTANTE (pas une nouvelle)', 'FAIL', format('org attendue=%L, obtenue=%L', f.org_id, v_profile_org_id));
  end if;

  select count(*) into v_org_count_after from public.organizations;
  if v_org_count_after = f.org_count_before + 1 then
    perform pg_temp.record('2b aucune organisation supplémentaire créée pour ce rattachement', 'PASS');
  else
    perform pg_temp.record('2b aucune organisation supplémentaire créée pour ce rattachement', 'FAIL', format('avant=%s après=%s (attendu +1 pour la fixture admin uniquement)', f.org_count_before, v_org_count_after));
  end if;

  select r.code into v_role_code
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where ur.user_id = v_new_user;
  if v_role_code = 'agent' then
    perform pg_temp.record('2c rôle attribué correspond à role_code de l''invitation (agent)', 'PASS');
  else
    perform pg_temp.record('2c rôle attribué correspond à role_code de l''invitation (agent)', 'FAIL', format('obtenu=%L', v_role_code));
  end if;

  select status, accepted_by into v_inv_status, v_inv_accepted_by
  from public.staff_invitations where token_hash = encode(extensions.digest('token-12n-agent', 'sha256'), 'hex');
  if v_inv_status = 'acceptee' and v_inv_accepted_by = v_new_user then
    perform pg_temp.record('2d invitation marquée acceptée, accepted_by correct', 'PASS');
  else
    perform pg_temp.record('2d invitation marquée acceptée, accepted_by correct', 'FAIL', format('status=%L accepted_by=%L', v_inv_status, v_inv_accepted_by));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. role_code=admin : un deuxième admin rejoint la MÊME organisation
--    (jamais accordé par self-signup avant cette brique).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_new_user  uuid := gen_random_uuid();
  v_role_code text;
  v_org_id    uuid;
begin
  select * into f from pg_temp.fixtures;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_new_user, 'admin2-12n@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-12n-admin2', 'full_name', 'Second Admin 12n'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_new_user;
  select r.code into v_role_code
  from public.user_roles ur join public.roles r on r.id = ur.role_id
  where ur.user_id = v_new_user;

  if v_org_id = f.org_id and v_role_code = 'admin' then
    perform pg_temp.record('3 role_code=admin -> second admin rattaché à la même organisation', 'PASS');
  else
    perform pg_temp.record('3 role_code=admin -> second admin rattaché à la même organisation', 'FAIL', format('org=%L role=%L', v_org_id, v_role_code));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. REJETS — jeton inconnu, email non correspondant, invitation expirée,
--    jeton déjà accepté (réemploi).
-- ----------------------------------------------------------------------------

do $$
declare
  v_detail text;
begin
  -- 4a jeton totalement inconnu.
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'inconnu-12n@example.com',
      jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-jamais-emis-12n', 'full_name', 'Inconnu 12n'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('4a jeton inconnu -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4a jeton inconnu -> refusé', v_detail, 'staff_invitation.accept.invalid_or_expired');
  end;

  -- 4b email ne correspondant pas à l'invitation (jeton valide, mauvais compte).
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'mauvais-destinataire-12n@example.com',
      jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-12n-mismatch', 'full_name', 'Mauvais Destinataire 12n'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('4b email ne correspondant pas à l''invitation -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4b email ne correspondant pas à l''invitation -> refusé', v_detail, 'staff_invitation.accept.email_mismatch');
  end;

  -- 4c invitation expirée.
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'expiree-12n@example.com',
      jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-12n-expired', 'full_name', 'Expiree 12n'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('4c invitation expirée -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4c invitation expirée -> refusée', v_detail, 'staff_invitation.accept.invalid_or_expired');
  end;

  -- 4d jeton déjà accepté (réemploi).
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      gen_random_uuid(), 'reemploi-12n@example.com',
      jsonb_build_object('account_type', 'internal', 'staff_invitation_token', 'token-12n-reused', 'full_name', 'Reemploi 12n'),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('4d réemploi d''un jeton déjà accepté -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4d réemploi d''un jeton déjà accepté -> refusé', v_detail, 'staff_invitation.accept.invalid_or_expired');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. RÉSUMÉ.
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
