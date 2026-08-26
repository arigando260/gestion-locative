-- ============================================================================
-- TEST — Module 12m (table staff_invitations, RLS, aperçu pré-inscription,
-- détection compte existant).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Fixtures : org_a et org_b, chacune avec un admin réel (créé via
-- private.handle_new_user(), qui crée systématiquement une NOUVELLE
-- organisation pour un compte interne depuis le Module 12e -- aucune
-- fixture ne peut donc rattacher un second compte à une organisation
-- existante, la brique "invitation staff" étant justement ce qui manque
-- pour ça). Le scénario "staff sans permission" est couvert en révoquant
-- users:create sur le rôle admin d'une troisième organisation (org_c),
-- plutôt qu'en créant un second membre de même organisation avec un rôle
-- restreint (impossible sans bypass de trg_handle_new_user, qui échoue
-- lui-même : le rôle postgres de ce projet n'est pas propriétaire de
-- auth.users -- déjà rencontré et documenté au Module 12l).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805620000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12m_staff_invitations.sql
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
-- 1. FIXTURES — org_a (admin normal), org_b (admin normal, pour l'isolation
--    cross-org), org_c (admin dont users:create est révoqué juste après
--    création, pour isoler le test de has_permission()).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a       uuid;
  v_org_b       uuid;
  v_org_c       uuid;
  v_admin_a     uuid := gen_random_uuid();
  v_admin_b     uuid := gen_random_uuid();
  v_admin_c     uuid := gen_random_uuid();
  v_admin_role_c uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_a, 'admin-staffinv-a@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12m A',
      'organization_country', 'BJ', 'organization_phone', '90000010', 'full_name', 'Admin A'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_a from public.profiles where id = v_admin_a;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_b, 'admin-staffinv-b@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12m B',
      'organization_country', 'BJ', 'organization_phone', '90000011', 'full_name', 'Admin B'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_b from public.profiles where id = v_admin_b;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_c, 'admin-staffinv-c@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12m C',
      'organization_country', 'BJ', 'organization_phone', '90000012', 'full_name', 'Admin C'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_c from public.profiles where id = v_admin_c;

  select id into v_admin_role_c from public.roles where organization_id = v_org_c and code = 'admin';
  delete from public.role_permissions
  where role_id = v_admin_role_c and resource = 'users' and action = 'create';

  create table pg_temp.fixtures as
  select
    v_org_a   as org_a,   v_admin_a as admin_a,
    v_org_b   as org_b,   v_admin_b as admin_b,
    v_org_c   as org_c,   v_admin_c as admin_c;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role, anon;

