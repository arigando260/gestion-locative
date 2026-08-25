-- ============================================================================
-- TEST — Module 12i (properties_effective_status expose address_complement/
-- country_code/city/neighborhood au lieu de l'ancien "address").
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805580000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12i_properties_effective_status_address_fix.sql
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
-- 1. LA VUE EXPOSE LES BONNES COLONNES — les 4 nouvelles présentes, "address"
--    absente.
-- ----------------------------------------------------------------------------

do $$
declare
  v_missing int;
  v_has_old_address boolean;
begin
  select count(*) into v_missing
  from (values ('address_complement'), ('country_code'), ('city'), ('neighborhood')) as expected(col)
  where not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'properties_effective_status' and column_name = expected.col
  );

  if v_missing = 0 then
    perform pg_temp.record('1a les 4 nouvelles colonnes sont exposées par la vue', 'PASS');
  else
    perform pg_temp.record('1a les 4 nouvelles colonnes sont exposées par la vue', 'FAIL', format('%s colonne(s) manquante(s)', v_missing));
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'properties_effective_status' and column_name = 'address'
  ) into v_has_old_address;

  if not v_has_old_address then
    perform pg_temp.record('1b l''ancienne colonne "address" n''est plus exposée', 'PASS');
  else
    perform pg_temp.record('1b l''ancienne colonne "address" n''est plus exposée', 'FAIL');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. VALEURS CORRECTES — un bien de test avec des valeurs connues,
--    interrogé via la vue.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id  uuid;
  v_prop_id uuid;
  v_row     record;
begin
  insert into public.organizations (name, slug, country_code)
  values ('Test Org12i', 'test-org12i-' || substr(gen_random_uuid()::text, 1, 8), 'BJ')
  returning id into v_org_id;

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (v_org_id, 'Bien Test12i', 500000, 'longue_duree', 'BJ', 'Cotonou', 'Fidjrosse', 'Immeuble test 12i')
  returning id into v_prop_id;

  select country_code, city, neighborhood, address_complement, effective_status
  into v_row
  from public.properties_effective_status
  where id = v_prop_id;

  if v_row.country_code = 'BJ' and v_row.city = 'Cotonou' and v_row.neighborhood = 'Fidjrosse' and v_row.address_complement = 'Immeuble test 12i' then
    perform pg_temp.record('2a valeurs correctes exposées par la vue pour un bien de test', 'PASS');
  else
    perform pg_temp.record('2a valeurs correctes exposées par la vue pour un bien de test', 'FAIL', format('%s', row_to_json(v_row)));
  end if;

  if v_row.effective_status = 'disponible' then
    perform pg_temp.record('2b effective_status toujours calculé correctement (non régressé)', 'PASS');
  else
    perform pg_temp.record('2b effective_status toujours calculé correctement (non régressé)', 'FAIL', format('effective_status=%L', v_row.effective_status));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. RÉSUMÉ.
-- ----------------------------------------------------------------------------

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
