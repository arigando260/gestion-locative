-- ============================================================================
-- TEST — Retrait des réservations, PASSE B (triggers et fonctions).
--
-- Vérifie que les 7 fonctions simplifiées par
-- 20260805300000_remove_reservations_b_triggers_and_functions.sql
-- continuent de faire leur travail correctement sur le seul périmètre
-- restant (bail), et que le changement de comportement volontaire
-- (validate_lease_property_location_type ne tolère plus meuble_simple)
-- fonctionne dans les deux sens.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module9_billing_documents.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_b_triggers_and_functions.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module9_billing_documents.sql).
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
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id        uuid;
  v_staff_id      uuid := gen_random_uuid();
  v_tenant_id     uuid := gen_random_uuid();
  v_prop_longue   uuid;
  v_prop_longue2  uuid;
  v_prop_meuble   uuid;
  v_lease_a       uuid;
  v_lease_other   uuid;
  v_sched_a       uuid;
  v_sched_other   uuid;
  v_invoice_a     uuid;
  v_inspection_1  uuid;
  v_inspection_2  uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org RemoveResa B', 'test-org-remove-resa-b-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-remove-resa-b@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test Remove Resa B'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-remove-resa-b@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test Remove Resa B'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaB — longue A', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_longue;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaB — longue B', '2 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_longue2;

  -- Type encore présent au catalogue à ce stade (retiré seulement à la
  -- Migration F) — sert uniquement à prouver que le bail y est désormais
  -- refusé.
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaB — meublé simple', '3 rue du Test', 500000, 'meuble_simple')
  returning id into v_prop_meuble;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_longue, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_a;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_longue2, v_tenant_id, current_date, 90000, 'mensuel', 180000, 'postpaye')
  returning id into v_lease_other;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_a, current_date, current_date + 30, 100000, current_date + 30, 'en_attente')
  returning id into v_sched_a;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_other, current_date, current_date + 30, 90000, current_date + 30, 'en_attente')
  returning id into v_sched_other;

  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (v_org_id, v_lease_a, v_org_id || '/invoice-a.pdf', v_staff_id)
  returning id into v_invoice_a;

  -- Premier état des lieux d'entrée finalisé sur lease_a (nécessaire pour
  -- les scénarios 4 et 5).
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_a, 'entree', current_date, 'finalise', v_staff_id)
  returning id into v_inspection_1;

  -- Brouillon de sortie créé par le staff (created_by_tenant = false) sur
  -- lease_a, pour le scénario 6 (restrict_tenant_inspection_update_fields).
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_a, 'sortie', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_2;

  create table pg_temp.fixtures as
  select
    v_org_id       as org_id,
    v_staff_id     as staff_id,
    v_tenant_id    as tenant_id,
    v_prop_longue  as prop_longue,
    v_prop_meuble  as prop_meuble,
    v_lease_a      as lease_a,
    v_lease_other  as lease_other,
    v_sched_a      as sched_a,
    v_sched_other  as sched_other,
    v_invoice_a    as invoice_a,
    v_inspection_1 as inspection_1,
    v_inspection_2 as inspection_2;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. validate_lease_property_location_type — meuble_simple refusé,
