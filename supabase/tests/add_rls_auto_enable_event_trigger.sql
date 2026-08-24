-- ============================================================================
-- TEST — event trigger ensure_rls / public.rls_auto_enable() (migration
-- 20260805470000_add_rls_auto_enable_event_trigger.sql).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents (module6e/
-- module7b/module8/module9) : transaction begin/rollback, helper pg_temp
-- pour le résumé PASS/FAIL, ROLLBACK final.
--
-- Objectif unique : prouver que le trigger active RLS automatiquement sur
-- une table fraîchement créée dans public qui n'active pas RLS elle-même.
-- La table de test est droppée explicitement avant le ROLLBACK (qui de
-- toute façon annulerait la création) pour ne rien laisser dépendre du seul
-- rollback en cas d'exécution manuelle partielle du script.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805470000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/add_rls_auto_enable_event_trigger.sql
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

-- ----------------------------------------------------------------------------
-- 1. SCÉNARIO — table créée dans public SANS enable row level security
--    explicite -> RLS doit se retrouver activée automatiquement dessus.
-- ----------------------------------------------------------------------------

create table public.drift_check_rls_auto_enable_probe (
  id uuid primary key default gen_random_uuid()
);
-- Volontairement : aucun `alter table ... enable row level security` ici.
-- C'est exactement l'oubli que le trigger est censé rattraper.

do $$
declare
  v_rls_enabled boolean;
begin
  select relrowsecurity into v_rls_enabled
  from pg_class
  where oid = 'public.drift_check_rls_auto_enable_probe'::regclass;

  if v_rls_enabled is true then
    perform pg_temp.record('RLS activée automatiquement sur une table créée sans enable explicite', 'PASS');
  else
    perform pg_temp.record('RLS activée automatiquement sur une table créée sans enable explicite', 'FAIL', format('relrowsecurity=%s', v_rls_enabled));
  end if;
end;
$$;

-- Nettoyage explicite de la table de test, en plus du ROLLBACK final.
drop table public.drift_check_rls_auto_enable_probe;

-- ----------------------------------------------------------------------------
-- 2. RÉSUMÉ.
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
