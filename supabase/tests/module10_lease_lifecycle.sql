-- ============================================================================
-- TEST — Module 10 (cycle de vie du bail : brouillon -> actif -> resilie/
-- termine), les 3 volets (activation conditionnée, fin de bail normale,
-- restitution des clés + clôture) + le trigger générique de garde de
-- leases.status + le mécanisme de suppression d'un bail brouillon.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/.
--
-- Même patron que les scripts précédents (module8/module6f/module9) :
--   - Tout s'exécute dans une seule transaction, ROLLBACK en toute fin.
--   - Fixtures montées avec le rôle de connexion (superuser, bypasse RLS),
--     scénarios basculés explicitement via pg_temp.act_as().
--   - Résultats : RAISE NOTICE '[PASS|FAIL] ...' au fil de l'eau, résumé
--     tabulaire juste avant le ROLLBACK.
--
-- Deux helpers de fixture propres à ce script (voir section 0b) :
--   - pg_temp.new_lease(...) : crée un bien + un bail au statut par défaut
--     ('brouillon', désormais) — réduit la répétition vu le nombre de baux
--     nécessaires (un par scénario, comme aux scripts précédents).
--   - pg_temp.force_lease_status(...) : désactive temporairement le trigger
--     de garde pour fabriquer un bail à un statut de départ donné (resilie,
--     termine, ou actif sans repasser par le parcours d'activation déjà
--     prouvé en section 2) — fixture uniquement, jamais un chemin testé.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 10 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10_lease_lifecycle.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0a. HELPERS DE TEST (identiques aux scripts précédents).
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

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 0b. HELPERS DE FIXTURE PROPRES À CE SCRIPT.
-- ----------------------------------------------------------------------------

-- Crée un bien + un bail dédiés, au statut par défaut ('brouillon'). Un bail
-- par scénario indépendant, comme aux scripts précédents (immutabilité/
-- unicité post-transition obligent à ne jamais réutiliser un bail entre
-- deux scénarios indépendants).
create or replace function pg_temp.new_lease(
  p_org uuid,
  p_tenant uuid,
  p_label text,
  p_security_deposit numeric default 200000,
  p_utility_deposit numeric default null,
  p_start_date date default current_date
) returns uuid language plpgsql as $$
declare
  v_prop  uuid;
  v_lease uuid;
begin
  insert into public.properties (organization_id, name, address, price, location_type)
  values (p_org, 'Bien 10 — ' || p_label, p_label || ' rue du Test', 500000, 'longue_duree')
  returning id into v_prop;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, utility_deposit_amount, payment_timing
  ) values (p_org, v_prop, p_tenant, p_start_date, 100000, 'mensuel', p_security_deposit, p_utility_deposit, 'postpaye')
  returning id into v_lease;

  return v_lease;
end;
$$;

-- Fabrique un bail à un statut de départ donné, en désactivant temporairement
-- le trigger de garde — UNIQUEMENT pour monter une fixture (ex: un bail déjà
-- 'actif' sans repasser par le parcours d'activation, déjà prouvé en
-- section 2 ; ou déjà 'resilie'/'termine' pour la matrice de transitions
-- refusées, section 5). Jamais un chemin testé en lui-même. Même technique
-- que le backdatage de finalized_at dans module6e/6f.
create or replace function pg_temp.force_lease_status(p_lease uuid, p_status text)
returns void language plpgsql as $$
begin
  alter table public.leases disable trigger trg_leases_validate_status_transition;
  update public.leases set status = p_status where id = p_lease;
  alter table public.leases enable trigger trg_leases_validate_status_transition;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10', 'test-org-10-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_tenant_id as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- Tous les baux de scénario sont créés ici, sous le rôle propriétaire, puis