-- ----------------------------------------------------------------------------
-- 2. INSERT — admin A crée une invitation pour son organisation -> autorisé.
--    admin C (users:create révoqué) -> refusé malgré organization_id correct.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  begin
    insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
    values (f.org_a, 'agent-invite-a@example.com', 'agent', encode(extensions.digest('token-a', 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');
    perform pg_temp.record('2a admin A crée une invitation role_code=agent pour son organisation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2a admin A crée une invitation role_code=agent pour son organisation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.admin_c);
  begin
    insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
    values (f.org_c, 'agent-invite-c@example.com', 'agent', encode(extensions.digest('token-c', 'sha256'), 'hex'), f.admin_c, now() + interval '7 days');
    perform pg_temp.record('2b admin C (users:create révoqué) -> refusé malgré organization_id correct', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('2b admin C (users:create révoqué) -> refusé malgré organization_id correct', 'PASS');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. CHECK CONSTRAINT — role_code hors ('admin','agent','comptable') refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_a);
  begin
    insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
    values (f.org_a, 'invalide@example.com', 'superadmin', encode(extensions.digest('token-invalid-role', 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');
    perform pg_temp.record('3 role_code=''superadmin'' -> refusé', 'FAIL', 'succès inattendu');
  exception when check_violation then
    perform pg_temp.record('3 role_code=''superadmin'' -> refusé', 'PASS');
  when others then
    perform pg_temp.record('3 role_code=''superadmin'' -> refusé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. ISOLATION CROSS-ORG — admin B ne voit pas les invitations de org_a.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin_b);
  select count(*) into v_count from public.staff_invitations where organization_id = f.org_a;

  if v_count = 0 then
    perform pg_temp.record('4 admin B ne voit aucune invitation de l''organisation A', 'PASS');
  else
    perform pg_temp.record('4 admin B ne voit aucune invitation de l''organisation A', 'FAIL', format('%s ligne(s) visible(s)', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. UPDATE (révocation) — admin A révoque sa propre invitation -> autorisé.
--    admin B ne peut pas révoquer une invitation de org_a.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_inv_id uuid;
  v_status text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select id into v_inv_id from public.staff_invitations where organization_id = f.org_a limit 1;

  perform pg_temp.act_as('authenticated', f.admin_b);
  update public.staff_invitations set status = 'revoquee' where id = v_inv_id;
  perform pg_temp.act_as_owner();
  select status into v_status from public.staff_invitations where id = v_inv_id;
  if v_status = 'en_attente' then
    perform pg_temp.record('5a admin B ne peut pas révoquer une invitation de org_a', 'PASS');
  else
    perform pg_temp.record('5a admin B ne peut pas révoquer une invitation de org_a', 'FAIL', format('status=%L', v_status));
  end if;

  perform pg_temp.act_as('authenticated', f.admin_a);
  update public.staff_invitations set status = 'revoquee' where id = v_inv_id;
  perform pg_temp.act_as_owner();
  select status into v_status from public.staff_invitations where id = v_inv_id;
  if v_status = 'revoquee' then
    perform pg_temp.record('5b admin A révoque sa propre invitation -> autorisé', 'PASS');
  else
    perform pg_temp.record('5b admin A révoque sa propre invitation -> autorisé', 'FAIL', format('status=%L', v_status));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. DELETE — aucune policy DELETE : suppression toujours refusée.
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
  select id into v_inv_id from public.staff_invitations where organization_id = f.org_a limit 1;
  select count(*) into v_count_before from public.staff_invitations where id = v_inv_id;

  perform pg_temp.act_as('authenticated', f.admin_a);
  delete from public.staff_invitations where id = v_inv_id;

  perform pg_temp.act_as_owner();
  select count(*) into v_count_after from public.staff_invitations where id = v_inv_id;

  if v_count_before = 1 and v_count_after = 1 then
    perform pg_temp.record('6 aucune policy DELETE -> ligne toujours présente après tentative', 'PASS');
  else
    perform pg_temp.record('6 aucune policy DELETE -> ligne toujours présente après tentative', 'FAIL', format('avant=%s apres=%s', v_count_before, v_count_after));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. APERÇU PRÉ-INSCRIPTION — anon, jeton valide vs jeton inconnu.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_token text := 'raw-token-staffinv-preview';
  v_org_name text;
  v_role_code text;
  v_none int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (f.org_a, 'preview-staffinv@example.com', 'comptable', encode(extensions.digest(v_token, 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');

  perform pg_temp.act_as('anon', null);

  select organization_name, role_code into v_org_name, v_role_code
  from public.get_staff_invitation_preview(v_token);

  if v_org_name = 'Org Test 12m A' and v_role_code = 'comptable' then
    perform pg_temp.record('7a aperçu (anon, jeton valide) -> organisation et rôle corrects', 'PASS');
  else
    perform pg_temp.record('7a aperçu (anon, jeton valide) -> organisation et rôle corrects', 'FAIL', format('org=%L role=%L', v_org_name, v_role_code));
  end if;

  select count(*) into v_none from public.get_staff_invitation_preview('jeton-staffinv-inconnu');
  if v_none = 0 then
    perform pg_temp.record('7b aperçu (anon, jeton inconnu) -> aucun résultat', 'PASS');
  else
    perform pg_temp.record('7b aperçu (anon, jeton inconnu) -> aucun résultat', 'FAIL', format('%s ligne(s)', v_none));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. DÉTECTION COMPTE EXISTANT — email déjà présent dans auth.users (staff
--    d'une autre organisation) -> true. Email inédit -> false. Jeton
--    invalide -> false (pas d'exception).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_token_existing text := 'token-staffinv-existing-account';
  v_token_new      text := 'token-staffinv-new-account';
  v_result boolean;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  -- Email déjà utilisé par admin B (staff d'une AUTRE organisation, org_b).
  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (f.org_a, 'admin-staffinv-b@example.com', 'agent', encode(extensions.digest(v_token_existing, 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (f.org_a, 'jamais-vu-staffinv@example.com', 'agent', encode(extensions.digest(v_token_new, 'sha256'), 'hex'), f.admin_a, now() + interval '7 days');

  perform pg_temp.act_as('anon', null);

  select public.check_staff_invitation_existing_account(v_token_existing) into v_result;
  if v_result = true then
    perform pg_temp.record('8a email déjà présent dans auth.users (staff d''une autre org) -> true', 'PASS');
  else
    perform pg_temp.record('8a email déjà présent dans auth.users (staff d''une autre org) -> true', 'FAIL', format('obtenu=%L', v_result));
  end if;

  select public.check_staff_invitation_existing_account(v_token_new) into v_result;
  if v_result = false then
    perform pg_temp.record('8b email inédit -> false', 'PASS');
  else
    perform pg_temp.record('8b email inédit -> false', 'FAIL', format('obtenu=%L', v_result));
  end if;

  select public.check_staff_invitation_existing_account('jeton-staffinv-totalement-inconnu') into v_result;
  if v_result = false then
    perform pg_temp.record('8c jeton invalide -> false (pas d''exception)', 'PASS');
  else
    perform pg_temp.record('8c jeton invalide -> false (pas d''exception)', 'FAIL', format('obtenu=%L', v_result));
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
