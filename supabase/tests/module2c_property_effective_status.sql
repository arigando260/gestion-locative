-- ============================================================================
-- TEST — Module 2c (statut effectif des biens, calculé à la volée : vue
-- properties_effective_status, fonction private.property_effective_status,
-- resserrement du CHECK sur properties.status).
--
-- Mis à jour par la migration "retrait des réservations — passe A" : le
-- scénario 2 (ex-"réservation confirmée en cours -> occupe") vérifie
-- désormais l'inverse — une réservation confirmée en cours ne compte plus
-- comme occupation, private.property_effective_status n'a plus que 2
-- paramètres (p_status, p_has_active_lease).
--
-- Corrigé au passage (bug préexistant, sans rapport avec le retrait des
-- réservations) : les baux des scénarios 1 et 3 ne précisaient pas
-- status='actif' à l'insertion, s'appuyant silencieusement sur le défaut
-- posé au Module 3 — or le Module 10 (20260805240000) a changé ce défaut
-- en 'brouillon' (un bail exige désormais une approbation de contrat pour
-- devenir actif). Le scénario 3 passait par accident (l'override
-- 'en_travaux' masque la valeur réelle testée) ; le scénario 1 échouait
-- franchement. Les deux insertions posent maintenant status='actif'
-- explicitement.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que supabase/tests/module7b_maintenance_locks.sql
-- et supabase/tests/module8_lease_termination_consensus.sql.
--
-- Fonctionnement :
--   - Tout s'exécute dans une seule transaction, ROLLBACK en toute fin :
--     aucune donnée de test ne persiste, le script est rejouable à volonté.
--   - Fixtures montées avec le rôle de connexion (superuser, bypasse RLS) —
--     aucun besoin de bascule d'identité ici : ce test vérifie un CALCUL
--     (effective_status) et une contrainte CHECK, pas des policies RLS, donc
--     pas de pg_temp.act_as() nécessaire (contrairement à 7b/8).
--   - Résultats : RAISE NOTICE '[PASS|FAIL] ...' au fil de l'eau, plus un
--     résumé tabulaire (pg_temp.test_results) juste avant le ROLLBACK.
--
-- Hypothèses sur l'instance locale (Supabase CLI standard) :
--   - connexion effectuée avec un rôle superuser (postgres).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 2c soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module2c_property_effective_status.sql
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

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id      uuid;
  v_tenant_id   uuid := gen_random_uuid();
  v_prop_a      uuid; -- bail actif -> occupe
  v_prop_b      uuid; -- réservation confirmée en cours -> occupe
  v_prop_c      uuid; -- en_travaux + bail actif -> reste en_travaux (override prime)
  v_prop_d      uuid; -- ni bail ni réservation, disponible -> disponible
