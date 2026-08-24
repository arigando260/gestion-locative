-- ============================================================================
-- TEST — Module 11 (limite de biens par palier d'abonnement, migration
-- 20260805490000_module11_subscription_plans_and_property_limit.sql).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents (module6e/
-- module7b/module8/module9) : transaction begin/rollback, helpers pg_temp,
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Couvre : limite respectée, dépassement bloqué avec le bon slug DETAIL,
-- non-régression sur les organisations existantes (rétro-remplissage
-- 'actif'/palier illimité).
--
-- NE couvre PAS la concurrence réelle : un script à transaction unique ne
-- peut pas faire s'exécuter deux transactions en parallèle contre
-- elles-mêmes — le verrou FOR UPDATE ne peut être prouvé qu'avec deux
-- connexions distinctes réellement concurrentes. Voir le script séparé
-- verify-property-limit-lock.mjs (Node, deux connexions pg) pour cette
-- partie-là.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805490000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module11_subscription_plans_and_property_limit.sql
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

grant select, insert on pg_temp.test_results to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — org de test (auto-seed starter/essai via trigger), palier de
--    test à limite volontairement basse (2), pour ne pas avoir à créer 10
--    biens pour atteindre la limite réelle du palier Starter.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id      uuid;
  v_test_plan   uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org Module11', 'test-org-module11-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into public.subscription_plans (code, name, max_properties, trial_days, monthly_price, sort_order, is_active)
  values ('test_limit_2', 'Test Limite 2', 2, 14, 0, 999, false)
  returning id into v_test_plan;

  update public.organization_subscriptions
  set plan_id = v_test_plan
  where organization_id = v_org_id;

  create table pg_temp.fixtures as select v_org_id as org_id, v_test_plan as test_plan_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — deux biens sous la limite (2) : autorisés.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.properties (organization_id, name, address, price, location_type)
    values (f.org_id, 'Bien Module11 A', '1 rue du Test', 500000, 'longue_duree');
    perform pg_temp.record('1a premier bien (0 -> 1, limite 2) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('1a premier bien (0 -> 1, limite 2) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  begin
    insert into public.properties (organization_id, name, address, price, location_type)
    values (f.org_id, 'Bien Module11 B', '2 rue du Test', 500000, 'longue_duree');
    perform pg_temp.record('1b deuxième bien (1 -> 2, limite 2) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('1b deuxième bien (1 -> 2, limite 2) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — troisième bien au-delà de la limite (2) : refusé, avec le
--    bon slug DETAIL.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.properties (organization_id, name, address, price, location_type)
    values (f.org_id, 'Bien Module11 C', '3 rue du Test', 500000, 'longue_duree');
    perform pg_temp.record('2 troisième bien (2 -> 3, limite 2) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 troisième bien (2 -> 3, limite 2) -> refusé', v_detail, 'property.create.plan_limit_exceeded');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — non-régression sur une organisation déjà existante avant
--    cette migration (rétro-remplissage 'actif' / palier illimité) : elle
--    doit pouvoir créer un bien sans jamais toucher la limite.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id  uuid;
  v_status  text;
  v_code    text;
  v_max     integer;
begin
  select o.id into v_org_id
  from public.organizations o
  join pg_temp.fixtures f on true
  where o.id <> f.org_id
  order by o.created_at
  limit 1;

  if v_org_id is null then
    perform pg_temp.record('3 organisation pré-existante trouvée pour le test de non-régression', 'FAIL', 'aucune organisation pré-existante en base');
    return;
  end if;

  select os.status, sp.code, sp.max_properties
  into v_status, v_code, v_max
  from public.organization_subscriptions os
  join public.subscription_plans sp on sp.id = os.plan_id
  where os.organization_id = v_org_id;

  if v_status = 'actif' and v_max is null then
    perform pg_temp.record('3a organisation pré-existante rétro-remplie en actif/illimité', 'PASS');
  else
    perform pg_temp.record('3a organisation pré-existante rétro-remplie en actif/illimité', 'FAIL', format('status=%L palier=%L max_properties=%L', v_status, v_code, v_max));
  end if;

  begin
    insert into public.properties (organization_id, name, address, price, location_type)
    values (v_org_id, 'Bien Module11 Non-Regression', '4 rue du Test', 500000, 'longue_duree');
    perform pg_temp.record('3b création d''un bien sur organisation pré-existante (illimité) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('3b création d''un bien sur organisation pré-existante (illimité) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
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