-- stockés dans pg_temp.leases pour être référencés par label dans chaque
-- scénario ci-dessous.
do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  create table pg_temp.leases as
  select
    pg_temp.new_lease(f.org_id, f.tenant_id, 'A',  200000, 50000)  as lease_a,  -- Volet A, parcours complet
    pg_temp.new_lease(f.org_id, f.tenant_id, 'C',  100000, null)   as lease_c,  -- bypass direct brouillon->actif
    pg_temp.new_lease(f.org_id, f.tenant_id, 'D',  100000, null)   as lease_d,  -- idempotence approbation
    pg_temp.new_lease(f.org_id, f.tenant_id, 'E',  100000, null)   as lease_e,  -- doublon contrat
    pg_temp.new_lease(f.org_id, f.tenant_id, 'F',  100000, null)   as lease_f,  -- staff approuve à la place du locataire
    pg_temp.new_lease(f.org_id, f.tenant_id, 'G',  100000, null)   as lease_g,  -- bypass direct actif->resilie
    pg_temp.new_lease(f.org_id, f.tenant_id, 'H',  100000, null)   as lease_h,  -- clôture depuis actif
    pg_temp.new_lease(f.org_id, f.tenant_id, 'I',  100000, null)   as lease_i,  -- clôture depuis resilie (Module 8 réel)
    pg_temp.new_lease(f.org_id, f.tenant_id, 'N',  100000, null)   as lease_n,  -- Volet B, renouveler
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J1', 100000, null)   as lease_j1, -- brouillon -> termine
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J2', 100000, null)   as lease_j2, -- brouillon -> resilie
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J3', 100000, null)   as lease_j3, -- actif -> brouillon
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J4', 100000, null)   as lease_j4, -- resilie -> actif
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J5', 100000, null)   as lease_j5, -- resilie -> brouillon
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J6', 100000, null)   as lease_j6, -- termine -> actif
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J7', 100000, null)   as lease_j7, -- termine -> resilie
    pg_temp.new_lease(f.org_id, f.tenant_id, 'J8', 100000, null)   as lease_j8, -- termine -> brouillon
    pg_temp.new_lease(f.org_id, f.tenant_id, 'K',  100000, null)   as lease_k,  -- suppression brouillon, zéro dépôt
    pg_temp.new_lease(f.org_id, f.tenant_id, 'L',  100000, null)   as lease_l,  -- suppression brouillon, avec dépôt
    pg_temp.new_lease(f.org_id, f.tenant_id, 'M1', 100000, null)   as lease_m1, -- service_role bypass brouillon->actif
    pg_temp.new_lease(f.org_id, f.tenant_id, 'M2', 100000, null)   as lease_m2, -- service_role bypass actif->resilie
    pg_temp.new_lease(f.org_id, f.tenant_id, 'M3', 100000, null)   as lease_m3, -- service_role clôture sans clés
    pg_temp.new_lease(f.org_id, f.tenant_id, 'M4', 100000, null)   as lease_m4; -- service_role delete avec dépôt
end;
$$;

grant select, insert on pg_temp.leases to authenticated, service_role;

-- ============================================================================
-- 2. VOLET A — ACTIVATION CONDITIONNÉE À L'ENGAGEMENT FINANCIER RÉEL.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 — INSERT sans statut explicite -> 'brouillon' (plus 'actif').
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select status into v_status from public.leases l join pg_temp.leases pl on l.id = pl.lease_a;
  perform pg_temp.check_detail('2.1 nouveau bail -> statut brouillon par défaut', v_status, 'brouillon');
end;
$$;

-- ----------------------------------------------------------------------------
-- 2.2 — INSERT avec status='actif' explicite -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (f.org_id, 'Bien 10 — B', '2.2 rue du Test', 500000, 'longue_duree') returning id into v_prop;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.leases (
      organization_id, property_id, tenant_account_id, start_date,
      rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
    ) values (f.org_id, v_prop, f.tenant_id, current_date, 100000, 'mensuel', 100000, 'postpaye', 'actif');
    perform pg_temp.record('2.2 INSERT status=actif direct -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2.2 INSERT status=actif direct -> refusé', v_detail, 'lease.status.invalid_initial_value');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2.3 à 2.9 — bail A : dépôts échelonnés (2 types, avance + utilities),
