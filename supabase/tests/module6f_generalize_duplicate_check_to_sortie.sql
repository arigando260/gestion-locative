-- ============================================================================
-- TEST — Module 6f (généralisation du contrôle anti-doublon Module 6e à
-- 'sortie', comparaison strictement intra-type).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents (module6e/module5c/module8/module2c/module9) : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Reprend EXACTEMENT les 6 scénarios déjà couverts par module6e_prevent_
-- entree_duplicate_unless_contested.sql pour 'entree' (non-régression après
-- généralisation) et ajoute les 6 mêmes scénarios pour 'sortie' (12 au
-- total) :
--   1. Premier état des lieux du type -> autorisé.
--   2. Deuxième alors que le premier est en_attente -> refusé.
--   3. Deuxième alors que le premier est valide -> refusé.
--   4. Deuxième alors que le premier est accepte_tacitement (finalized_at
--      reculé de 8 jours) -> refusé.
--   5. Deuxième après contestation du premier (conteste) -> autorisé.
--   6. UPDATE : requalification d'un brouillon de L'AUTRE type existant
--      vers CE type, sur un bail qui a déjà un état des lieux de ce type
--      non contesté -> refusé.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 6f soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module6f_generalize_duplicate_check_to_sortie.sql
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
-- 1. FIXTURES — org, staff (admin), locataire, 12 biens/baux (un par
-- scénario : e1..e6 pour 'entree', s1..s6 pour 'sortie').
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
  v_prop      uuid;
  v_e1 uuid; v_e2 uuid; v_e3 uuid; v_e4 uuid; v_e5 uuid; v_e6 uuid;
  v_s1 uuid; v_s2 uuid; v_s3 uuid; v_s4 uuid; v_s5 uuid; v_s6 uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 6f', 'test-org-6f-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-6f@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 6f'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-6f@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 6f'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E1', '1 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e1;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E2', '2 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e2;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E3', '3 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e3;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E4', '4 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e4;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E5', '5 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e5;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — E6', '6 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_e6;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S1', '7 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s1;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S2', '8 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s2;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S3', '9 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s3;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S4', '10 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s4;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S5', '11 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s5;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6f — S6', '12 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_s6;

  create table pg_temp.fixtures as
  select
    v_org_id    as org_id,
    v_staff_id  as staff_id,
    v_tenant_id as tenant_id,
    v_e1 as e1, v_e2 as e2, v_e3 as e3, v_e4 as e4, v_e5 as e5, v_e6 as e6,
    v_s1 as s1, v_s2 as s2, v_s3 as s3, v_s4 as s4, v_s5 as s5, v_s6 as s6;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ============================================================================
