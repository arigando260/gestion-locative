-- ============================================================================
-- TEST — Module 10l (reconduction tacite du générateur d'échéances +
-- annulation des échéances au-delà de la date C lors d'une résiliation
-- validée).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/.
--
-- Même patron que module10_lease_lifecycle.sql / module8_lease_termination_
-- consensus.sql :
--   - Tout s'exécute dans une seule transaction, ROLLBACK en toute fin.
--   - Fixtures montées avec le rôle propriétaire (bypasse RLS), scénarios
--     basculés explicitement via pg_temp.act_as().
--   - Résultats : RAISE NOTICE '[PASS|FAIL] ...' au fil de l'eau, résumé
--     tabulaire juste avant le ROLLBACK.
--
-- Exécution (méthode DEV réelle du projet -- pas de Docker/Supabase local,
-- voir ARCHITECTURE.md "Séparation dev/prod") :
--   npx supabase db query --file supabase/tests/module10l_tacit_renewal_and_post_termination_schedules.sql \
--     --db-url "<SUPABASE_DB_URL issue de .env.local, jamais .env.prod-admin.local>"
--
-- Pas de \set ON_ERROR_STOP : méta-commande propre à psql, sans effet (et
-- source d'erreur) via `supabase db query`, qui envoie le fichier tel quel
-- au serveur -- le begin;/rollback; explicite ci-dessous suffit à isoler le
-- script dans une seule transaction annulée en fin d'exécution.
-- ============================================================================

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

create or replace function pg_temp.check_int(p_name text, p_got integer, p_expected integer)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('détail attendu=%s, obtenu=%s', p_expected, p_got));
  end if;
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

-- Comme pg_temp.new_lease (module10_lease_lifecycle.sql), avec end_date en
-- paramètre optionnel supplémentaire — nécessaire ici pour fabriquer des
-- baux déjà à/après leur échéance sans passer par un vrai écoulement du
-- temps.
create or replace function pg_temp.new_lease(
  p_org uuid,
  p_tenant uuid,
  p_label text,
  p_start_date date default current_date - 400,
  p_end_date date default null,
  p_security_deposit numeric default 200000
) returns uuid language plpgsql as $$
declare
  v_prop  uuid;
  v_lease uuid;
begin
  -- properties.address n'existe plus depuis module12c (renommée
  -- address_complement, désormais optionnelle) -- non nécessaire ici, omise.
  insert into public.properties (organization_id, name, price, location_type)
  values (p_org, 'Bien 10l — ' || p_label, 500000, 'longue_duree')
  returning id into v_prop;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, end_date,
    rent_amount, payment_frequency, security_deposit_amount, utility_deposit_amount, payment_timing
  ) values (p_org, v_prop, p_tenant, p_start_date, p_end_date, 100000, 'mensuel', p_security_deposit, null, 'postpaye')
  returning id into v_lease;

  return v_lease;
end;
$$;

-- Fabrique un bail à un statut de départ donné, en désactivant temporairement
-- le trigger de garde — UNIQUEMENT pour monter une fixture (bail déjà
-- 'actif' sans repasser par le parcours d'activation, déjà prouvé au Module
-- 10 ; ou déjà 'termine'). Jamais un chemin testé en lui-même. Même
-- technique que module10_lease_lifecycle.sql.
create or replace function pg_temp.force_lease_status(p_lease uuid, p_status text)
returns void language plpgsql as $$
begin
  alter table public.leases disable trigger trg_leases_validate_status_transition;
  update public.leases set status = p_status where id = p_lease;
  alter table public.leases enable trigger trg_leases_validate_status_transition;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — une organisation, un staff (admin), un locataire.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_invite_token text := gen_random_uuid()::text;
  v_invite_hash  text;
