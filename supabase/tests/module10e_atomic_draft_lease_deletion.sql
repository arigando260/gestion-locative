-- ============================================================================
-- TEST — Module 10e (suppression atomique d'un bail + son lease_contracts
-- non approuvé, fonction public.delete_lease_with_contract, policy
-- lease_contracts_delete).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents : transaction begin/rollback, helpers pg_temp, identité
-- simulée via pg_temp.act_as(), résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 10e soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10e_atomic_draft_lease_deletion.sql
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
  values (p_org, 'Bien 10e — ' || p_label, p_label || ' rue du Test', 500000, 'longue_duree')
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

create or replace function pg_temp.new_lease_contract(p_org uuid, p_lease uuid, p_label text)
returns uuid language plpgsql as $$
declare
  v_contract uuid;
begin
  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (p_org, p_lease, 'test/contracts/' || p_label || '.pdf')
  returning id into v_contract;
  return v_contract;
end;
$$;

-- Fixture uniquement : fait passer un contrat à "approuvé" sans exiger que
-- les dépôts du bail soient réellement complets (déjà exhaustivement testé
-- au Module 10). Désactive temporairement les deux triggers de la chaîne
-- d'approbation (horodatage + activation du bail), les réactive aussitôt
-- après — même technique que module10c_allow_delete_unapproved_lease_
-- contract.sql. Le bail reste délibérément 'brouillon' (trg_lease_
-- contracts_activate_lease désactivé pendant l'opération) : état
-- artificiel, jamais atteignable en usage réel (une approbation véritable
-- fait toujours basculer le bail à 'actif' dans la même transaction), mais
-- c'est précisément le cas à couvrir ici.
create or replace function pg_temp.force_contract_approved(p_contract uuid)
returns void language plpgsql as $$
begin
  alter table public.lease_contracts disable trigger trg_lease_contracts_fill_approved_at;
  alter table public.lease_contracts disable trigger trg_lease_contracts_activate_lease;
  update public.lease_contracts set approved_at = now() where id = p_contract;
  alter table public.lease_contracts enable trigger trg_lease_contracts_fill_approved_at;
  alter table public.lease_contracts enable trigger trg_lease_contracts_activate_lease;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — une organisation, un staff admin (leases:delete), un staff
-- comptable (SANS leases:delete — scénario 5), un locataire.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id        uuid;
  v_staff_id      uuid := gen_random_uuid();
  v_comptable_id  uuid := gen_random_uuid();
  v_tenant_id     uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10e', 'test-org-10e-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10e@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10e'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_comptable_id, 'comptable-10e@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Comptable Test 10e'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_comptable_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'comptable';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10e@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10e'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select
    v_org_id       as org_id,
    v_staff_id     as staff_id,
    v_comptable_id as comptable_id,
    v_tenant_id    as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — brouillon + contrat NON approuvé -> suppression réussit,
-- les deux lignes disparaissent.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_lease_count int;
  v_contract_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S1');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S1');

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform public.delete_lease_with_contract(v_lease);
    perform pg_temp.record('1a brouillon + contrat non approuvé -> suppression autorisée', 'PASS');
  exception when others then
    perform pg_temp.record('1a brouillon + contrat non approuvé -> suppression autorisée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_lease_count from public.leases where id = v_lease;
  select count(*) into v_contract_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('1b le bail a disparu', v_lease_count::text, '0');
  perform pg_temp.check_detail('1c le contrat a disparu', v_contract_count::text, '0');
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — brouillon + contrat APPROUVÉ -> suppression refusée,
-- bail ET contrat survivent tous les deux (pas de suppression partielle).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_detail text;
  v_lease_count int;
  v_contract_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S2');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S2');
  perform pg_temp.force_contract_approved(v_contract);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform public.delete_lease_with_contract(v_lease);
    perform pg_temp.record('2a brouillon + contrat approuvé -> suppression refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2a brouillon + contrat approuvé -> suppression refusée', v_detail, 'lease_contract.delete.immutable');
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_lease_count from public.leases where id = v_lease;
  select count(*) into v_contract_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('2b le bail existe toujours', v_lease_count::text, '1');
  perform pg_temp.check_detail('2c le contrat existe toujours', v_contract_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — brouillon + dépôt versé (deposit_ledger non vide) ->
-- suppression refusée par trg_leases_prevent_delete_with_deposit_history ;
-- le contrat (non approuvé, qui se serait supprimé seul sans problème)
-- survit lui aussi -> preuve directe de l'atomicité (sans elle, le contrat
-- aurait disparu et le bail serait resté, exactement le trou corrigé ici).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_detail text;
  v_lease_count int;
  v_contract_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S3');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S3');
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values (f.org_id, v_lease, 'avance_garantie', 'depot_initial', 50000);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform public.delete_lease_with_contract(v_lease);
    perform pg_temp.record('3a brouillon + dépôt versé -> suppression refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3a brouillon + dépôt versé -> suppression refusée', v_detail, 'lease.delete.has_deposit_history');
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_lease_count from public.leases where id = v_lease;
  select count(*) into v_contract_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('3b le bail existe toujours', v_lease_count::text, '1');
  perform pg_temp.check_detail('3c le contrat (pourtant supprimable seul) existe toujours -> pas de suppression partielle', v_contract_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — brouillon SANS aucun contrat -> suppression réussit
-- normalement (non-régression du comportement Module 10 d'origine).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_lease_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S4');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    perform public.delete_lease_with_contract(v_lease);
    perform pg_temp.record('4a brouillon sans contrat -> suppression autorisée', 'PASS');
  exception when others then
    perform pg_temp.record('4a brouillon sans contrat -> suppression autorisée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_lease_count from public.leases where id = v_lease;
  perform pg_temp.check_detail('4b le bail a disparu', v_lease_count::text, '0');
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 5 — défense en profondeur : staff SANS leases:delete
-- (comptable) -> policies RLS (leases_delete ET la nouvelle lease_
-- contracts_delete) filtrent silencieusement, aucune exception, mais
-- aucune ligne n'est réellement supprimée non plus.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_lease_count int;
  v_contract_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S5');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S5');

  perform pg_temp.act_as('authenticated', f.comptable_id);
  begin
    perform public.delete_lease_with_contract(v_lease);
    perform pg_temp.record('5a comptable (sans leases:delete) appelle la fonction -> aucune exception (RLS silencieuse)', 'PASS');
  exception when others then
    perform pg_temp.record('5a comptable (sans leases:delete) appelle la fonction -> aucune exception (RLS silencieuse)', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_lease_count from public.leases where id = v_lease;
  select count(*) into v_contract_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('5b le bail existe toujours (RLS leases_delete a filtré)', v_lease_count::text, '1');
  perform pg_temp.check_detail('5c le contrat existe toujours (RLS lease_contracts_delete a filtré)', v_contract_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. RÉSUMÉ.
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
