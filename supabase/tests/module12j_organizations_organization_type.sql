-- ============================================================================
-- TEST — Module 12j (organizations.organization_type : nullable, check
-- constraint proprietaire/agence).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805590000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12j_organizations_organization_type.sql
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

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

select pg_temp.act_as_owner();

-- ----------------------------------------------------------------------------
-- 1. NULLABLE — insertion sans organization_type toujours autorisée (aucun
--    backfill, aucune contrainte NOT NULL posée).
-- ----------------------------------------------------------------------------

do $$
declare
  v_id uuid;
  v_stored text;
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org12j Sans Type', 'test-org12j-sans-type-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_id;

  select organization_type into v_stored from public.organizations where id = v_id;

  if v_stored is null then
    perform pg_temp.record('1 insertion sans organization_type -> autorisée, valeur NULL', 'PASS');
  else
    perform pg_temp.record('1 insertion sans organization_type -> autorisée, valeur NULL', 'FAIL', format('valeur stockée=%L', v_stored));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. CHECK CONSTRAINT — valeur hors ('proprietaire', 'agence') refusée.
-- ----------------------------------------------------------------------------

do $$
begin
  begin
    insert into public.organizations (name, slug, country_code, organization_type)
    values ('Test Org12j Type Invalide', 'test-org12j-type-invalide-' || substr(gen_random_uuid()::text, 1, 8), 'BJ', 'notaire');
    perform pg_temp.record('2 organization_type=''notaire'' -> refusée', 'FAIL', 'succès inattendu');
  exception when check_violation then
    perform pg_temp.record('2 organization_type=''notaire'' -> refusée', 'PASS');
  when others then
    perform pg_temp.record('2 organization_type=''notaire'' -> refusée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. VALEURS VALIDES — 'proprietaire' et 'agence' toutes deux acceptées,
--    valeur correctement stockée.
-- ----------------------------------------------------------------------------

do $$
declare
  v_id_owner  uuid;
  v_id_agency uuid;
  v_stored_owner  text;
  v_stored_agency text;
begin
  insert into public.organizations (name, slug, country_code, organization_type)
  values ('Test Org12j Proprietaire', 'test-org12j-proprietaire-' || substr(gen_random_uuid()::text, 1, 8), 'BJ', 'proprietaire')
  returning id into v_id_owner;

  insert into public.organizations (name, slug, country_code, organization_type)
  values ('Test Org12j Agence', 'test-org12j-agence-' || substr(gen_random_uuid()::text, 1, 8), 'BJ', 'agence')
  returning id into v_id_agency;

  select organization_type into v_stored_owner from public.organizations where id = v_id_owner;
  select organization_type into v_stored_agency from public.organizations where id = v_id_agency;

  if v_stored_owner = 'proprietaire' and v_stored_agency = 'agence' then
    perform pg_temp.record('3 organization_type=''proprietaire''/''agence'' -> autorisées, valeurs correctes', 'PASS');
  else
    perform pg_temp.record('3 organization_type=''proprietaire''/''agence'' -> autorisées, valeurs correctes', 'FAIL', format('proprietaire=%L agence=%L', v_stored_owner, v_stored_agency));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. RÉSUMÉ.
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
