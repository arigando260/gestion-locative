-- ============================================================================
-- TEST — Module 6e (un nouvel état des lieux d'entrée ne peut être créé, ou
-- un brouillon requalifié en entrée, que si le précédent est CONTESTÉ).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents (module7b/
-- module8/module2c/module9) : transaction begin/rollback, helpers pg_temp,
-- identité simulée via pg_temp.act_as(), résumé PASS/FAIL avant le
-- ROLLBACK final.
--
-- Un bail distinct par scénario (lease_a..lease_f) pour ne jamais faire
-- interférer le "dernier état des lieux d'entrée" d'un scénario avec un
-- autre — même raison que Modules 8/9.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 6e soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module6e_prevent_entree_duplicate_unless_contested.sql
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
-- 1. FIXTURES — org, staff (admin), locataire, 6 biens/baux (un par scénario).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
  v_prop      uuid;
  v_lease_a   uuid;
  v_lease_b   uuid;
  v_lease_c   uuid;
  v_lease_d   uuid;
  v_lease_e   uuid;
  v_lease_f   uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 6e', 'test-org-6e-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-6e@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 6e'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-6e@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 6e'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — A', '1 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_a;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — B', '2 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_b;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — C', '3 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_c;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — D', '4 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_d;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — E', '5 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_e;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6e — F', '6 rue du Test', 500000, 'longue_duree') returning id into v_prop;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
  values (v_org_id, v_prop, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye') returning id into v_lease_f;

  create table pg_temp.fixtures as
  select
    v_org_id    as org_id,
    v_staff_id  as staff_id,
    v_tenant_id as tenant_id,
    v_lease_a   as lease_a,
    v_lease_b   as lease_b,
    v_lease_c   as lease_c,
    v_lease_d   as lease_d,
    v_lease_e   as lease_e,
    v_lease_f   as lease_f;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — bail A : premier état des lieux d'entrée -> autorisé.
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
    values (f.org_id, f.lease_a, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('1 premier état des lieux d''entrée sur un bail -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('1 premier état des lieux d''entrée sur un bail -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — bail B : deuxième entrée alors que la première est
--    en_attente (finalisée, aucune décision locataire) -> refusé.
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
  values (f.org_id, f.lease_b, 'entree', current_date, 'finalise', f.staff_id);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.lease_b, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('2 deuxième entrée alors que la première est en_attente -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 deuxième entrée alors que la première est en_attente -> refusé', v_detail, 'property_inspection.entree.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — bail C : deuxième entrée alors que la première est
--    valide -> refusé.
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
  values (f.org_id, f.lease_c, 'entree', current_date, 'finalise', f.staff_id, 'valide', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.lease_c, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('3 deuxième entrée alors que la première est validée -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 deuxième entrée alors que la première est validée -> refusé', v_detail, 'property_inspection.entree.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — bail D : deuxième entrée alors que la première est
--    tacitement acceptée (finalisée il y a 8 jours, jamais tranchée) ->
--    refusé. finalized_at reculé artificiellement (bypass temporaire des
--    triggers qui le figeraient sinon) uniquement pour fabriquer une
--    donnée de test historique — jamais fait ainsi en usage réel.
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
  values (f.org_id, f.lease_d, 'entree', current_date, 'finalise', f.staff_id)
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
    values (f.org_id, f.lease_d, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('4 deuxième entrée alors que la première est tacitement acceptée -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 deuxième entrée alors que la première est tacitement acceptée -> refusé', v_detail, 'property_inspection.entree.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — bail E : deuxième entrée après contestation de la
--    première -> autorisé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.lease_e, 'entree', current_date, 'finalise', f.staff_id, 'conteste', now());

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.property_inspections
      (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.lease_e, 'entree', current_date, 'finalise', f.staff_id);
    perform pg_temp.record('5 deuxième entrée après contestation de la première -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('5 deuxième entrée après contestation de la première -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIO 6 — bail F : requalification d'un brouillon 'sortie' existant
--    en 'entree' (via UPDATE) alors qu'une entrée validée (non contestée)
--    existe déjà sur ce bail -> refusé. Couvre le chemin UPDATE OF
--    inspection_type, pas seulement INSERT.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_f_start date;
  v_sortie_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  select start_date into v_lease_f_start from public.leases where id = f.lease_f;

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, tenant_validation_status, tenant_validation_at)
  values (f.org_id, f.lease_f, 'entree', current_date, 'finalise', f.staff_id, 'valide', now());

  insert into public.property_inspections
    (organization_id, lease_id, inspection_type, inspection_date, document_status)
  values (f.org_id, f.lease_f, 'sortie', v_lease_f_start, 'brouillon')
  returning id into v_sortie_id;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.property_inspections set inspection_type = 'entree' where id = v_sortie_id;
    perform pg_temp.record('6 requalification d''un brouillon sortie en entree sur bail déjà pourvu (non contesté) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6 requalification d''un brouillon sortie en entree sur bail déjà pourvu (non contesté) -> refusé', v_detail, 'property_inspection.entree.duplicate_not_contested');
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
