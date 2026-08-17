-- ============================================================================
-- TEST — Module 10b (un seul bail "en cours" — actif OU brouillon — par
-- bien, index leases_one_pending_or_active_per_property + trigger
-- trg_leases_validate_one_pending_or_active_per_property).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents (module10/module8/module6f/...) : transaction begin/rollback,
-- helpers pg_temp, identité simulée via pg_temp.act_as(), résumé PASS/FAIL
-- avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 10b soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10b_one_pending_or_active_lease_per_property.sql
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

create or replace function pg_temp.new_property(p_org uuid, p_label text)
returns uuid language plpgsql as $$
declare
  v_prop uuid;
begin
  insert into public.properties (organization_id, name, address, price, location_type)
  values (p_org, 'Bien 10b — ' || p_label, p_label || ' rue du Test', 500000, 'longue_duree')
  returning id into v_prop;
  return v_prop;
end;
$$;

create or replace function pg_temp.new_brouillon_lease(p_org uuid, p_tenant uuid, p_property uuid)
returns uuid language plpgsql as $$
declare
  v_lease uuid;
begin
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (p_org, p_property, p_tenant, current_date, 100000, 'mensuel', 100000, 'postpaye')
  returning id into v_lease;
  return v_lease;
end;
$$;

-- Fixture uniquement (même technique que module10_lease_lifecycle.sql) :
-- ne désactive QUE le garde-fou de transition de statut (Module 10), jamais
-- le trigger testé ici (trg_leases_validate_one_pending_or_active_per_property
-- reste actif pendant l'appel — inoffensif pour la ligne elle-même, l.id <>
-- new.id l'exclut d'elle-même).
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
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10b', 'test-org-10b-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10b@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10b'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10b@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10b'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_tenant_id as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — deux brouillons sur le même bien -> le second refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p1 uuid;
  v_detail text;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p1 := pg_temp.new_property(f.org_id, 'S1');

  perform pg_temp.act_as('authenticated', f.staff_id);
  perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p1);
  perform pg_temp.record('1a premier brouillon sur le bien -> autorisé', 'PASS');

  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p1);
    perform pg_temp.record('1b deuxième brouillon sur le même bien -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('1b deuxième brouillon sur le même bien -> refusé', v_detail, 'lease.property.already_has_pending_or_active_lease');
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.leases where property_id = v_p1;
  perform pg_temp.check_detail('1c le bien ne porte toujours qu''un seul bail', v_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — nouveau brouillon refusé sur un bien déjà actif.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p2 uuid;
  v_lease1 uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p2 := pg_temp.new_property(f.org_id, 'S2');
  v_lease1 := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p2);
  perform pg_temp.force_lease_status(v_lease1, 'actif');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p2);
    perform pg_temp.record('2 nouveau brouillon sur un bien déjà actif -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 nouveau brouillon sur un bien déjà actif -> refusé', v_detail, 'lease.property.already_has_pending_or_active_lease');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — 'resilie' ne bloque pas un nouveau brouillon.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p3 uuid;
  v_lease1 uuid;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p3 := pg_temp.new_property(f.org_id, 'S3');
  v_lease1 := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p3);
  perform pg_temp.force_lease_status(v_lease1, 'resilie');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p3);
    perform pg_temp.record('3 nouveau brouillon sur un bien avec bail resilie -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('3 nouveau brouillon sur un bien avec bail resilie -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — 'termine' ne bloque pas un nouveau brouillon.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p4 uuid;
  v_lease1 uuid;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p4 := pg_temp.new_property(f.org_id, 'S4');
  v_lease1 := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p4);
  perform pg_temp.force_lease_status(v_lease1, 'termine');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p4);
    perform pg_temp.record('4 nouveau brouillon sur un bien avec bail termine -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('4 nouveau brouillon sur un bien avec bail termine -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — chemin UPDATE OF property_id : déplacer un brouillon vers
-- un bien déjà pourvu -> refusé.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p5a uuid;
  v_p5b uuid;
  v_lease_mover uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p5a := pg_temp.new_property(f.org_id, 'S5a');
  v_p5b := pg_temp.new_property(f.org_id, 'S5b');
  perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p5b);
  v_lease_mover := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p5a);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.leases set property_id = v_p5b where id = v_lease_mover;
    perform pg_temp.record('5 déplacement property_id vers un bien déjà pourvu -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5 déplacement property_id vers un bien déjà pourvu -> refusé', v_detail, 'lease.property.already_has_pending_or_active_lease');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIO 6 — défense en profondeur, second niveau : trigger désactivé,
-- l'index unique bloque quand même (23505 brut, garantie atomique de
-- dernier recours — voir conception).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p6 uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p6 := pg_temp.new_property(f.org_id, 'S6');
  perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p6);

  alter table public.leases disable trigger trg_leases_validate_one_pending_or_active_per_property;

  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p6);
    perform pg_temp.record('6 trigger désactivé, doublon tenté -> l''index bloque quand même (23505)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = returned_sqlstate;
    perform pg_temp.check_detail('6 trigger désactivé, doublon tenté -> l''index bloque quand même (23505)', v_detail, '23505');
  end;

  alter table public.leases enable trigger trg_leases_validate_one_pending_or_active_per_property;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. SCÉNARIO 7 — défense en profondeur, service_role (bypasse RLS) :
-- le trigger tient toujours, indépendamment de toute policy.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p7 uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p7 := pg_temp.new_property(f.org_id, 'S7');
  perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p7);

  perform pg_temp.act_as('service_role', null);
  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p7);
    perform pg_temp.record('7 service_role tente un doublon -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('7 service_role tente un doublon -> refusé malgré bypass RLS', v_detail, 'lease.property.already_has_pending_or_active_lease');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. SCÉNARIO 8 — deux biens distincts, chacun son brouillon -> aucune
-- interférence croisée.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_p8a uuid;
  v_p8b uuid;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_p8a := pg_temp.new_property(f.org_id, 'S8a');
  v_p8b := pg_temp.new_property(f.org_id, 'S8b');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p8a);
    perform pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_p8b);
    perform pg_temp.record('8 deux biens distincts, chacun son brouillon -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('8 deux biens distincts, chacun son brouillon -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 10. RÉSUMÉ.
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