--    longue_duree toujours accepté.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.leases (
      organization_id, property_id, tenant_account_id, start_date,
      rent_amount, payment_frequency, security_deposit_amount, payment_timing
    ) values (f.org_id, f.prop_meuble, f.tenant_id, current_date, 80000, 'mensuel', 160000, 'postpaye');
    perform pg_temp.record('1 bail sur bien meuble_simple -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('1 bail sur bien meuble_simple -> refusé', 'PASS');
  end;

  -- lease_a (fixture) est déjà sur un bien longue_duree : sa seule
  -- existence (returning id sans exception, section 1) prouve déjà le cas
  -- accepté. On le confirme explicitement ici pour la lisibilité du résumé.
  perform pg_temp.record('2 bail sur bien longue_duree -> accepté (lease_a créé sans exception)', 'PASS');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. validate_payment_schedule_consistency — cohérence limitée au bail.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.payments (organization_id, lease_id, payment_schedule_id, amount, method, payment_type, direction)
    values (f.org_id, f.lease_a, f.sched_other, 100000, 'virement', 'loyer', 'entrant');
    perform pg_temp.record('3 paiement lease_a avec échéance de lease_other -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('3 paiement lease_a avec échéance de lease_other -> refusé', 'PASS');
  end;

  begin
    insert into public.payments (organization_id, lease_id, payment_schedule_id, amount, method, payment_type, direction)
    values (f.org_id, f.lease_a, f.sched_a, 100000, 'virement', 'loyer', 'entrant');
    perform pg_temp.record('4 paiement lease_a avec échéance de lease_a -> accepté', 'PASS');
  exception when others then
    perform pg_temp.record('4 paiement lease_a avec échéance de lease_a -> accepté', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. validate_deposit_ledger_balance — verrou et solde limités au bail.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  -- deposit_type = 'caution_utilities' + imputation_category =
  -- 'impayes_utilities' (pas 'avance_garantie'/'degats') : seul couple
  -- valide pour 'impayes_utilities' (deposit_ledger_category_matches_
  -- deposit_type, Module 6) qui isole la vérification de solde de
  -- validate_deposit_ledger_balance (celle touchée par Migration B) de
  -- l'exigence d'état des lieux d'entrée validé, propre à 'degats'
  -- (private.validate_deposit_ledger_damage_imputation_requires_inspections,
  -- Module 6, sans rapport avec cette migration — non satisfaite par ce
  -- fixture minimal).
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, f.lease_a, 'caution_utilities', 'depot_initial', 200000);

  begin
    insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, imputation_category, amount, reason)
    values (f.org_id, f.lease_a, 'caution_utilities', 'imputation', 'impayes_utilities', 250000, 'test dépassement');
    perform pg_temp.record('5 imputation > solde détenu -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.check_detail('5 imputation > solde détenu -> refusée',
      (sqlerrm like 'Imputation/remboursement refusé : solde insuffisant%')::text, 'true');
  end;

  begin
    insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, imputation_category, amount, reason)
    values (f.org_id, f.lease_a, 'caution_utilities', 'imputation', 'impayes_utilities', 100000, 'test dans la limite');
    perform pg_temp.record('6 imputation <= solde détenu -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('6 imputation <= solde détenu -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. validate_property_inspection_not_duplicate — doublon limité au bail.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.lease_a, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('7 deuxième entree sur lease_a (première non contestée) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7 deuxième entree sur lease_a (première non contestée) -> refusée', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. prevent_finalized_inspection_change — lease_id toujours immuable après
--    finalisation.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  begin
    update public.property_inspections set lease_id = f.lease_other where id = f.inspection_1;
    perform pg_temp.record('8 changer lease_id d''un état des lieux finalisé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('8 changer lease_id d''un état des lieux finalisé -> refusé', 'PASS');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. restrict_tenant_inspection_update_fields — un locataire ne peut pas
--    changer lease_id, même sur un brouillon qu'il n'a pas créé lui-même.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    update public.property_inspections set lease_id = f.lease_other where id = f.inspection_2;
    perform pg_temp.record('9 locataire change lease_id d''un brouillon créé par le staff -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('9 locataire change lease_id d''un brouillon créé par le staff -> refusé', 'PASS');
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. validate_invoice_schedule_item_consistency — cohérence limitée au bail.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  begin
    insert into public.invoice_schedule_items (organization_id, invoice_id, payment_schedule_id)
    values (f.org_id, f.invoice_a, f.sched_a);
    perform pg_temp.record('10 échéance de lease_a sur facture de lease_a -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('10 échéance de lease_a sur facture de lease_a -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  begin
    insert into public.invoice_schedule_items (organization_id, invoice_id, payment_schedule_id)
    values (f.org_id, f.invoice_a, f.sched_other);
    perform pg_temp.record('11 échéance de lease_other sur facture de lease_a -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('11 échéance de lease_other sur facture de lease_a -> refusée', v_detail, 'invoice_schedule_item.mismatch.lease_or_reservation');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. RÉSUMÉ.
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
