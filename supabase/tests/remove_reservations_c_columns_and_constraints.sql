-- ============================================================================
-- TEST — Retrait des réservations, PASSE C (colonnes et contraintes XOR).
--
-- Pour chacune des 5 tables (payment_schedules, payments, deposit_ledger,
-- property_inspections, schedule_invoices) : un INSERT normal avec
-- lease_id seul fonctionne toujours (non-régression), et un INSERT avec
-- lease_id NULL est refusé par la nouvelle contrainte ..._lease_required
-- (23514, nom de contrainte vérifié). Les 3 vues recréées pendant cette
-- passe (payment_schedules_effective_status, deposit_ledger_balances,
-- property_inspections_effective_status — DROP VIEW/CREATE VIEW pour lever
-- leur dépendance dure sur reservation_id) sont interrogées une fois
-- chacune pour confirmer qu'elles répondent toujours correctement.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module9_billing_documents.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_c_columns_and_constraints.sql
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

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id     uuid;
  v_staff_id   uuid := gen_random_uuid();
  v_tenant_id  uuid := gen_random_uuid();
  v_prop_id    uuid;
  v_lease_id   uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org RemoveResa C', 'test-org-remove-resa-c-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-remove-resa-c@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test Remove Resa C'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-remove-resa-c@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test Remove Resa C'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaC', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  create table pg_temp.fixtures as
  select
    v_org_id    as org_id,
    v_staff_id  as staff_id,
    v_tenant_id as tenant_id,
    v_prop_id   as prop_id,
    v_lease_id  as lease_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. PAYMENT_SCHEDULES.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sched_id   uuid;
  v_sqlstate   text;
  v_constraint text;
  v_effective  text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, f.lease_id, current_date, current_date + 30, 100000, current_date + 30, 'en_attente')
  returning id into v_sched_id;
  perform pg_temp.record('1 payment_schedules : insert avec lease_id seul -> accepté', 'PASS');

  begin
    insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
    values (f.org_id, null, current_date, current_date + 30, 100000, current_date + 30, 'en_attente');
    perform pg_temp.record('2 payment_schedules : insert avec lease_id NULL -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'payment_schedules_lease_required' then
      perform pg_temp.record('2 payment_schedules : insert avec lease_id NULL -> refusé', 'PASS');
    else
      perform pg_temp.record('2 payment_schedules : insert avec lease_id NULL -> refusé', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
    end if;
  end;

  select effective_status into v_effective
  from public.payment_schedules_effective_status where id = v_sched_id;
  perform pg_temp.check_detail('3 payment_schedules_effective_status répond toujours (vue recréée)', v_effective, 'en_attente');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. PAYMENTS.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sqlstate   text;
  v_constraint text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.payments (organization_id, lease_id, amount, method, payment_type, direction)
  values (f.org_id, f.lease_id, 100000, 'virement', 'loyer', 'entrant');
  perform pg_temp.record('4 payments : insert avec lease_id seul -> accepté', 'PASS');

  begin
    insert into public.payments (organization_id, lease_id, amount, method, payment_type, direction)
    values (f.org_id, null, 100000, 'virement', 'loyer', 'entrant');
    perform pg_temp.record('5 payments : insert avec lease_id NULL -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'payments_lease_required' then
      perform pg_temp.record('5 payments : insert avec lease_id NULL -> refusé', 'PASS');
    else
      perform pg_temp.record('5 payments : insert avec lease_id NULL -> refusé', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
    end if;
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. DEPOSIT_LEDGER.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sqlstate   text;
  v_constraint text;
  v_held       numeric;
begin
  select * into f from pg_temp.fixtures;

  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, f.lease_id, 'avance_garantie', 'depot_initial', 200000);
  perform pg_temp.record('6 deposit_ledger : insert avec lease_id seul -> accepté', 'PASS');

  begin
    insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
    values (f.org_id, null, 'avance_garantie', 'depot_initial', 200000);
    perform pg_temp.record('7 deposit_ledger : insert avec lease_id NULL -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'deposit_ledger_lease_required' then
      perform pg_temp.record('7 deposit_ledger : insert avec lease_id NULL -> refusé', 'PASS');
    else
      perform pg_temp.record('7 deposit_ledger : insert avec lease_id NULL -> refusé', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
    end if;
  end;

  select amount_held into v_held
  from public.deposit_ledger_balances
  where lease_id = f.lease_id and deposit_type = 'avance_garantie';
  perform pg_temp.check_detail('8 deposit_ledger_balances répond toujours (vue recréée)', v_held::text, '200000.00');
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. PROPERTY_INSPECTIONS.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_insp_id    uuid;
  v_sqlstate   text;
  v_constraint text;
  v_effective  text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status)
  values (f.org_id, f.lease_id, 'entree', current_date, 'brouillon')
  returning id into v_insp_id;
  perform pg_temp.record('9 property_inspections : insert avec lease_id seul -> accepté', 'PASS');

  begin
    insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status)
    values (f.org_id, null, 'entree', current_date, 'brouillon');
    perform pg_temp.record('10 property_inspections : insert avec lease_id NULL -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'property_inspections_lease_required' then
      perform pg_temp.record('10 property_inspections : insert avec lease_id NULL -> refusé', 'PASS');
    else
      perform pg_temp.record('10 property_inspections : insert avec lease_id NULL -> refusé', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
    end if;
  end;

  select effective_validation_status into v_effective
  from public.property_inspections_effective_status where id = v_insp_id;
  perform pg_temp.check_detail('11 property_inspections_effective_status répond toujours (vue recréée)', v_effective, 'en_attente');
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCHEDULE_INVOICES.
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sqlstate   text;
  v_constraint text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (f.org_id, f.lease_id, f.org_id || '/invoice.pdf', f.staff_id);
  perform pg_temp.record('12 schedule_invoices : insert avec lease_id seul -> accepté', 'PASS');

  begin
    insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
    values (f.org_id, null, f.org_id || '/invoice-2.pdf', f.staff_id);
    perform pg_temp.record('13 schedule_invoices : insert avec lease_id NULL -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'schedule_invoices_lease_required' then
      perform pg_temp.record('13 schedule_invoices : insert avec lease_id NULL -> refusé', 'PASS');
    else
      perform pg_temp.record('13 schedule_invoices : insert avec lease_id NULL -> refusé', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
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
