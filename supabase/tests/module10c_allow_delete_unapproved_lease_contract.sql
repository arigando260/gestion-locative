-- ============================================================================
-- TEST — Module 10c (suppression autorisée d'un lease_contracts non
-- approuvé, toujours refusée une fois approuvé — private.prevent_lease_
-- contract_delete).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents : transaction begin/rollback, helpers pg_temp, identité
-- simulée via pg_temp.act_as(), résumé PASS/FAIL avant le ROLLBACK final.
--
-- Note structurelle : lease_contracts n'a AUCUNE policy RLS DELETE (voir
-- Module 10 — "Pas de policy DELETE : voir trg_lease_contracts_prevent_
-- delete"), donc un rôle 'authenticated' ordinaire ne peut de toute façon
-- jamais supprimer une ligne ici (0 ligne affectée, RLS filtre avant même
-- que le trigger s'exécute) — les scénarios ci-dessous s'exécutent donc en
-- tant que owner/service_role, seuls rôles capables d'atteindre le trigger,
-- exactement comme demandé (défense en profondeur vérifiée sous
-- service_role pour les deux cas).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 10c soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10c_allow_delete_unapproved_lease_contract.sql
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
  values (p_org, 'Bien 10c — ' || p_label, p_label || ' rue du Test', 500000, 'longue_duree')
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
-- au Module 10 — pas l'objet de ce script). Désactive temporairement les
-- deux triggers de la chaîne d'approbation (horodatage + activation), les
-- réactive aussitôt après.
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
-- 1. FIXTURES — une organisation, un locataire (aucun geste staff/tenant
-- n'est testé ici, RLS étant hors-jeu pour DELETE sur cette table — voir
-- note en tête de fichier).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_tenant_id uuid := gen_random_uuid();
begin
  insert into public.organizations (name, slug)
  values ('Test Org 10c', 'test-org-10c-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10c@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10c'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_tenant_id as tenant_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — contrat NON approuvé -> suppression autorisée (owner).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S1');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S1');

  begin
    delete from public.lease_contracts where id = v_contract;
    perform pg_temp.record('1a contrat non approuvé -> suppression autorisée', 'PASS');
  exception when others then
    perform pg_temp.record('1a contrat non approuvé -> suppression autorisée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select count(*) into v_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('1b la ligne a bien disparu', v_count::text, '0');

  -- Effet recherché : le bail brouillon redevient supprimable maintenant que
  -- son contrat n'existe plus (lease_contracts_lease_org_fk ne bloque plus).
  begin
    delete from public.leases where id = v_lease;
    perform pg_temp.record('1c bail brouillon désormais supprimable (contrat retiré)', 'PASS');
  exception when others then
    perform pg_temp.record('1c bail brouillon désormais supprimable (contrat retiré)', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — contrat APPROUVÉ -> suppression toujours refusée
-- (non-régression, owner).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_detail text;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S2');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S2');
  perform pg_temp.force_contract_approved(v_contract);

  begin
    delete from public.lease_contracts where id = v_contract;
    perform pg_temp.record('2a contrat approuvé -> suppression refusée (non-régression)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2a contrat approuvé -> suppression refusée (non-régression)', v_detail, 'lease_contract.delete.immutable');
  end;

  select count(*) into v_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('2b la ligne existe toujours', v_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — défense en profondeur, service_role : contrat NON
-- approuvé -> suppression toujours autorisée (le comportement n'est pas
-- "accidentellement" lié à owner).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S3');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S3');

  perform pg_temp.act_as('service_role', null);
  begin
    delete from public.lease_contracts where id = v_contract;
    perform pg_temp.record('3 service_role, contrat non approuvé -> suppression autorisée', 'PASS');
  exception when others then
    perform pg_temp.record('3 service_role, contrat non approuvé -> suppression autorisée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('3b la ligne a bien disparu', v_count::text, '0');
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — défense en profondeur, service_role : contrat APPROUVÉ
-- -> suppression toujours refusée, même en bypassant RLS.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_prop uuid;
  v_lease uuid;
  v_contract uuid;
  v_detail text;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as_owner();
  v_prop := pg_temp.new_property(f.org_id, 'S4');
  v_lease := pg_temp.new_brouillon_lease(f.org_id, f.tenant_id, v_prop);
  v_contract := pg_temp.new_lease_contract(f.org_id, v_lease, 'S4');
  perform pg_temp.force_contract_approved(v_contract);

  perform pg_temp.act_as('service_role', null);
  begin
    delete from public.lease_contracts where id = v_contract;
    perform pg_temp.record('4 service_role, contrat approuvé -> suppression refusée malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 service_role, contrat approuvé -> suppression refusée malgré bypass RLS', v_detail, 'lease_contract.delete.immutable');
  end;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.lease_contracts where id = v_contract;
  perform pg_temp.check_detail('4b la ligne existe toujours', v_count::text, '1');
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. RÉSUMÉ.
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
