-- ============================================================================
-- TEST — Module 12k (private.handle_new_user() lit organization_type
-- depuis les métadonnées, optionnel).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Ne re-teste pas ce que module12e_handle_new_user_signup.sql couvre déjà
-- (chemin locataire, rejets organization_id ignoré, jetons invalides...) --
-- uniquement le comportement ajouté ici : organization_type lu quand
-- présent, absent sans exception sinon.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805600000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12k_handle_new_user_organization_type.sql
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
-- 1. organization_type ABSENT des métadonnées -> inscription toujours
--    autorisée, valeur NULL (pas d'exception, comportement pré-12k
--    préservé pour tout signup n'envoyant pas ce champ).
-- ----------------------------------------------------------------------------

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_org_id  uuid;
  v_stored  text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_user_id, 'org12k-no-type@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_name', 'Org12k No Type',
      'organization_country', 'BJ',
      'organization_phone', '90000001',
      'full_name', 'Sans Type'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_user_id;
  select organization_type into v_stored from public.organizations where id = v_org_id;

  if v_org_id is not null and v_stored is null then
    perform pg_temp.record('1 organization_type absent -> inscription OK, valeur NULL', 'PASS');
  else
    perform pg_temp.record('1 organization_type absent -> inscription OK, valeur NULL', 'FAIL', format('org_id=%L organization_type=%L', v_org_id, v_stored));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. organization_type='proprietaire' -> stocké correctement.
-- ----------------------------------------------------------------------------

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_org_id  uuid;
  v_stored  text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_user_id, 'org12k-owner@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_name', 'Org12k Owner',
      'organization_country', 'BJ',
      'organization_phone', '90000002',
      'full_name', 'Proprio Test',
      'organization_type', 'proprietaire'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_user_id;
  select organization_type into v_stored from public.organizations where id = v_org_id;

  if v_stored = 'proprietaire' then
    perform pg_temp.record('2 organization_type=''proprietaire'' -> stocké correctement', 'PASS');
  else
    perform pg_temp.record('2 organization_type=''proprietaire'' -> stocké correctement', 'FAIL', format('organization_type=%L', v_stored));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. organization_type='agence' -> stocké correctement.
-- ----------------------------------------------------------------------------

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_org_id  uuid;
  v_stored  text;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_user_id, 'org12k-agency@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'organization_name', 'Org12k Agency',
      'organization_country', 'BJ',
      'organization_phone', '90000003',
      'full_name', 'Agence Test',
      'organization_type', 'agence'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_user_id;
  select organization_type into v_stored from public.organizations where id = v_org_id;

  if v_stored = 'agence' then
    perform pg_temp.record('3 organization_type=''agence'' -> stocké correctement', 'PASS');
  else
    perform pg_temp.record('3 organization_type=''agence'' -> stocké correctement', 'FAIL', format('organization_type=%L', v_stored));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. RÉGRESSION — organization_name toujours obligatoire (comportement
--    Module 12e préservé, l'ajout d'un champ optionnel de plus ne doit rien
--    changer aux validations existantes).
-- ----------------------------------------------------------------------------

do $$
declare
  v_user_id uuid := gen_random_uuid();
  v_detail  text;
begin
  begin
    insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
    values (
      v_user_id, 'org12k-missing-name@example.com',
      jsonb_build_object(
        'account_type', 'internal',
        'organization_country', 'BJ',
        'organization_phone', '90000004',
        'full_name', 'Sans Nom Org',
        'organization_type', 'proprietaire'
      ),
      '{}'::jsonb, 'authenticated', 'authenticated'
    );
    perform pg_temp.record('4 organization_name toujours obligatoire (régression 12e)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail(
      '4 organization_name toujours obligatoire (régression 12e)',
      v_detail,
      'handle_new_user.internal.organization_name_missing'
    );
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