-- approbation refusée tant qu'incomplets, activation, génération des
-- échéances SEULEMENT à l'activation, doublon de contrat refusé,
-- usurpation d'approbation refusée, idempotence, bypass direct refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_a uuid;
  v_complete boolean;
  v_contract_id uuid;
  v_status text;
  v_detail text;
  v_sched_count_before int;
  v_sched_count_after int;
  v_sched_count_regen int;
  v_row_count int;
begin
  select * into f from pg_temp.fixtures;
  select lease_a into v_lease_a from pg_temp.leases;

  -- Aucune échéance n'existe encore sur un bail encore brouillon (Module 5c
  -- ne se déclenche plus à l'INSERT).
  select count(*) into v_sched_count_before from public.payment_schedules where lease_id = v_lease_a;
  if v_sched_count_before = 0 then
    perform pg_temp.record('2.3a aucune échéance générée tant que le bail est brouillon', 'PASS');
  else
    perform pg_temp.record('2.3a aucune échéance générée tant que le bail est brouillon', 'FAIL', format('%s ligne(s) trouvée(s)', v_sched_count_before));
  end if;

  select private.lease_deposits_complete(v_lease_a) into v_complete;
  if v_complete is false then
    perform pg_temp.record('2.3b dépôts complets = false, aucun dépôt versé', 'PASS');
  else
    perform pg_temp.record('2.3b dépôts complets = false, aucun dépôt versé', 'FAIL', format('obtenu %s', v_complete));
  end if;

  -- Premier versement partiel (échelonnement) de l'avance de garantie.
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease_a, 'avance_garantie', 'depot_initial', 100000);

  select private.lease_deposits_complete(v_lease_a) into v_complete;
  perform pg_temp.check_detail('2.3c dépôts complets = false, avance de garantie partielle (100000/200000)',
    v_complete::text, 'false');

  -- Solde de l'avance de garantie.
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease_a, 'avance_garantie', 'depot_initial', 100000);

  select private.lease_deposits_complete(v_lease_a) into v_complete;
  perform pg_temp.check_detail('2.3d dépôts complets = false, avance de garantie soldée MAIS caution utilities absente',
    v_complete::text, 'false');

  -- 2.4 — le locataire génère le contrat, puis tente d'approuver avant que
  -- la caution utilities ne soit versée -> refusé.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (f.org_id, v_lease_a, 'test/contracts/lease-a.pdf')
  returning id into v_contract_id;
  perform pg_temp.record('2.4a locataire génère le contrat (dépôts incomplets) -> autorisé', 'PASS');

  begin
    update public.lease_contracts set approved_at = now() where id = v_contract_id;
    perform pg_temp.record('2.4b locataire approuve avant dépôts complets -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2.4b locataire approuve avant dépôts complets -> refusé', v_detail, 'lease_contract.approve.deposits_incomplete');
  end;

  select status into v_status from public.leases where id = v_lease_a;
  perform pg_temp.check_detail('2.4c bail toujours brouillon après approbation refusée', v_status, 'brouillon');

  -- Caution eau/électricité versée -> dépôts complets.
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease_a, 'caution_utilities', 'depot_initial', 50000);

  select private.lease_deposits_complete(v_lease_a) into v_complete;
  perform pg_temp.check_detail('2.5a dépôts complets = true, les deux dépôts atteints', v_complete::text, 'true');

  -- 2.5 — approbation locataire -> activation + génération des échéances.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    update public.lease_contracts set approved_at = now() where id = v_contract_id;
    perform pg_temp.record('2.5b locataire approuve (dépôts complets) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2.5b locataire approuve (dépôts complets) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status into v_status from public.leases where id = v_lease_a;
  perform pg_temp.check_detail('2.5c leases.status = actif après approbation', v_status, 'actif');

  -- Bascule owner pour ce comptage : on vérifie l'existence des lignes,
  -- pas la visibilité RLS du locataire (non testée ici).
  perform pg_temp.act_as_owner();
  select count(*) into v_sched_count_after from public.payment_schedules where lease_id = v_lease_a;
  if v_sched_count_after > 0 then
    perform pg_temp.record('2.5d échéances générées exactement à l''activation', 'PASS');
  else
    perform pg_temp.record('2.5d échéances générées exactement à l''activation', 'FAIL', 'aucune échéance générée');
  end if;

  -- 2.6 — doublon de contrat sur le même bail -> refusé (unique lease_id).
  begin
    insert into public.lease_contracts (organization_id, lease_id, storage_path)
    values (f.org_id, v_lease_a, 'test/contracts/lease-a-bis.pdf');
    perform pg_temp.record('2.6 deuxième contrat sur le même bail -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = returned_sqlstate;
    perform pg_temp.check_detail('2.6 deuxième contrat sur le même bail -> refusé', v_detail, '23505');
  end;

  -- 2.8 — idempotence : re-tenter l'approbation (déjà approuvée) -> refusé,
  -- bail inchangé, aucune échéance dupliquée.
  begin
    update public.lease_contracts set approved_at = now() where id = v_contract_id;
    perform pg_temp.record('2.8a ré-approbation d''un contrat déjà approuvé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2.8a ré-approbation d''un contrat déjà approuvé -> refusé', v_detail, 'lease_contract.approved_at.immutable');
  end;

  select status into v_status from public.leases where id = v_lease_a;
  perform pg_temp.check_detail('2.8b bail toujours actif après tentative de ré-approbation', v_status, 'actif');

  perform pg_temp.act_as_owner();
  perform public.generate_payment_schedules_for_lease(v_lease_a);
  select count(*) into v_sched_count_regen from public.payment_schedules where lease_id = v_lease_a;
  if v_sched_count_regen = v_sched_count_after then
    perform pg_temp.record('2.8c ré-appeler generate_payment_schedules_for_lease -> idempotent, aucun doublon', 'PASS');
  else
    perform pg_temp.record('2.8c ré-appeler generate_payment_schedules_for_lease -> idempotent, aucun doublon', 'FAIL',
      format('avant=%s après=%s', v_sched_count_after, v_sched_count_regen));
  end if;

  -- 2.7 — le staff tente d'approuver à la place du locataire sur le bail F
  -- (RLS : 0 ligne affectée, jamais une exception).
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (f.org_id, (select lease_f from pg_temp.leases), 'test/contracts/lease-f.pdf')
  returning id into v_contract_id;

  update public.lease_contracts set approved_at = now() where id = v_contract_id;
  get diagnostics v_row_count = row_count;
  perform pg_temp.check_detail('2.7 staff tente d''approuver le contrat du locataire -> 0 ligne (RLS)',
    v_row_count::text, '0');

  perform pg_temp.act_as_owner();
  perform pg_temp.check_detail('2.7b approved_at toujours NULL après la tentative du staff',
    (select approved_at is null from public.lease_contracts where id = v_contract_id)::text, 'true');
end;
$$;

-- ----------------------------------------------------------------------------
-- 2.9 — bail C : dépôts complets, mais bypass direct brouillon -> actif
-- (sans passer par lease_contracts) -> refusé, même avec leases:update.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_c uuid;
  v_detail text;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select lease_c into v_lease_c from pg_temp.leases;

  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease_c, 'avance_garantie', 'depot_initial', 100000);

  begin
    update public.leases set status = 'actif' where id = v_lease_c;
    perform pg_temp.record('2.9 UPDATE direct brouillon->actif (dépôts complets, staff, depth=1) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2.9 UPDATE direct brouillon->actif (dépôts complets, staff, depth=1) -> refusé', v_detail, 'lease.status.invalid_transition');
  end;

  select status into v_status from public.leases where id = v_lease_c;
  perform pg_temp.check_detail('2.9b bail C toujours brouillon après le bypass refusé', v_status, 'brouillon');
end;
$$;

-- ============================================================================
-- 3. VOLET B — FIN DE BAIL NORMALE (renouveler = simple UPDATE end_date,
-- rien de nouveau côté base ; leases_closure_status reflète l'état à la
-- volée).
-- ============================================================================

do $$
declare
  f record;
  v_lease_n uuid;
  v_new_end date := current_date + 45;
  v_view_end date;
begin
  select * into f from pg_temp.fixtures;
  select lease_n into v_lease_n from pg_temp.leases;

  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(v_lease_n, 'actif');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set end_date = v_new_end where id = v_lease_n;
    perform pg_temp.record('3a "renouveler" = UPDATE end_date sur bail actif -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('3a "renouveler" = UPDATE end_date sur bail actif -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select lease_end_date into v_view_end from public.leases_closure_status where lease_id = v_lease_n;
  perform pg_temp.check_detail('3b leases_closure_status reflète la nouvelle end_date immédiatement',
    v_view_end::text, v_new_end::text);
end;
$$;

-- ============================================================================
-- 4. VOLET C — RESTITUTION DES CLÉS + CLÔTURE.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 à 4.3 — bail H (actif) : clôture refusée sans clés, refusée sans état
-- des lieux de sortie finalisé, puis autorisée une fois les deux réunis.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_h uuid;
  v_detail text;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select lease_h into v_lease_h from pg_temp.leases;

  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(v_lease_h, 'actif');

  perform pg_temp.act_as('authenticated', f.staff_id);

  -- 4.1 — clôture sans keys_returned_at -> refusé.
  begin
    update public.leases set status = 'termine' where id = v_lease_h;
    perform pg_temp.record('4.1 clôture sans keys_returned_at -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.1 clôture sans keys_returned_at -> refusé', v_detail, 'lease.closure.keys_not_returned');
  end;

  -- Restitution des clés (VOLET C : enfin accessible depuis un geste staff).
  update public.leases set keys_returned_at = current_date where id = v_lease_h;

  -- 4.2 — clôture avec clés mais sans état des lieux de sortie finalisé -> refusé.
  begin
    update public.leases set status = 'termine' where id = v_lease_h;
    perform pg_temp.record('4.2 clôture avec clés, sans état des lieux de sortie finalisé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.2 clôture avec clés, sans état des lieux de sortie finalisé -> refusé', v_detail, 'lease.closure.missing_exit_inspection');
  end;

  -- État des lieux de sortie finalisé (Module 6, inchangé).
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, v_lease_h, 'sortie', current_date, 'finalise', f.staff_id);

  -- 4.3 — clôture désormais autorisée -> termine.
  begin
    update public.leases set status = 'termine' where id = v_lease_h;
    perform pg_temp.record('4.3 clôture avec clés + état des lieux de sortie finalisé -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('4.3 clôture avec clés + état des lieux de sortie finalisé -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status into v_status from public.leases where id = v_lease_h;
  perform pg_temp.check_detail('4.3b leases.status = termine', v_status, 'termine');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4.4 — bail I : chaîne universelle depuis 'resilie'. Passe par le VRAI
-- mécanisme de consensus Module 8 (inchangé), puis rejoint le même parcours
-- de clôture que 4.1-4.3 pour atteindre 'termine' — preuve que 'resilie'
-- n'est plus un état terminal isolé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_i uuid;
  v_request_id uuid;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select lease_i into v_lease_i from pg_temp.leases;

  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(v_lease_i, 'actif');

  -- Résiliation par consensus réel (Module 8, complètement inchangé) :
  -- staff initie, locataire accepte.
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, v_lease_i, null, f.staff_id, current_date + 5, 'Test Module 10 — chaîne universelle')
  returning id into v_request_id;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  update public.lease_termination_requests set status = 'validee' where id = v_request_id;

  select status into v_status from public.leases where id = v_lease_i;
  perform pg_temp.check_detail('4.4a Module 8 inchangé : bail I -> resilie après consensus', v_status, 'resilie');

  -- Même parcours de clôture qu'en 4.1-4.3, depuis 'resilie' cette fois.
  perform pg_temp.act_as('authenticated', f.staff_id);

  declare
    v_detail_i text;
  begin
    update public.leases set status = 'termine' where id = v_lease_i;
    perform pg_temp.record('4.4b clôture d''un bail resilie sans clés -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail_i = pg_exception_detail;
    perform pg_temp.check_detail('4.4b clôture d''un bail resilie sans clés -> refusé', v_detail_i, 'lease.closure.keys_not_returned');
  end;

  update public.leases set keys_returned_at = current_date where id = v_lease_i;

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, v_lease_i, 'sortie', current_date, 'finalise', f.staff_id);

  begin
    update public.leases set status = 'termine' where id = v_lease_i;
    perform pg_temp.record('4.4c resilie -> termine (clés + inspection réunies) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('4.4c resilie -> termine (clés + inspection réunies) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status into v_status from public.leases where id = v_lease_i;
  perform pg_temp.check_detail('4.4d leases.status = termine (bail I, parti de resilie)', v_status, 'termine');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4.5 — bail G : bypass direct actif -> resilie (sans passer par le
-- consensus Module 8) -> refusé, même avec leases:update. Ferme la lacune
-- préexistante identifiée dans la conception.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_g uuid;
  v_detail text;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select lease_g into v_lease_g from pg_temp.leases;

  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(v_lease_g, 'actif');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set status = 'resilie' where id = v_lease_g;
    perform pg_temp.record('4.5 UPDATE direct actif->resilie (staff, depth=1, hors Module 8) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.5 UPDATE direct actif->resilie (staff, depth=1, hors Module 8) -> refusé', v_detail, 'lease.status.invalid_transition');
  end;

  select status into v_status from public.leases where id = v_lease_g;
  perform pg_temp.check_detail('4.5b bail G toujours actif après le bypass refusé', v_status, 'actif');
end;
$$;

-- ============================================================================
-- 5. MATRICE EXHAUSTIVE DES TRANSITIONS REFUSÉES (au-delà des cas déjà
-- couverts en 2.9/4.5) : tout saut, tout retour en arrière, toute écriture
-- depuis l'état terminal 'termine'.
-- ============================================================================

-- Helper dédié à cette matrice (fonction top-level, comme les autres
-- helpers pg_temp.* — PL/pgSQL ne permet pas de déclarer une procédure
-- imbriquée dans un bloc DO).
create or replace function pg_temp.assert_transition_rejected(p_lease uuid, p_new_status text, p_label text)
returns void language plpgsql as $$
declare
  v_detail text;
begin
  begin
    update public.leases set status = p_new_status where id = p_lease;
    perform pg_temp.record(p_label, 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail(p_label, v_detail, 'lease.status.invalid_transition');
  end;
end;
$$;

grant execute on function pg_temp.assert_transition_rejected(uuid, text, text) to authenticated, service_role;

do $$
declare
  f record;
  L pg_temp.leases%rowtype;
begin
  select * into f from pg_temp.fixtures;
  select * into L from pg_temp.leases;

  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(L.lease_j3, 'actif');
  perform pg_temp.force_lease_status(L.lease_j4, 'resilie');
  perform pg_temp.force_lease_status(L.lease_j5, 'resilie');
  perform pg_temp.force_lease_status(L.lease_j6, 'termine');
  perform pg_temp.force_lease_status(L.lease_j7, 'termine');
  perform pg_temp.force_lease_status(L.lease_j8, 'termine');

  perform pg_temp.act_as('authenticated', f.staff_id);

  perform pg_temp.assert_transition_rejected(L.lease_j1, 'termine', '5.1 brouillon -> termine (saut direct) -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j2, 'resilie', '5.2 brouillon -> resilie (saut direct) -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j3, 'brouillon', '5.3 actif -> brouillon (retour en arrière) -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j4, 'actif', '5.4 resilie -> actif -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j5, 'brouillon', '5.5 resilie -> brouillon -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j6, 'actif', '5.6 termine -> actif (absorbant) -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j7, 'resilie', '5.7 termine -> resilie (absorbant) -> refusé');
  perform pg_temp.assert_transition_rejected(L.lease_j8, 'brouillon', '5.8 termine -> brouillon (absorbant) -> refusé');
end;
$$;

-- ============================================================================
-- 6. SUPPRESSION D'UN BAIL BROUILLON — mécanisme de refus de contrat.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 6.1 — bail K : aucun dépôt versé -> suppression propre.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_k uuid;
  v_count int;
begin
  select * into f from pg_temp.fixtures;
  select lease_k into v_lease_k from pg_temp.leases;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    delete from public.leases where id = v_lease_k;
    perform pg_temp.record('6.1 suppression bail brouillon sans dépôt -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('6.1 suppression bail brouillon sans dépôt -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select count(*) into v_count from public.leases where id = v_lease_k;
  perform pg_temp.check_detail('6.1b la ligne a bien disparu', v_count::text, '0');
end;
$$;

-- ----------------------------------------------------------------------------
-- 6.2 — bail L : un dépôt a été versé -> suppression refusée avec message
-- métier propre, PAS la violation FK brute (23503).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_l uuid;
  v_detail text;
  v_count int;
begin
  select * into f from pg_temp.fixtures;
  select lease_l into v_lease_l from pg_temp.leases;

  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease_l, 'avance_garantie', 'depot_initial', 50000);

  begin
    delete from public.leases where id = v_lease_l;
    perform pg_temp.record('6.2 suppression bail brouillon avec dépôt -> refusé (message propre)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.2 suppression bail brouillon avec dépôt -> refusé (message propre)', v_detail, 'lease.delete.has_deposit_history');
  end;

  select count(*) into v_count from public.leases where id = v_lease_l;
  perform pg_temp.check_detail('6.2b le bail L existe toujours (remboursement possible via RefundForm)', v_count::text, '1');
end;
$$;

-- ============================================================================
-- 7. DÉFENSE EN PROFONDEUR — service_role, bypasse RLS entièrement, prouve
-- que tout tient aux triggers (jamais aux policies RLS).
-- ============================================================================

do $$
declare
  f record;
  L pg_temp.leases%rowtype;
  v_detail text;
  v_status text;
begin
  select * into f from pg_temp.fixtures;
  select * into L from pg_temp.leases;

  -- 7.1 — service_role, brouillon -> actif direct -> refusé malgré le bypass RLS.
  perform pg_temp.act_as('service_role', null);
  begin
    update public.leases set status = 'actif' where id = L.lease_m1;
    perform pg_temp.record('7.1 service_role brouillon->actif direct -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7.1 service_role brouillon->actif direct -> refusé malgré bypass RLS', v_detail, 'lease.status.invalid_transition');
  end;

  -- 7.2 — service_role, actif -> resilie direct -> refusé malgré le bypass RLS.
  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(L.lease_m2, 'actif');

  perform pg_temp.act_as('service_role', null);
  begin
    update public.leases set status = 'resilie' where id = L.lease_m2;
    perform pg_temp.record('7.2 service_role actif->resilie direct -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7.2 service_role actif->resilie direct -> refusé malgré bypass RLS', v_detail, 'lease.status.invalid_transition');
  end;

  -- 7.3 — service_role, clôture sans keys_returned_at -> refusé (règle
  -- métier portée par le trigger, pas par une permission).
  perform pg_temp.act_as_owner();
  perform pg_temp.force_lease_status(L.lease_m3, 'actif');

  perform pg_temp.act_as('service_role', null);
  begin
    update public.leases set status = 'termine' where id = L.lease_m3;
    perform pg_temp.record('7.3 service_role clôture sans clés -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7.3 service_role clôture sans clés -> refusé malgré bypass RLS', v_detail, 'lease.closure.keys_not_returned');
  end;

  -- 7.4 — service_role, suppression d'un brouillon avec historique de
  -- dépôts -> refusé malgré le bypass RLS (le message propre tient au
  -- trigger, pas à une policy).
  perform pg_temp.act_as_owner();
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, L.lease_m4, 'avance_garantie', 'depot_initial', 50000);

  perform pg_temp.act_as('service_role', null);
  begin
    delete from public.leases where id = L.lease_m4;
    perform pg_temp.record('7.4 service_role suppression brouillon avec dépôt -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7.4 service_role suppression brouillon avec dépôt -> refusé malgré bypass RLS', v_detail, 'lease.delete.has_deposit_history');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. RÉSUMÉ.
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