begin
  insert into public.organizations (name, slug)
  values ('Test Org 2c', 'test-org-2c-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-2c@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 2c'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- Bien A : longue_duree, recevra un bail actif. Le passage direct à
  -- status='actif' n'est normalement pas permis à l'INSERT (Module 10,
  -- trg_leases_validate_status_transition impose 'brouillon' puis une
  -- activation en cascade via l'approbation du contrat) — hors sujet ici
  -- (ce test porte sur le calcul du statut effectif, pas sur le cycle de
  -- vie du bail), donc le garde-fou est désactivé le temps de cette seule
  -- insertion, même technique que supabase/tests/module10c_allow_delete_
  -- unapproved_lease_contract.sql et module10e_atomic_draft_lease_deletion.sql.
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 2c — A (bail actif)', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_a;

  alter table public.leases disable trigger trg_leases_validate_status_transition;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_a, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye', 'actif');

  -- Bien B : courte_duree, recevra une réservation confirmée couvrant
  -- aujourd'hui (check_in = hier, check_out = dans 3 jours) — depuis la
  -- passe A du retrait des réservations, ceci ne doit PLUS rendre le bien
  -- 'occupe' (voir scénario 2 plus bas).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 2c — B (réservation en cours)', '2 rue du Test', 500000, 'courte_duree')
  returning id into v_prop_b;

  insert into public.reservations (
    organization_id, property_id, tenant_account_id,
    check_in_date, check_out_date, nightly_rate, total_amount
  ) values (
    v_org_id, v_prop_b, v_tenant_id,
    current_date - 1, current_date + 3, 25000, 100000
  );

  -- Bien C : longue_duree, posé manuellement 'en_travaux' ET recevant un
  -- bail actif quand même (scénario volontairement contradictoire, pour
  -- vérifier que l'override manuel prime toujours sur le calcul).
  insert into public.properties (organization_id, name, address, price, location_type, status)
  values (v_org_id, 'Bien 2c — C (en_travaux + bail actif)', '3 rue du Test', 500000, 'longue_duree', 'en_travaux')
  returning id into v_prop_c;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_c, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye', 'actif');

  alter table public.leases enable trigger trg_leases_validate_status_transition;

  -- Bien D : ni bail ni réservation, status='disponible' (défaut).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 2c — D (aucune occupation)', '4 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_d;

  create table pg_temp.fixtures as
  select
    v_org_id    as org_id,
    v_tenant_id as tenant_id,
    v_prop_a    as prop_a,
    v_prop_b    as prop_b,
    v_prop_c    as prop_c,
    v_prop_d    as prop_d;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — BAIL ACTIF -> occupe.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_effective text;
begin
  select * into f from pg_temp.fixtures;

  select effective_status into v_effective
  from public.properties_effective_status where id = f.prop_a;

  perform pg_temp.check_detail('1 bien avec bail actif -> occupe', v_effective, 'occupe');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — RÉSERVATION CONFIRMÉE EN COURS -> reste disponible
--    (retrait des réservations, passe A : plus aucune réservation, même
--    confirmée et en cours, ne compte comme occupation).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_effective text;
begin
  select * into f from pg_temp.fixtures;

  select effective_status into v_effective
  from public.properties_effective_status where id = f.prop_b;

  perform pg_temp.check_detail('2 bien avec réservation confirmée en cours -> reste disponible (réservations retirées du calcul)', v_effective, 'disponible');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — en_travaux + BAIL ACTIF -> reste en_travaux (override
--    manuel prioritaire sur le calcul, même avec occupation réelle).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_effective text;
begin
  select * into f from pg_temp.fixtures;

  select effective_status into v_effective
  from public.properties_effective_status where id = f.prop_c;

  perform pg_temp.check_detail(
    '3 bien en_travaux + bail actif -> reste en_travaux (override prioritaire)',
    v_effective, 'en_travaux'
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — NI BAIL NI RÉSERVATION, status='disponible' -> disponible.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_effective text;
begin
  select * into f from pg_temp.fixtures;

  select effective_status into v_effective
  from public.properties_effective_status where id = f.prop_d;

  perform pg_temp.check_detail('4 bien sans occupation, disponible -> disponible', v_effective, 'disponible');
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — INSERTION DIRECTE status='occupe' -> refusée par le CHECK
--    resserré (Module 2c). location_type valide utilisé pour isoler
--    précisément le CHECK testé, sans passer par le trigger de validation
--    de location_type en amont.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_sqlstate   text;
  v_constraint text;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.properties (organization_id, name, address, price, location_type, status)
    values (f.org_id, 'Bien 2c — tentative status=occupe', '5 rue du Test', 500000, 'longue_duree', 'occupe');
    perform pg_temp.record('5 insertion directe status=occupe -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics
      v_sqlstate = returned_sqlstate,
      v_constraint = constraint_name;

    if v_sqlstate = '23514' and v_constraint = 'properties_status_check' then
      perform pg_temp.record('5 insertion directe status=occupe -> refusée', 'PASS');
    else
      perform pg_temp.record('5 insertion directe status=occupe -> refusée', 'FAIL',
        format('sqlstate=%L constraint=%L (attendu 23514 / properties_status_check) — %s',
          v_sqlstate, v_constraint, sqlerrm));
    end if;
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