-- ENTRÉE — non-régression des 6 scénarios déjà prouvés par Module 6e.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- E1 — premier état des lieux d'entrée sur un bail -> autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.e1, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('E1 premier état des lieux d''entrée -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('E1 premier état des lieux d''entrée -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- E2 — deuxième entrée alors que la première est en_attente -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, f.e2, 'entree', current_date, 'finalise', f.staff_id);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.e2, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('E2 deuxième entrée (première en_attente) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('E2 deuxième entrée (première en_attente) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- E3 — deuxième entrée alors que la première est validée -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.e3, 'entree', current_date, 'finalise', f.staff_id, 'valide', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.e3, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('E3 deuxième entrée (première validée) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('E3 deuxième entrée (première validée) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- E4 — deuxième entrée alors que la première est tacitement acceptée ->
-- refusé. finalized_at reculé artificiellement (bypass temporaire des
-- triggers qui le figeraient sinon) uniquement pour fabriquer une donnée de
-- test historique — jamais fait ainsi en usage réel.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, f.e4, 'entree', current_date, 'finalise', f.staff_id)
  returning id into v_id;

  alter table public.property_inspections disable trigger trg_property_inspections_set_finalized_at;
  alter table public.property_inspections disable trigger trg_property_inspections_prevent_finalized_change;
  update public.property_inspections set finalized_at = now() - interval '8 days' where id = v_id;
  alter table public.property_inspections enable trigger trg_property_inspections_set_finalized_at;
  alter table public.property_inspections enable trigger trg_property_inspections_prevent_finalized_change;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.e4, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('E4 deuxième entrée (première tacitement acceptée) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('E4 deuxième entrée (première tacitement acceptée) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- E5 — deuxième entrée après contestation de la première -> autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.e5, 'entree', current_date, 'finalise', f.staff_id, 'conteste', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.e5, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('E5 deuxième entrée après contestation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('E5 deuxième entrée après contestation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- E6 — requalification d'un brouillon SORTIE existant en ENTREE, sur un
-- bail qui a déjà une entrée non contestée -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_start date;
  v_draft_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select start_date into v_lease_start from public.leases where id = f.e6;

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.e6, 'entree', current_date, 'finalise', f.staff_id, 'valide', now());

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status)
  values (f.org_id, f.e6, 'sortie', v_lease_start, 'brouillon')
  returning id into v_draft_id;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.property_inspections set inspection_type = 'entree' where id = v_draft_id;
    perform pg_temp.record('E6 requalification brouillon sortie -> entree (déjà pourvu) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('E6 requalification brouillon sortie -> entree (déjà pourvu) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ============================================================================
-- SORTIE — mêmes 6 scénarios, nouveaux avec Module 6f.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- S1 — premier état des lieux de sortie sur un bail -> autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.s1, 'sortie', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('S1 premier état des lieux de sortie -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('S1 premier état des lieux de sortie -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- S2 — deuxième sortie alors que la première est en_attente -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, f.s2, 'sortie', current_date, 'finalise', f.staff_id);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.s2, 'sortie', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('S2 deuxième sortie (première en_attente) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('S2 deuxième sortie (première en_attente) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- S3 — deuxième sortie alors que la première est validée -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.s3, 'sortie', current_date, 'finalise', f.staff_id, 'valide', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.s3, 'sortie', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('S3 deuxième sortie (première validée) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('S3 deuxième sortie (première validée) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- S4 — deuxième sortie alors que la première est tacitement acceptée ->
-- refusé (même technique de backdatage que E4).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (f.org_id, f.s4, 'sortie', current_date, 'finalise', f.staff_id)
  returning id into v_id;

  alter table public.property_inspections disable trigger trg_property_inspections_set_finalized_at;
  alter table public.property_inspections disable trigger trg_property_inspections_prevent_finalized_change;
  update public.property_inspections set finalized_at = now() - interval '8 days' where id = v_id;
  alter table public.property_inspections enable trigger trg_property_inspections_set_finalized_at;
  alter table public.property_inspections enable trigger trg_property_inspections_prevent_finalized_change;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.s4, 'sortie', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('S4 deuxième sortie (première tacitement acceptée) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('S4 deuxième sortie (première tacitement acceptée) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- S5 — deuxième sortie après contestation de la première -> autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.s5, 'sortie', current_date, 'finalise', f.staff_id, 'conteste', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.s5, 'sortie', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('S5 deuxième sortie après contestation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('S5 deuxième sortie après contestation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- S6 — requalification d'un brouillon ENTREE existant en SORTIE, sur un
-- bail qui a déjà une sortie non contestée -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_start date;
  v_draft_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select start_date into v_lease_start from public.leases where id = f.s6;

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.s6, 'sortie', current_date, 'finalise', f.staff_id, 'valide', now());

  -- Brouillon 'entree' : soumis à la contrainte de date d'entrée
  -- (inspection_date <= start_date) tant qu'il est de type 'entree' — sans
  -- effet une fois requalifié en 'sortie' juste après.
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status)
  values (f.org_id, f.s6, 'entree', v_lease_start, 'brouillon')
  returning id into v_draft_id;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.property_inspections set inspection_type = 'sortie' where id = v_draft_id;
    perform pg_temp.record('S6 requalification brouillon entree -> sortie (déjà pourvu) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('S6 requalification brouillon entree -> sortie (déjà pourvu) -> refusé', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. RÉSUMÉ.
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