begin
  -- Staff interne : passe par private.create_organization_for_new_user()
  -- (Module 12e/12n) -- organization_id n'est plus lu par handle_new_user(),
  -- seuls organization_name/organization_country/organization_phone le sont ;
  -- l'organisation est créée par le trigger, jamais pré-créée par l'appelant
  -- (même mécanisme que déjà validé 5/5 dans
  -- module10l_followup_invoice_excludes_annulee.sql).
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10l@example.com',
    jsonb_build_object(
      'account_type', 'internal',
      'full_name', 'Staff Test 10l',
      'organization_name', 'Test Org 10l ' || substr(gen_random_uuid()::text, 1, 8),
      'organization_country', 'BJ',
      'organization_phone', '+22900000000'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  select organization_id into v_org_id from public.profiles where id = v_staff_id;
  -- Le rôle admin est déjà attribué par create_organization_for_new_user()
  -- (insert user_roles interne à la fonction) -- un second insert ici
  -- dupliquerait la clé primaire (user_id, role_id), retiré.

  -- Locataire : flux d'invitation réel (Module 12d), jamais organization_id
  -- en métadonnées (handle_new_user exige un jeton valide dans tous les cas
  -- pour account_type='tenant').
  v_invite_hash := encode(extensions.digest(v_invite_token, 'sha256'), 'hex');
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (v_org_id, 'tenant-10l@example.com', v_invite_hash, v_staff_id, now() + interval '1 day');

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10l@example.com',
    jsonb_build_object(
      'account_type', 'tenant',
      'full_name', 'Tenant Test 10l',
      'invitation_token', v_invite_token
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_tenant_id as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

select pg_temp.act_as_owner();

-- ============================================================================
-- SCÉNARIO 1 — bail actif AVANT son end_date : comportement inchangé.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_inserted integer;
  v_max_start date;
  v_total integer;
  v_cancelled integer;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '1', current_date - 60, current_date + 30);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  select public.generate_payment_schedules_for_lease(v_lease) into v_inserted;
  select max(period_start_date) into v_max_start from public.payment_schedules where lease_id = v_lease;

  -- 1a teste le résultat métier réel (des échéances existent bien pour ce
  -- bail, aucune annulée), pas la valeur de retour de CET appel précis --
  -- trg_leases_generate_schedules_on_activation (Module 10, comportement
  -- réel et voulu) a déjà généré les échéances au passage brouillon->actif
  -- (force_lease_status ci-dessus) ; l'appel explicite qui suit est donc un
  -- second appel légitimement idempotent, qui peut renvoyer 0 sans que ce
  -- soit une anomalie. Une vraie régression du générateur (aucune échéance
  -- produite, par le trigger ou l'appel explicite) fait toujours échouer
  -- cette assertion.
  select count(*) into v_total from public.payment_schedules where lease_id = v_lease;
  select count(*) into v_cancelled from public.payment_schedules where lease_id = v_lease and status = 'annulee';
  perform pg_temp.check_true(
    '1a bail actif avant end_date -> au moins une échéance existe pour ce bail, aucune annulée',
    v_total > 0 and v_cancelled = 0
  );
  perform pg_temp.check_true('1b bail actif avant end_date -> plafonné strictement à end_date', v_max_start < current_date + 30);
end;
$$;

-- ============================================================================
-- SCÉNARIO 2 — bail actif ARRIVÉ à end_date (aujourd'hui), sans résiliation.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_inserted integer;
  v_max_start date;
  v_total integer;
  v_cancelled integer;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '2', current_date - 365, current_date);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  select public.generate_payment_schedules_for_lease(v_lease) into v_inserted;
  select max(period_start_date) into v_max_start from public.payment_schedules where lease_id = v_lease;

  perform pg_temp.check_true('2a bail actif arrivé à end_date -> génère au-delà (reconduction tacite)', v_max_start >= current_date);

  -- 2b : même principe que 1a -- résultat métier réel plutôt que la valeur
  -- de retour de ce seul appel (voir commentaire détaillé au scénario 1).
  select count(*) into v_total from public.payment_schedules where lease_id = v_lease;
  select count(*) into v_cancelled from public.payment_schedules where lease_id = v_lease and status = 'annulee';
  perform pg_temp.check_true(
    '2b bail actif arrivé à end_date -> au moins une échéance existe pour ce bail, aucune annulée',
    v_total > 0 and v_cancelled = 0
  );
end;
$$;

-- ============================================================================
-- SCÉNARIO 3 — bail actif PLUSIEURS MOIS après end_date : reconduction
-- tacite avancée + end_date jamais modifiée en base.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_end_before date;
  v_end_after date;
  v_max_start date;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '3', current_date - 500, current_date - 90);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  select end_date into v_end_before from public.leases where id = v_lease;
  perform public.generate_payment_schedules_for_lease(v_lease);
  select end_date into v_end_after from public.leases where id = v_lease;
  select max(period_start_date) into v_max_start from public.payment_schedules where lease_id = v_lease;

  perform pg_temp.check_detail('3a end_date jamais réécrite par le générateur', v_end_after::text, v_end_before::text);
  perform pg_temp.check_true('3b échéances générées bien au-delà de l''ancienne end_date', v_max_start > current_date - 90);
end;
$$;

-- ============================================================================
-- SCÉNARIO 4 — résiliation EN ATTENTE (non validée) : n'interrompt PAS la
-- reconduction tacite, ne touche aucune échéance.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_request_id uuid;
  v_status_before text;
  v_annulee_count integer;
  v_max_start date;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '4', current_date - 400, current_date - 5);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, v_lease, f.tenant_id, null, current_date + 30, 'Test scénario 4')
  returning id into v_request_id;

  perform pg_temp.act_as_owner();
  select status into v_status_before from public.leases where id = v_lease;
  perform public.generate_payment_schedules_for_lease(v_lease);
  select max(period_start_date) into v_max_start from public.payment_schedules where lease_id = v_lease;
  select count(*) into v_annulee_count from public.payment_schedules where lease_id = v_lease and status = 'annulee';

  perform pg_temp.check_detail('4a résiliation en_attente -> bail toujours actif', v_status_before, 'actif');
  perform pg_temp.check_true('4b résiliation en_attente -> génération continue au-delà de l''ancienne end_date', v_max_start > current_date - 5);
  perform pg_temp.check_int('4c résiliation en_attente -> aucune échéance annulée', v_annulee_count, 0);
