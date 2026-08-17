-- ============================================================================
-- TEST — Retrait des réservations, PASSE A (RLS + statut effectif).
--
-- Vérifie que l'accès locataire "via une réservation qui lui appartient"
-- a bien disparu des policies SELECT, sans rien casser côté "via un bail
-- qui lui appartient" (régression). Échantillon représentatif plutôt
-- qu'exhaustif : properties_select, payment_schedules_select,
-- property_inspections_select et schedule_invoices_select couvrent les 3
-- formes de prédicat touchées par la migration (accès direct par
-- tenant_account_id, jointure simple property_inspections/leases, jointure
-- avec has_permission du Module 9). inspection_items_select,
-- inspection_photos_select, invoice_schedule_items_select,
-- payment_receipts_select et les 2 policies storage.objects appliquent
-- mécaniquement le même retrait de clause — non re-testés individuellement,
-- même choix de profondeur que supabase/tests/module9_billing_documents.sql
-- qui ne re-teste pas non plus chaque policy RLS de son propre module.
--
-- Le changement de private.property_effective_status /
-- properties_effective_status (réservation qui ne compte plus comme
-- occupation) est couvert séparément par le scénario 2, mis à jour, de
-- supabase/tests/module2c_property_effective_status.sql — pas dupliqué ici.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module8_lease_termination_consensus.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_a_rls_and_effective_status.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module8_lease_termination_consensus.sql).
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

create or replace function pg_temp.check_count(p_name text, p_got bigint, p_expected bigint)
returns void language plpgsql as $$
begin
  if p_got = p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('lignes attendues=%s, obtenues=%s', p_expected, p_got));
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
-- 1. FIXTURES — un bien longue_duree avec bail actif (tenant_lease), un bien
--    courte_duree avec réservation confirmée (tenant_reservation), une
--    échéance/un état des lieux/une facture liés à chacun.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id          uuid;
  v_staff_id        uuid := gen_random_uuid();
  v_tenant_lease_id uuid := gen_random_uuid();
  v_tenant_resa_id  uuid := gen_random_uuid();
  v_prop_lease      uuid;
  v_prop_resa       uuid;
  v_lease_id        uuid;
  v_resa_id         uuid;
  v_sched_lease     uuid;
  v_sched_resa      uuid;
  v_inspection_lease uuid;
  v_inspection_resa  uuid;
  v_invoice_lease    uuid;
  v_invoice_resa     uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org RemoveResa A', 'test-org-remove-resa-a-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-remove-resa-a@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test Remove Resa A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_lease_id, 'tenant-lease-remove-resa-a@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Bail Test Remove Resa A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_resa_id, 'tenant-resa-remove-resa-a@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Résa Test Remove Resa A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaA — bail', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_lease;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien RemoveResaA — réservation', '2 rue du Test', 500000, 'courte_duree')
  returning id into v_prop_resa;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_lease, v_tenant_lease_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.reservations (
    organization_id, property_id, tenant_account_id,
    check_in_date, check_out_date, nightly_rate, total_amount
  ) values (
    v_org_id, v_prop_resa, v_tenant_resa_id,
    current_date - 1, current_date + 3, 25000, 100000
  ) returning id into v_resa_id;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_id, current_date, current_date + 30, 100000, current_date + 30, 'en_attente')
  returning id into v_sched_lease;

  insert into public.payment_schedules (organization_id, reservation_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_resa_id, current_date - 1, current_date + 3, 100000, current_date + 3, 'en_attente')
  returning id into v_sched_resa;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status)
  values (v_org_id, v_lease_id, 'entree', current_date, 'brouillon')
  returning id into v_inspection_lease;

  insert into public.property_inspections (organization_id, reservation_id, inspection_type, inspection_date, document_status)
  values (v_org_id, v_resa_id, 'entree', current_date, 'brouillon')
  returning id into v_inspection_resa;

  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (v_org_id, v_lease_id, v_org_id || '/lease-invoice.pdf', v_staff_id)
  returning id into v_invoice_lease;

  insert into public.schedule_invoices (organization_id, reservation_id, storage_path, generated_by)
  values (v_org_id, v_resa_id, v_org_id || '/resa-invoice.pdf', v_staff_id)
  returning id into v_invoice_resa;

  create table pg_temp.fixtures as
  select
    v_org_id           as org_id,
    v_staff_id         as staff_id,
    v_tenant_lease_id  as tenant_lease_id,
    v_tenant_resa_id   as tenant_resa_id,
    v_prop_lease       as prop_lease,
    v_prop_resa        as prop_resa,
    v_lease_id         as lease_id,
    v_resa_id          as resa_id,
    v_sched_lease      as sched_lease,
    v_sched_resa       as sched_resa,
    v_inspection_lease as inspection_lease,
    v_inspection_resa  as inspection_resa,
    v_invoice_lease    as invoice_lease,
    v_invoice_resa     as invoice_resa;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. TENANT_LEASE (accès via bail) — doit toujours tout lire (régression).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count bigint;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_lease_id);

  select count(*) into v_count from public.properties where id = f.prop_lease;
  perform pg_temp.check_count('1 tenant_lease lit son bien via bail -> 1 ligne', v_count, 1);

  select count(*) into v_count from public.payment_schedules where id = f.sched_lease;
  perform pg_temp.check_count('2 tenant_lease lit son échéance via bail -> 1 ligne', v_count, 1);

  select count(*) into v_count from public.property_inspections where id = f.inspection_lease;
  perform pg_temp.check_count('3 tenant_lease lit son état des lieux via bail -> 1 ligne', v_count, 1);

  select count(*) into v_count from public.schedule_invoices where id = f.invoice_lease;
  perform pg_temp.check_count('4 tenant_lease lit sa facture via bail -> 1 ligne', v_count, 1);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. TENANT_RESA (accès via réservation) — ne doit plus rien lire, la
--    deuxième voie d'accès RLS a été retirée par la migration.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count bigint;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_resa_id);

  select count(*) into v_count from public.properties where id = f.prop_resa;
  perform pg_temp.check_count('5 tenant_resa ne lit plus son bien via réservation -> 0 ligne', v_count, 0);

  select count(*) into v_count from public.payment_schedules where id = f.sched_resa;
  perform pg_temp.check_count('6 tenant_resa ne lit plus son échéance via réservation -> 0 ligne', v_count, 0);

  select count(*) into v_count from public.property_inspections where id = f.inspection_resa;
  perform pg_temp.check_count('7 tenant_resa ne lit plus son état des lieux via réservation -> 0 ligne', v_count, 0);

  select count(*) into v_count from public.schedule_invoices where id = f.invoice_resa;
  perform pg_temp.check_count('8 tenant_resa ne lit plus sa facture via réservation -> 0 ligne', v_count, 0);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. STAFF — accès interne inchangé (régression), sur les deux biens.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count bigint;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  select count(*) into v_count from public.properties where id in (f.prop_lease, f.prop_resa);
  perform pg_temp.check_count('9 staff lit toujours les 2 biens de son organisation -> 2 lignes', v_count, 2);
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
