-- ============================================================================
-- TEST — Module 12b (organizations.country_code : NOT NULL, FK vers
-- countries, rétro-remplissage des organisations dev existantes).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805510000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12b_organizations_country.sql
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

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

select pg_temp.act_as_owner();

-- ----------------------------------------------------------------------------
-- 1. RÉTRO-REMPLISSAGE — toutes les organisations dev existantes doivent
--    avoir country_code = 'BJ'.
-- ----------------------------------------------------------------------------

do $$
declare
  v_missing int;
begin
  select count(*) into v_missing
  from public.organizations
  where country_code is distinct from 'BJ';

  if v_missing = 0 then
    perform pg_temp.record('1 toutes les organisations existantes ont country_code=''BJ''', 'PASS');
  else
    perform pg_temp.record('1 toutes les organisations existantes ont country_code=''BJ''', 'FAIL', format('%s organisation(s) sans BJ', v_missing));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. NOT NULL — insertion sans country_code refusée.
-- ----------------------------------------------------------------------------

do $$
begin
  begin
    insert into public.organizations (name, slug)
    values ('Test Org Sans Pays', 'test-org-sans-pays-' || substr(gen_random_uuid()::text, 1, 8));
    perform pg_temp.record('2 insertion sans country_code -> refusée', 'FAIL', 'succès inattendu');
  exception when not_null_violation then
    perform pg_temp.record('2 insertion sans country_code -> refusée', 'PASS');
  when others then
    perform pg_temp.record('2 insertion sans country_code -> refusée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. FK — country_code inexistant dans countries refusé.
-- ----------------------------------------------------------------------------

do $$
begin
  begin
    insert into public.organizations (name, slug, country_code)
    values ('Test Org Pays Invalide', 'test-org-pays-invalide-' || substr(gen_random_uuid()::text, 1, 8), 'ZZ');
    perform pg_temp.record('3 insertion avec country_code inconnu (''ZZ'') -> refusée', 'FAIL', 'succès inattendu');
  exception when foreign_key_violation then
    perform pg_temp.record('3 insertion avec country_code inconnu (''ZZ'') -> refusée', 'PASS');
  when others then
    perform pg_temp.record('3 insertion avec country_code inconnu (''ZZ'') -> refusée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Insertion valide -> autorisée, valeur bien stockée.
-- ----------------------------------------------------------------------------

do $$
declare
  v_id uuid;
  v_stored text;
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org Togo', 'test-org-togo-' || substr(gen_random_uuid()::text, 1, 8), 'TG')
  returning id into v_id;

  select country_code into v_stored from public.organizations where id = v_id;

  if v_stored = 'TG' then
    perform pg_temp.record('4 insertion avec country_code valide (''TG'') -> autorisée, valeur correcte', 'PASS');
  else
    perform pg_temp.record('4 insertion avec country_code valide (''TG'') -> autorisée, valeur correcte', 'FAIL', format('valeur stockée=%L', v_stored));
  end if;
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