end;
$$;

-- ============================================================================
-- SCÉNARIO 5 — résiliation VALIDÉE, C postérieure à l'ancienne end_date.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_request_id uuid;
  v_old_end date := current_date + 10;
  v_new_end date := current_date + 60;
  v_status text;
  v_end date;
  v_max_start date;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '5', current_date - 300, v_old_end);
  perform pg_temp.force_lease_status(v_lease, 'actif');
  perform public.generate_payment_schedules_for_lease(v_lease);

  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, v_lease, null, f.staff_id, v_new_end, 'Test scénario 5')
  returning id into v_request_id;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  update public.lease_termination_requests set status = 'validee' where id = v_request_id;

  perform pg_temp.act_as_owner();
  select status, end_date into v_status, v_end from public.leases where id = v_lease;
  perform public.generate_payment_schedules_for_lease(v_lease);
  select max(period_start_date) into v_max_start from public.payment_schedules where lease_id = v_lease;

  perform pg_temp.check_detail('5a résiliation validée -> status=resilie', v_status, 'resilie');
  perform pg_temp.check_detail('5b résiliation validée -> end_date=C', v_end::text, v_new_end::text);
  perform pg_temp.check_true('5c C postérieure -> le générateur produit bien jusqu''à C', v_max_start >= v_old_end and v_max_start < v_new_end);
end;
$$;

