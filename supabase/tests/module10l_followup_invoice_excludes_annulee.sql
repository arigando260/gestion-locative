-- ============================================================================
-- TEST — Suite du Module 10l : sémantique des données derrière le correctif
-- de facturation (src/data/schedule-invoices.ts getInvoiceGenerationContext).
--
-- Contexte : le Module 10l (résiliation validée) crée désormais des
-- échéances annulee automatiquement (post-date C) ; avant le correctif de
-- facturation, rien n'empêchait de sélectionner une telle échéance pour
-- facturation individuelle (schedule-invoices.ts, à la différence de
-- building-invoicing.ts qui excluait déjà 'annulee'). Voir réserve remontée
-- lors de la validation empirique du Lot 1.
--
-- PORTÉE RÉELLE DE CE TEST — à lire avant d'en tirer une conclusion :
-- getInvoiceGenerationContext() est une fonction TypeScript (supabase-js,
-- via PostgREST). Ce script ne l'exécute PAS et ne peut donc PAS prouver que
-- le code TypeScript contient bien le filtre .neq("status","annulee")
-- (aucune infrastructure de test TS/React n'existe dans ce projet -- pas de
-- jest/vitest configuré, vérifié dans package.json -- et il n'a pas été
-- demandé d'en créer une pour ce correctif ponctuel).
--
-- Ce que ce script démontre RÉELLEMENT, par exécution SQL directe sur DEV :
-- que la sémantique des données sous-jacentes au filtre est correcte et
-- suffisante pour que ce filtre fonctionne comme prévu une fois appliqué --
-- en particulier que le statut brut d'une échéance intégralement payée ou
-- déjà facturée reste 'en_attente' (jamais 'annulee'), donc qu'un filtre
-- status <> 'annulee' ne les exclut jamais par accident. C'est un test de
-- RÉGRESSION sur le modèle de données, pas une preuve d'exécution du code
-- TypeScript. La preuve que le filtre existe bien dans le code reste, à ce
-- stade, la lecture directe de schedule-invoices.ts (déjà faite) + tsc/eslint
-- (vérifient la compilation, pas le comportement runtime).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Ne touche ni à la migration 20260805700000 ni au
-- fichier de test module10l_tacit_renewal_and_post_termination_schedules.sql.
--
-- Fixture : passe par le contrat RÉEL de private.handle_new_user() /
-- private.create_organization_for_new_user() (Module 12e/12n) -- signup
-- interne via organization_name/organization_country/organization_phone
-- (organization_id dans les métadonnées est ignoré par la fonction actuelle,
-- l'organisation est toujours créée par le trigger, jamais choisie par
-- l'appelant) -- et par le contrat réel du flux d'invitation locataire
-- (Module 12d) : une ligne tenant_invitations avec token_hash = sha256(jeton
-- en clair), consommée par le même trigger via raw_user_meta_data.invitation_token.
-- Aucun trigger désactivé pour ces deux inserts (seul
-- trg_leases_validate_status_transition l'est, pour le bail, comme dans
-- module10_lease_lifecycle.sql -- non concerné par ce changement).
--
-- Exécution (DEV uniquement) :
--   node --env-file=.env.local scripts/run-module10l-tests.mjs \
--     supabase/tests/module10l_followup_invoice_excludes_annulee.sql
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS (identiques aux scripts précédents).
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

create or replace function pg_temp.check_true(p_name text, p_got boolean)
returns void language plpgsql as $$
begin
  if p_got then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', 'condition fausse');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — organisation (créée via le trigger handle_new_user, pas par
--    INSERT direct), staff, locataire (via invitation réelle), bail,
--    4 échéances dans des états différents.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_invite_token text := gen_random_uuid()::text;
  v_invite_hash  text;
  v_prop_id      uuid;
  v_lease_id     uuid;
  v_s_pending  uuid; -- en_attente, jamais touchée -> doit rester proposable
  v_s_annulee  uuid; -- annulee (post-C, Module 10l) -> ne doit jamais être proposée
  v_s_paid     uuid; -- en_attente + paiement confirmé intégral -> comportement financier inchangé
  v_s_invoiced uuid; -- en_attente + déjà facturée (invoice_schedule_items) -> comportement inchangé (dédoublonnage hors de ce prédicat)
  v_invoice_id uuid;
  v_result_ids uuid[];
begin
  -- Staff interne : passe par private.create_organization_for_new_user()
  -- (Module 12e/12n), qui crée elle-même organizations/profiles/user_roles --
  -- organization_id n'est PAS lu par handle_new_user(), seuls
  -- organization_name/organization_country/organization_phone le sont.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10l-fu@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'full_name', 'Staff Test 10l Followup',
      'organization_name', 'Test Org 10l Followup ' || substr(gen_random_uuid()::text, 1, 8),
      'organization_country', 'BJ',
      'organization_phone', '+22900000000'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_staff_id;

  -- Locataire : passe par le flux d'invitation réel (Module 12d), jamais par
  -- organization_id en métadonnées (handle_new_user exige un jeton valide
  -- dans tous les cas pour account_type='tenant').
  v_invite_hash := encode(extensions.digest(v_invite_token, 'sha256'), 'hex');
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (v_org_id, 'tenant-10l-fu@example.com', v_invite_hash, v_staff_id, now() + interval '1 day');

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10l-fu@example.com',
    jsonb_build_object(
      'account_type', 'tenant',
      'full_name', 'Tenant Test 10l Followup',
      'invitation_token', v_invite_token
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- properties.address n'existe plus depuis module12c (renommée
  -- address_complement, désormais optionnelle) -- non nécessaire pour ce
  -- test, omise.
  insert into public.properties (organization_id, name, price, location_type)
  values (v_org_id, 'Bien 10l Followup', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, end_date,
    rent_amount, payment_frequency, security_deposit_amount, utility_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date - 200, null, 100000, 'mensuel', 200000, null, 'postpaye', 'brouillon')
  returning id into v_lease_id;

  alter table public.leases disable trigger trg_leases_validate_status_transition;
  update public.leases set status = 'actif' where id = v_lease_id;
  alter table public.leases enable trigger trg_leases_validate_status_transition;

  -- S_pending : en_attente, cas nominal.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_id, current_date - 30, current_date, 100000, current_date, 'en_attente')
  returning id into v_s_pending;

  -- S_annulee : cas que le correctif doit exclure.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_id, current_date + 1, current_date + 31, 100000, current_date + 31, 'annulee')
  returning id into v_s_annulee;

  -- S_paid : en_attente (statut brut inchangé même intégralement payée --
  -- payment_schedules_status_check n'autorise que en_attente/annulee, voir
  -- Module 5b/8), avec un paiement confirmé -- ne doit PAS être exclue par
  -- le nouveau filtre (comportement financier existant préservé).
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_id, current_date - 60, current_date - 30, 100000, current_date - 30, 'en_attente')
  returning id into v_s_paid;
  insert into public.payments
    (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (v_org_id, v_lease_id, v_s_paid, 100000, current_date, 'virement', 'loyer', 'entrant', 'confirme');

  -- S_invoiced : en_attente, déjà couverte par une facture existante -- ne
  -- doit pas non plus être exclue par CE prédicat (le dédoublonnage
  -- facture/échéance est assuré ailleurs, par la contrainte
  -- invoice_schedule_items_unique + son trigger d'immutabilité, Module 9 --
  -- pas par ce filtre-ci ; on vérifie ici que le correctif ne change rien à
  -- ce comportement préexistant).
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_id, current_date - 90, current_date - 60, 100000, current_date - 60, 'en_attente')
  returning id into v_s_invoiced;

  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (v_org_id, v_lease_id, 'test/10l-followup-invoice.pdf', v_staff_id)
  returning id into v_invoice_id;
  insert into public.invoice_schedule_items (invoice_id, payment_schedule_id, organization_id)
  values (v_invoice_id, v_s_invoiced, v_org_id);

  create table pg_temp.fixtures as
  select v_lease_id as lease_id, v_s_pending as s_pending, v_s_annulee as s_annulee,
         v_s_paid as s_paid, v_s_invoiced as s_invoiced;

  -- ----------------------------------------------------------------------------
  -- 2. SÉMANTIQUE DES DONNÉES SOUS-JACENTE AU FILTRE -- pas une exécution du
  --    code TypeScript (voir avertissement de portée en tête de fichier).
  --    Le filtre lui-même (status <> 'annulee') n'est pas ce qu'on cherche à
  --    prouver ici (il est trivialement correct par construction) ; ce qui
  --    est vérifié, c'est que le statut BRUT des échéances payées/facturées
  --    reste bien 'en_attente' dans ce schéma, donc que ce filtre ne les
  --    exclut jamais par accident une fois appliqué côté TypeScript.
  -- ----------------------------------------------------------------------------
  select array_agg(id) into v_result_ids
  from public.payment_schedules
  where lease_id = v_lease_id
    and status <> 'annulee'
    and id = any(array[v_s_pending, v_s_annulee, v_s_paid, v_s_invoiced]);

  perform pg_temp.check_true(
    'en_attente jamais touchée -> proposée',
    v_s_pending = any(v_result_ids)
  );
  perform pg_temp.check_true(
    'annulee -> JAMAIS proposée',
    not (v_s_annulee = any(v_result_ids))
  );
  perform pg_temp.check_true(
    'en_attente + paiement confirmé intégral -> toujours proposée (comportement financier inchangé)',
    v_s_paid = any(v_result_ids)
  );
  perform pg_temp.check_true(
    'en_attente + déjà facturée -> toujours proposée par ce prédicat (dédoublonnage assuré ailleurs, comportement inchangé)',
    v_s_invoiced = any(v_result_ids)
  );
  perform pg_temp.check_true(
    'exactement 3 échéances proposées sur les 4 (seule annulee exclue)',
    array_length(v_result_ids, 1) = 3
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- RÉSUMÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  v_total integer;
  v_pass  integer;
  v_fail  integer;
begin
  select count(*) into v_total from pg_temp.test_results;
  select count(*) into v_pass from pg_temp.test_results where status = 'PASS';
  select count(*) into v_fail from pg_temp.test_results where status = 'FAIL';
  raise notice '============================================================';
  raise notice 'MODULE 10l FOLLOWUP (facturation) — % tests, % PASS, % FAIL', v_total, v_pass, v_fail;
  raise notice '============================================================';
  if v_fail > 0 then
    raise exception 'Module 10l followup : % test(s) en échec — voir le détail ci-dessus', v_fail;
  end if;
end;
$$;

rollback;
