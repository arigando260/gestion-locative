-- ============================================================================
-- TEST — Module 10d (colonnes special_terms sur organizations et leases,
-- aucune logique métier — vérifie seulement l'existence, la nullabilité et
-- l'écriture sous RLS existante).
--
-- Script SQL autonome — PAS une migration. Même patron que les scripts
-- précédents, volontairement réduit ici (rien à couvrir au-delà de
-- l'existence des colonnes) : transaction begin/rollback, helpers pg_temp,
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 10d soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module10d_lease_special_terms.sql
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
-- 1. FIXTURES — une organisation (avec special_terms renseigné dès la
-- création), un staff (admin), un locataire, un bien, un bail brouillon
-- (special_terms non renseigné à la création).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
  v_prop_id   uuid;
  v_lease_id  uuid;
begin
  insert into public.organizations (name, slug, special_terms)
  values ('Test Org 10d', 'test-org-10d-' || substr(gen_random_uuid()::text, 1, 8), 'Règlement intérieur par défaut.')
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-10d@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 10d'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-10d@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 10d'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 10d', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 100000, 'postpaye')
  returning id into v_lease_id;

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_tenant_id as tenant_id, v_lease_id as lease_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — organizations.special_terms renseigné à la création,
-- leases.special_terms NULL par défaut (aucun override).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_org_terms text;
  v_lease_terms text;
begin
  select * into f from pg_temp.fixtures;

  select special_terms into v_org_terms from public.organizations where id = f.org_id;
  perform pg_temp.check_detail('1a organizations.special_terms renseigné à la création', v_org_terms, 'Règlement intérieur par défaut.');

  select special_terms into v_lease_terms from public.leases where id = f.lease_id;
  perform pg_temp.check_detail('1b leases.special_terms NULL par défaut (aucun override)', v_lease_terms, null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — écriture staff sous RLS existante (organizations_update /
-- leases_update, Module 1/3, non modifiées par cette migration).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_terms text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.staff_id);

  update public.organizations set special_terms = 'Règlement mis à jour par le staff.' where id = f.org_id;
  select special_terms into v_terms from public.organizations where id = f.org_id;
  perform pg_temp.check_detail('2a staff modifie organizations.special_terms -> autorisé', v_terms, 'Règlement mis à jour par le staff.');

  update public.leases set special_terms = 'Clause spécifique à ce bail.' where id = f.lease_id;
  select special_terms into v_terms from public.leases where id = f.lease_id;
  perform pg_temp.check_detail('2b staff renseigne un override sur ce bail -> autorisé', v_terms, 'Clause spécifique à ce bail.');

  -- Override effacé -> retour à l'héritage implicite (résolu côté
  -- application, pas ici) : simple retour à NULL, aucune règle en base.
  update public.leases set special_terms = null where id = f.lease_id;
  select special_terms into v_terms from public.leases where id = f.lease_id;
  perform pg_temp.check_detail('2c override effacé -> NULL de nouveau', v_terms, null);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. RÉSUMÉ.
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