-- ============================================================================
-- SCÉNARIO 6-10-13 — résiliation VALIDÉE, C ANTÉRIEURE à l'ancienne
-- end_date, avec échéances pré-existantes dans des situations différentes :
--   S1 : vierge, post-C stricte                -> annulée (7)
--   S2 : payée intégralement, post-C           -> conservée (8)
--   S3 : payée partiellement, post-C           -> conservée (9)
--   S4 : imputation de dépôt, post-C           -> conservée (10)
--   S5 : period_start_date = C exactement      -> annulée (13)
--   S6 : chevauche C (start < C < end)         -> inchangée (11)
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_old_end date := current_date + 90;
  v_c date := current_date + 10;
  v_request_id uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid; v_s6 uuid;
  v_pay_id uuid;
  v_status text;
  v_stat1 text; v_stat2 text; v_stat3 text; v_stat4 text; v_stat5 text; v_stat6 text;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '6', current_date - 200, v_old_end);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  -- S1 : vierge, nettement après C.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c + 5, v_c + 35, 100000, v_c + 35, 'en_attente')
  returning id into v_s1;

  -- S2 : payée intégralement, après C.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c + 20, v_c + 50, 100000, v_c + 50, 'en_attente')
  returning id into v_s2;
  insert into public.payments
    (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (f.org_id, v_lease, v_s2, 100000, current_date, 'virement', 'loyer', 'entrant', 'confirme');

  -- S3 : payée partiellement, après C.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c + 35, v_c + 65, 100000, v_c + 65, 'en_attente')
  returning id into v_s3;
  insert into public.payments
    (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (f.org_id, v_lease, v_s3, 40000, current_date, 'virement', 'loyer', 'entrant', 'confirme');

  -- S4 : imputation de dépôt (loyer), après C. Prérequis découverts à
  -- l'exécution réelle (jamais atteints par les tentatives précédentes,
  -- bloquées plus tôt) : private.validate_deposit_ledger_balance() exige un
  -- solde détenu (entry_type='depot_initial') suffisant AVANT toute
  -- imputation, et private.validate_deposit_ledger_rent_imputation_
  -- authorized() exige leases.advance_consumption_authorized=true pour une
  -- imputation_category='loyer' sur deposit_type='avance_garantie'. Aucun
  -- des deux n'est lié au Lot 1 -- logique Module 5/8 préexistante.
  update public.leases
  set advance_consumption_authorized = true,
      advance_consumption_authorized_at = now(),
      advance_consumption_authorized_by = f.staff_id
  where id = v_lease;

  insert into public.deposit_ledger
    (organization_id, lease_id, deposit_type, entry_type, amount, reason)
  values (f.org_id, v_lease, 'avance_garantie', 'depot_initial', 200000, 'Test scénario 10 - dépôt initial');

  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c + 50, v_c + 80, 100000, v_c + 80, 'en_attente')
  returning id into v_s4;
  insert into public.deposit_ledger
    (organization_id, lease_id, deposit_type, entry_type, imputation_category, amount, reason, payment_schedule_id)
  values (f.org_id, v_lease, 'avance_garantie', 'imputation', 'loyer', 100000, 'Test scénario 10', v_s4);

  -- S5 : exactement à C.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c, v_c + 30, 100000, v_c + 30, 'en_attente')
  returning id into v_s5;

  -- S6 : chevauche C (commence avant, se termine après) — jamais touchée.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, v_lease, v_c - 5, v_c + 25, 100000, v_c + 25, 'en_attente')
  returning id into v_s6;

  -- Résiliation : staff initie, locataire valide, C = v_c (antérieure à v_old_end).
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, v_lease, null, f.staff_id, v_c, 'Test scénarios 6-10-13')
  returning id into v_request_id;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  update public.lease_termination_requests set status = 'validee' where id = v_request_id;

  perform pg_temp.act_as_owner();
  select status into v_status from public.leases where id = v_lease;
  select status into v_stat1 from public.payment_schedules where id = v_s1;
  select status into v_stat2 from public.payment_schedules where id = v_s2;
  select status into v_stat3 from public.payment_schedules where id = v_s3;
  select status into v_stat4 from public.payment_schedules where id = v_s4;
  select status into v_stat5 from public.payment_schedules where id = v_s5;
  select status into v_stat6 from public.payment_schedules where id = v_s6;

  perform pg_temp.check_detail('6a résiliation validée, C avant l''ancienne end_date -> status=resilie', v_status, 'resilie');
  perform pg_temp.check_detail('7 échéance vierge post-C -> annulee', v_stat1, 'annulee');
  perform pg_temp.check_detail('8 échéance payée intégralement post-C -> conservée en_attente', v_stat2, 'en_attente');
  perform pg_temp.check_detail('9 échéance payée partiellement post-C -> conservée en_attente', v_stat3, 'en_attente');
  perform pg_temp.check_detail('10 échéance avec imputation de dépôt post-C -> conservée en_attente', v_stat4, 'en_attente');
  perform pg_temp.check_detail('13 échéance exactement à C (period_start_date = C) -> annulee', v_stat5, 'annulee');
  perform pg_temp.check_detail('11 échéance chevauchant C (start<C<end) -> inchangée, non proratisée', v_stat6, 'en_attente');
