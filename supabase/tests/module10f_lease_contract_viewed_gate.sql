-- ============================================================================
-- TEST — Module 10f (garde-fou "contrat consulté avant approbation").
--
-- 6 scénarios sur un même bail : dépôts complétés à l'avance pour isoler
-- le nouveau check (first_viewed_at) des vérifications déjà existantes
-- (dépôts, statut brouillon).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module10_lease_lifecycle.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10f_lease_contract_viewed_gate.sql
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
-- 1. FIXTURES — un bail brouillon, dépôts complets (avance de garantie
--    seule : utility_deposit_amount laissé NULL pour ne pas avoir à
--    compléter une deuxième caution), un contrat généré (approved_at et
--    first_viewed_at tous deux NULL au départ).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id      uuid;
  v_staff_id    uuid := gen_random_uuid();
  v_tenant_id   uuid := gen_random_uuid();
  v_prop_id     uuid;
  v_lease_id    uuid;
  v_contract_id uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10f', 'test-org-10f-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10f@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10f'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10f@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10f'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10f', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (v_org_id, v_lease_id, 'avance_garantie', 'depot_initial', 200000);

  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (v_org_id, v_lease_id, v_org_id || '/lease-10f.pdf')
  returning id into v_contract_id;

  create table pg_temp.fixtures as
  select
    v_org_id      as org_id,
    v_staff_id    as staff_id,
    v_tenant_id   as tenant_id,
    v_lease_id    as lease_id,
    v_contract_id as contract_id;

  create table pg_temp.state (first_viewed_1 timestamptz);
  insert into pg_temp.state (first_viewed_1) values (null);
end;
$$;

grant select, insert, update on pg_temp.fixtures to authenticated, service_role;
grant select, update on pg_temp.state to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — LE STAFF TENTE DE POSER first_viewed_at -> BLOQUÉ PAR RLS
--    (0 ligne affectée, aucune policy UPDATE pour le staff sur
--    lease_contracts).
-- ----------------------------------------------------------------------------

do $$
declare
  f      record;
  v_rows int;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  update public.lease_contracts set first_viewed_at = now()
  where id = f.contract_id and first_viewed_at is null;
  get diagnostics v_rows = row_count;

  perform pg_temp.check_count('1 staff tente de poser first_viewed_at -> 0 ligne (RLS)', v_rows, 0);

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — APPROBATION TENTÉE AVEC first_viewed_at NULL -> REFUSÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    update public.lease_contracts set approved_at = now() where id = f.contract_id;
    perform pg_temp.record('2 approbation avec first_viewed_at NULL -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 approbation avec first_viewed_at NULL -> refusée', v_detail, 'lease_contract.approve.not_viewed');
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — LE LOCATAIRE POSE first_viewed_at -> 1 LIGNE, VALEUR
--    CAPTURÉE POUR LE TEST D'IDEMPOTENCE (SCÉNARIO 4).
-- ----------------------------------------------------------------------------

do $$
declare
  f              record;
  v_rows         int;
  v_first_viewed timestamptz;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  update public.lease_contracts set first_viewed_at = now()
  where id = f.contract_id and first_viewed_at is null;
  get diagnostics v_rows = row_count;
  perform pg_temp.check_count('3 locataire pose first_viewed_at -> 1 ligne', v_rows, 1);

  select first_viewed_at into v_first_viewed from public.lease_contracts where id = f.contract_id;
  update pg_temp.state set first_viewed_1 = v_first_viewed;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — RECONSULTATION (IDEMPOTENCE) : 0 LIGNE AFFECTÉE, VALEUR
--    INCHANGÉE.
-- ----------------------------------------------------------------------------

do $$
declare
  f              record;
  v_rows         int;
  v_first_viewed timestamptz;
  v_captured     timestamptz;
begin
  select * into f from pg_temp.fixtures;
  select first_viewed_1 into v_captured from pg_temp.state;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  update public.lease_contracts set first_viewed_at = now()
  where id = f.contract_id and first_viewed_at is null;
  get diagnostics v_rows = row_count;
  perform pg_temp.check_count('4 locataire reconsulte -> 0 ligne affectée (idempotence)', v_rows, 0);

  select first_viewed_at into v_first_viewed from public.lease_contracts where id = f.contract_id;
  perform pg_temp.check_detail('4b valeur de first_viewed_at inchangée après reconsultation',
    v_first_viewed::text, v_captured::text);

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — APPROBATION RETENTÉE : ACCEPTÉE (first_viewed_at posé +
--    dépôts complets).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    update public.lease_contracts set approved_at = now() where id = f.contract_id;
    perform pg_temp.record('5 approbation retentée (first_viewed_at posé) -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('5 approbation retentée (first_viewed_at posé) -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIO 6 — RÉGRESSION : leases.status EST BIEN PASSÉ À 'actif'.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_status text;
begin
  select * into f from pg_temp.fixtures;

  select status into v_status from public.leases where id = f.lease_id;
  perform pg_temp.check_detail('6 leases.status = actif après approbation', v_status, 'actif');
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. RÉSUMÉ.
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
