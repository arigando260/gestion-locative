-- ============================================================================
-- TEST — Module 12c (properties.address -> address_complement, colonnes
-- country_code/city/neighborhood, backfill du pays hérité).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805520000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12c_properties_structured_address.sql
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
-- 1. RENAME — une valeur connue de l'ancien texte libre a bien survécu dans
--    address_complement (échantillon observé au diagnostic : "sekandji").
-- ----------------------------------------------------------------------------

do $$
declare
  v_count int;
begin
  select count(*) into v_count
  from public.properties
  where address_complement = 'sekandji';

  if v_count >= 1 then
    perform pg_temp.record('1 valeur connue (''sekandji'') préservée dans address_complement après RENAME', 'PASS');
  else
    perform pg_temp.record('1 valeur connue (''sekandji'') préservée dans address_complement après RENAME', 'FAIL', 'valeur introuvable');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. BACKFILL — les biens existants ont le country_code de leur
--    organisation (pas de NULL orphelin).
-- ----------------------------------------------------------------------------

do $$
declare
  v_mismatch int;
begin
  select count(*) into v_mismatch
  from public.properties p
  join public.organizations o on o.id = p.organization_id
  where p.country_code is distinct from o.country_code;

  if v_mismatch = 0 then
    perform pg_temp.record('2 country_code de chaque bien = country_code de son organisation', 'PASS');
  else
    perform pg_temp.record('2 country_code de chaque bien = country_code de son organisation', 'FAIL', format('%s bien(s) désynchronisé(s)', v_mismatch));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. PAS D'INVENTION DE DONNÉE — city/neighborhood restent NULL pour un
--    bien existant (le même échantillon connu qu'au point 1).
-- ----------------------------------------------------------------------------

do $$
declare
  v_city        text;
  v_neighborhood text;
begin
  select city, neighborhood into v_city, v_neighborhood
  from public.properties
  where address_complement = 'sekandji'
  limit 1;

  if v_city is null and v_neighborhood is null then
    perform pg_temp.record('3 city/neighborhood non inventés pour un bien existant', 'PASS');
  else
    perform pg_temp.record('3 city/neighborhood non inventés pour un bien existant', 'FAIL', format('city=%L neighborhood=%L', v_city, v_neighborhood));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. address_complement DÉSORMAIS OPTIONNEL — insertion sans complément
--    autorisée.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id uuid;
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org Module12c', 'test-org-module12c-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_id;

  create table pg_temp.fixtures as select v_org_id as org_id;

  begin
    insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood)
    values (v_org_id, 'Bien Module12c Sans Complement', 500000, 'longue_duree', 'BJ', 'Cotonou', 'Akpakpa');
    perform pg_temp.record('4 insertion sans address_complement -> autorisée', 'PASS');
  exception when others then
    perform pg_temp.record('4 insertion sans address_complement -> autorisée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 5. INSERTION COMPLÈTE — pays/ville/quartier/complément tous renseignés,
--    valeurs bien stockées.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_id uuid;
  v_row record;
begin
  select * into f from pg_temp.fixtures;

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (f.org_id, 'Bien Module12c Complet', 500000, 'longue_duree', 'BJ', 'Cotonou', 'Fidjrossè', 'Immeuble bleu, 2e étage')
  returning id into v_id;

  select country_code, city, neighborhood, address_complement into v_row
  from public.properties where id = v_id;

  if v_row.country_code = 'BJ' and v_row.city = 'Cotonou' and v_row.neighborhood = 'Fidjrossè' and v_row.address_complement = 'Immeuble bleu, 2e étage' then
    perform pg_temp.record('5 insertion avec adresse structurée complète -> valeurs correctement stockées', 'PASS');
  else
    perform pg_temp.record('5 insertion avec adresse structurée complète -> valeurs correctement stockées', 'FAIL', format('%s', row_to_json(v_row)));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. FK — country_code inexistant refusé sur properties aussi.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.properties (organization_id, name, price, location_type, country_code)
    values (f.org_id, 'Bien Module12c Pays Invalide', 500000, 'longue_duree', 'ZZ');
    perform pg_temp.record('6 insertion avec country_code inconnu (''ZZ'') -> refusée', 'FAIL', 'succès inattendu');
  exception when foreign_key_violation then
    perform pg_temp.record('6 insertion avec country_code inconnu (''ZZ'') -> refusée', 'PASS');
  when others then
    perform pg_temp.record('6 insertion avec country_code inconnu (''ZZ'') -> refusée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. RÉSUMÉ.
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