end;
$$;

-- ============================================================================
-- SCÉNARIO 12 — génération répétée (idempotence), y compris sur la branche
-- reconduction tacite nouvellement activée.
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_count_1 integer;
  v_count_2 integer;
  v_second_call integer;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '12', current_date - 500, current_date - 120);
  perform pg_temp.force_lease_status(v_lease, 'actif');

  perform public.generate_payment_schedules_for_lease(v_lease);
  select count(*) into v_count_1 from public.payment_schedules where lease_id = v_lease;

  select public.generate_payment_schedules_for_lease(v_lease) into v_second_call;
  select count(*) into v_count_2 from public.payment_schedules where lease_id = v_lease;

  perform pg_temp.check_int('12a deuxième appel immédiat -> aucune ligne insérée (horizon déjà couvert)', v_second_call, 0);
  perform pg_temp.check_int('12b deuxième appel -> aucun doublon (nombre de lignes inchangé)', v_count_2, v_count_1);
end;
$$;

-- ============================================================================
-- SCÉNARIO 14 — bail TERMINÉ : aucune génération au-delà de sa couverture
-- déjà atteinte (comportement inchangé — la relaxation ne s'applique qu'à
-- status='actif').
-- ============================================================================

do $$
declare
  f record;
  v_lease uuid;
  v_end date := current_date - 200;
  v_count_before integer;
  v_inserted integer;
  v_count_after integer;
begin
  select * into f from pg_temp.fixtures;
  v_lease := pg_temp.new_lease(f.org_id, f.tenant_id, '14', current_date - 300, v_end);
  perform pg_temp.force_lease_status(v_lease, 'actif');
  perform public.generate_payment_schedules_for_lease(v_lease); -- couverture complète jusqu'à v_end

  select count(*) into v_count_before from public.payment_schedules where lease_id = v_lease;
  perform pg_temp.force_lease_status(v_lease, 'termine');

  select public.generate_payment_schedules_for_lease(v_lease) into v_inserted;
  select count(*) into v_count_after from public.payment_schedules where lease_id = v_lease;

  perform pg_temp.check_int('14a bail terminé -> aucune nouvelle échéance générée', v_inserted, 0);
  perform pg_temp.check_int('14b bail terminé -> nombre total d''échéances inchangé', v_count_after, v_count_before);
end;
$$;

-- ============================================================================
-- RÉSUMÉ.
-- ============================================================================

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
  raise notice 'MODULE 10l — % tests, % PASS, % FAIL', v_total, v_pass, v_fail;
  raise notice '============================================================';
  if v_fail > 0 then
    raise exception 'Module 10l : % test(s) en échec — voir le détail ci-dessus', v_fail;
  end if;
end;
$$;

rollback;
