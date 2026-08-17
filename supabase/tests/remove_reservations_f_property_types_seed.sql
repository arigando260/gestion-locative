-- ============================================================================
-- TEST — Retrait des réservations, PASSE F (catalogue property_types).
--
-- Migration F est un nettoyage de données de référence ponctuel (DELETE de
-- 2 lignes de seed), pas un comportement réutilisable (trigger/contrainte)
-- à exercer par des fixtures — contrairement aux passes A à E. "Avant" est
-- donc vérifié une fois pour toutes par le diagnostic qui précède la
-- migration (déjà fait, consigné dans son en-tête), pas rejouable ici après
-- coup : une fois la vraie ligne supprimée du catalogue réel, il n'existe
-- plus d'état "avant" à observer sans la réinsérer artificiellement, ce qui
-- testerait une copie plutôt que l'effet réel de la migration. Ce script
-- vérifie donc uniquement l'état "après" sur les données réelles :
-- absence des 2 codes retirés, présence inchangée de 'longue_duree', et
-- qu'aucun bien ne pointe plus vers un code retiré (non-régression,
-- re-vérifié par précaution comme le reste de cette série de migrations).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Lecture seule (aucun INSERT/UPDATE/DELETE) : le
-- bloc BEGIN/ROLLBACK est conservé uniquement pour rester au même patron
-- que les scripts précédents de cette série.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_f_property_types_seed.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST.
-- ----------------------------------------------------------------------------

create table pg_temp.test_results (
  id     serial primary key,
  name   text not null,
  status text not null check (status in ('PASS', 'FAIL')),
  detail text
);

create or replace function pg_temp.check_count(p_name text, p_got bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_got = p_expected then
    insert into pg_temp.test_results (name, status) values (p_name, 'PASS');
  else
    insert into pg_temp.test_results (name, status, detail)
    values (p_name, 'FAIL', format('lignes attendues=%s, obtenues=%s', p_expected, p_got));
  end if;
  raise notice '[%] %', (select status from pg_temp.test_results order by id desc limit 1), p_name;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. property_types — les 2 codes retirés sont absents (global, tous types
--    confondus : le filtre organization_id is null de la migration ne peut
--    de toute façon cibler que les 2 types globaux, aucun type personnalisé
--    n'existant à ce jour, mais on vérifie l'absence sans restreindre la
--    clause pour détecter aussi une éventuelle réapparition en type
--    personnalisé).
-- ----------------------------------------------------------------------------

do $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from public.property_types
  where code in ('meuble_simple', 'courte_duree');
  perform pg_temp.check_count('1 property_types : 0 ligne meuble_simple/courte_duree', v_count, 0);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. property_types — longue_duree toujours présent (non-régression).
-- ----------------------------------------------------------------------------

do $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from public.property_types
  where code = 'longue_duree' and organization_id is null;
  perform pg_temp.check_count('2 property_types : longue_duree toujours présent', v_count, 1);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. properties — aucun bien ne pointe plus vers un code retiré
--    (non-régression, revérifié par précaution).
-- ----------------------------------------------------------------------------

do $$
declare
  v_count bigint;
begin
  select count(*) into v_count
  from public.properties
  where location_type in ('meuble_simple', 'courte_duree');
  perform pg_temp.check_count('3 properties : 0 bien sur un type retiré', v_count, 0);
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
