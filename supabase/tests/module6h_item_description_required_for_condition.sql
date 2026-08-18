-- ============================================================================
-- TEST — Module 6h (description obligatoire pour un élément dégradé/hors
-- service).
--
-- 7 scénarios : 'bon'/'usage_normal' restent facultatifs (régression),
-- 'degrade' et 'hors_service' refusés sans description (NULL puis
-- espaces seuls), acceptés une fois renseignés, et régression sur
-- UPDATE (un item 'bon' existant ne peut pas passer à 'degrade' sans
-- ajouter de description).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module6g_finalize_requires_observations.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module6h_item_description_required_for_condition.sql
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
-- 1. FIXTURES — un état des lieux brouillon (RLS bypassée, superuser :
--    cette table n'a pas de trigger dépendant de la session comme
--    prevent_tenant_finalizing_inspection sur property_inspections, donc
--    pas besoin de bascule de rôle ici, contrairement à Module 6g).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_prop_id      uuid;
  v_lease_id     uuid;
  v_inspection_id uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 6h', 'test-org-6h-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-6h@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 6h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-6h@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 6h'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6h', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_id, 'entree', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_id;

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_inspection_id as inspection_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — 'bon' SANS DESCRIPTION -> ACCEPTÉ (régression).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition)
    values (f.org_id, f.inspection_id, 'Salon', 'bon');
    perform pg_temp.record('1 bon sans description -> accepté', 'PASS');
  exception when others then
    perform pg_temp.record('1 bon sans description -> accepté', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — 'usage_normal' SANS DESCRIPTION -> ACCEPTÉ (régression).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition)
    values (f.org_id, f.inspection_id, 'Cuisine', 'usage_normal');
    perform pg_temp.record('2 usage_normal sans description -> accepté', 'PASS');
  exception when others then
    perform pg_temp.record('2 usage_normal sans description -> accepté', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — 'degrade' SANS DESCRIPTION (NULL) -> REFUSÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition)
    values (f.org_id, f.inspection_id, 'Chambre', 'degrade');
    perform pg_temp.record('3 degrade sans description (NULL) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 degrade sans description (NULL) -> refusé', v_detail, 'inspection_item.description.required_for_condition');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — 'degrade' AVEC DESCRIPTION ESPACES SEULS -> REFUSÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition, description)
    values (f.org_id, f.inspection_id, 'Chambre', 'degrade', '   ');
    perform pg_temp.record('4 degrade avec description espaces seuls -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 degrade avec description espaces seuls -> refusé', v_detail, 'inspection_item.description.required_for_condition');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — 'hors_service' SANS DESCRIPTION -> REFUSÉ (confirme que
--    les deux valeurs de condition déclenchent le check, pas seulement
--    'degrade').
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition)
    values (f.org_id, f.inspection_id, 'Salle de bain', 'hors_service');
    perform pg_temp.record('5 hors_service sans description -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5 hors_service sans description -> refusé', v_detail, 'inspection_item.description.required_for_condition');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIO 6 — 'degrade' AVEC DESCRIPTION RENSEIGNÉE -> ACCEPTÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  begin
    insert into public.inspection_items (organization_id, inspection_id, zone, condition, description)
    values (f.org_id, f.inspection_id, 'Chambre', 'degrade', 'Trou dans le mur');
    perform pg_temp.record('6 degrade avec description renseignée -> accepté', 'PASS');
  exception when others then
    perform pg_temp.record('6 degrade avec description renseignée -> accepté', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. SCÉNARIO 7 — RÉGRESSION UPDATE : un item 'bon' existant ne peut pas
--    passer à 'degrade' sans ajouter de description dans la même
--    transition.
-- ----------------------------------------------------------------------------

do $$
declare
  f          record;
  v_item_id  uuid;
  v_detail   text;
begin
  select * into f from pg_temp.fixtures;

  insert into public.inspection_items (organization_id, inspection_id, zone, condition)
  values (f.org_id, f.inspection_id, 'Couloir', 'bon')
  returning id into v_item_id;

  begin
    update public.inspection_items set condition = 'degrade' where id = v_item_id;
    perform pg_temp.record('7 UPDATE bon -> degrade sans description -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7 UPDATE bon -> degrade sans description -> refusé', v_detail, 'inspection_item.description.required_for_condition');
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
