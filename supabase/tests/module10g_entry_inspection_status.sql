-- ============================================================================
-- TEST — Module 10g (leases_closure_status : lecture symétrique entrée).
--
-- 2 baux actifs : un avec état des lieux d'entrée finalisé, un sans aucun.
-- Vérifie aussi, sur les deux mêmes baux, que la partie sortie (déjà en
-- place) reste inchangée par ce CREATE OR REPLACE VIEW — régression bon
-- marché sur un objet entièrement redéfini.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module10_lease_lifecycle.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10g_entry_inspection_status.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module10_lease_lifecycle.sql).
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
-- 1. FIXTURES — deux baux actifs (status forcé, garde-fou de transition
--    désactivé le temps de l'insertion, même technique que
--    supabase/tests/module2c_property_effective_status.sql — hors sujet
--    ici, ce test porte sur une vue de lecture, pas sur le cycle de vie du
--    bail) : lease_with reçoit un état des lieux d'entrée finalisé,
--    lease_without n'en reçoit aucun.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id         uuid;
  v_staff_id       uuid := gen_random_uuid();
  v_tenant_id      uuid := gen_random_uuid();
  v_prop_with      uuid;
  v_prop_without   uuid;
  v_lease_with     uuid;
  v_lease_without  uuid;
  v_inspection_id  uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10g', 'test-org-10g-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10g@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10g'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10g@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10g'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10g — avec entrée', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_with;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10g — sans entrée', '2 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_without;

  alter table public.leases disable trigger trg_leases_validate_status_transition;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_with, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye', 'actif')
  returning id into v_lease_with;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_without, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye', 'actif')
  returning id into v_lease_without;

  alter table public.leases enable trigger trg_leases_validate_status_transition;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_with, 'entree', current_date, 'finalise', v_staff_id)
  returning id into v_inspection_id;

  create table pg_temp.fixtures as
  select
    v_lease_with    as lease_with,
    v_lease_without as lease_without,
    v_inspection_id as inspection_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — BAIL AVEC ÉTAT DES LIEUX D'ENTRÉE FINALISÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v record;
begin
  select * into f from pg_temp.fixtures;
  select entry_inspection_done, latest_finalized_entry_inspection_id, exit_inspection_done
    into v
  from public.leases_closure_status
  where lease_id = f.lease_with;

  perform pg_temp.check_detail('1 lease_with : entry_inspection_done = true', v.entry_inspection_done::text, 'true');
  perform pg_temp.check_detail('2 lease_with : latest_finalized_entry_inspection_id = celui créé', v.latest_finalized_entry_inspection_id::text, f.inspection_id::text);
  perform pg_temp.check_detail('3 lease_with : exit_inspection_done inchangé (false, régression)', v.exit_inspection_done::text, 'false');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — BAIL SANS AUCUN ÉTAT DES LIEUX D'ENTRÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v record;
begin
  select * into f from pg_temp.fixtures;
  select entry_inspection_done, latest_finalized_entry_inspection_id, exit_inspection_done
    into v
  from public.leases_closure_status
  where lease_id = f.lease_without;

  perform pg_temp.check_detail('4 lease_without : entry_inspection_done = false', v.entry_inspection_done::text, 'false');
  perform pg_temp.check_detail('5 lease_without : latest_finalized_entry_inspection_id = NULL', v.latest_finalized_entry_inspection_id::text, null);
  perform pg_temp.check_detail('6 lease_without : exit_inspection_done inchangé (false, régression)', v.exit_inspection_done::text, 'false');
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
