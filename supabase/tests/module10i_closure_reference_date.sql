-- ============================================================================
-- TEST — Module 10i (leases_closure_status.closure_reference_date).
--
-- 1. Bail resilie AVEC demande validee -> closure_reference_date =
--    responded_at::date de cette demande.
-- 2. Bail resilie SANS demande validee (orphelin simulé) ->
--    closure_reference_date = NULL.
-- 3. Bail actif en clôture (end_date renseignée) -> closure_reference_date
--    = end_date.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les tests précédents (BEGIN/
-- ROLLBACK, helpers pg_temp).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10i_closure_reference_date.sql
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

create or replace function pg_temp.check_date(p_name text, p_got date, p_expected date)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('attendu=%L, obtenu=%L', p_expected, p_got));
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

-- Même helper que supabase/tests/module10_lease_lifecycle.sql : désactive
-- temporairement le trigger de garde pour amener un bail brouillon à
-- 'actif' sans repasser par tout le parcours d'approbation de contrat
-- (déjà prouvé ailleurs) — fixture uniquement, jamais un chemin testé ici.
create or replace function pg_temp.force_lease_status(p_lease uuid, p_status text)
returns void language plpgsql as $$
begin
  alter table public.leases disable trigger trg_leases_validate_status_transition;
  update public.leases set status = p_status where id = p_lease;
  alter table public.leases enable trigger trg_leases_validate_status_transition;
end;
$$;

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
--
-- Le passage actif->resilie hors cascade est refusé par
-- private.validate_lease_status_transition() (Module 10) : les baux 1 et 2
-- sont donc amenés à 'resilie' via le vrai parcours (demande validee), qui
-- pose lui-même responded_at. Le cas "orphelin" (bail 2) est ensuite
-- simulé en supprimant la ligne lease_termination_requests après coup, en
-- superuser (act_as_owner) — exactement le scénario du diagnostic
-- précédent (connexion qui bypasse RLS, aucune policy DELETE dessus).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id           uuid;
  v_staff_id         uuid := gen_random_uuid();
  v_tenant_id        uuid := gen_random_uuid();
  v_prop_resilie     uuid;
  v_prop_orphan      uuid;
  v_prop_actif       uuid;
  v_lease_resilie    uuid;
  v_lease_orphan     uuid;
  v_lease_actif      uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10i', 'test-org-10i-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10i@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10i'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10i@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10i'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- Un bien ne peut avoir qu'un seul bail actif/brouillon à la fois
  -- (private.validate_one_pending_or_active_lease_per_property, Module
  -- 10b) : un bien distinct par bail de ce test.
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10i Resilie', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_resilie;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10i Orphan', '2 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_orphan;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10i Actif', '3 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_actif;

  -- Bail 1 : sera résilié avec une demande validee conservée.
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_resilie, v_tenant_id, current_date - 200, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_resilie;

  -- Bail 2 : sera résilié puis sa demande validee supprimée (orphelin simulé).
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_orphan, v_tenant_id, current_date - 200, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_orphan;

  -- Bail 3 : actif, en clôture Volet B (end_date renseignée).
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date, end_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_actif, v_tenant_id, current_date - 200, current_date + 10, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_actif;

  perform pg_temp.force_lease_status(v_lease_resilie, 'actif');
  perform pg_temp.force_lease_status(v_lease_orphan, 'actif');
  perform pg_temp.force_lease_status(v_lease_actif, 'actif');

  create table pg_temp.fixtures as
  select
    v_staff_id        as staff_id,
    v_tenant_id       as tenant_id,
    v_lease_resilie   as lease_resilie,
    v_lease_orphan    as lease_orphan,
    v_lease_actif     as lease_actif;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- Résiliation des baux 1 et 2 via le vrai parcours (demande + validation),
-- en tant que locataire (initiateur) puis staff (répondant).
do $$
declare
  f          record;
  v_ltr_id   uuid;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests (organization_id, lease_id, initiated_by_tenant_id, requested_end_date, reason)
  select organization_id, f.lease_resilie, f.tenant_id, current_date + 30, 'Test 10i'
  from public.leases where id = f.lease_resilie
  returning id into v_ltr_id;
  perform pg_temp.act_as_owner();

  perform pg_temp.act_as('authenticated', f.staff_id);
  update public.lease_termination_requests set status = 'validee' where id = v_ltr_id;
  perform pg_temp.act_as_owner();
end;
$$;

do $$
declare
  f          record;
  v_ltr_id   uuid;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests (organization_id, lease_id, initiated_by_tenant_id, requested_end_date, reason)
  select organization_id, f.lease_orphan, f.tenant_id, current_date + 30, 'Test 10i orphelin'
  from public.leases where id = f.lease_orphan
  returning id into v_ltr_id;
  perform pg_temp.act_as_owner();

  perform pg_temp.act_as('authenticated', f.staff_id);
  update public.lease_termination_requests set status = 'validee' where id = v_ltr_id;
  perform pg_temp.act_as_owner();

  -- Simule l'orphelin : suppression directe, en superuser (bypass RLS —
  -- aucune policy DELETE n'existe sur cette table, voir diagnostic).
  delete from public.lease_termination_requests where id = v_ltr_id;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIOS.
-- ----------------------------------------------------------------------------

do $$
declare
  f    record;
  v_lt public.leases_closure_status%rowtype;
begin
  select * into f from pg_temp.fixtures;

  select * into v_lt from public.leases_closure_status where lease_id = f.lease_resilie;
  perform pg_temp.check_date(
    '1 resilie avec demande validee -> responded_at::date',
    v_lt.closure_reference_date,
    (select responded_at::date from public.lease_termination_requests where lease_id = f.lease_resilie and status = 'validee')
  );

  select * into v_lt from public.leases_closure_status where lease_id = f.lease_orphan;
  perform pg_temp.check_date('2 resilie orphelin -> NULL', v_lt.closure_reference_date, null);

  select * into v_lt from public.leases_closure_status where lease_id = f.lease_actif;
  perform pg_temp.check_date(
    '3 actif en clôture -> end_date',
    v_lt.closure_reference_date,
    (select end_date from public.leases where id = f.lease_actif)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. RÉSUMÉ.
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
