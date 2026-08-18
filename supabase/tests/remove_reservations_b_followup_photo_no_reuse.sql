-- ============================================================================
-- TEST — Rattrapage passe B (private.validate_inspection_photo_no_reuse
-- recentrée sur lease_id, 20260805410000).
--
-- 1. Un upload de photo réussit désormais (avant ce correctif : 42703 sur
--    TOUT insert dans inspection_photos, entrée comme sortie).
-- 2. Non-régression sur la logique anti-réutilisation elle-même : une
--    photo déjà utilisée en entrée reste refusée en sortie du même bail.
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module6i_finalize_requires_at_least_one_item.sql
-- (helpers pg_temp, act_as/act_as_owner, BEGIN/ROLLBACK).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/remove_reservations_b_followup_photo_no_reuse.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module6i_finalize_requires_at_least_one_item.sql).
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

create or replace function pg_temp.check_message(p_name text, p_got text, p_expected text)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('message attendu=%L, obtenu=%L', p_expected, p_got));
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

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES — un bail, une inspection d'entrée avec un item, une
--    inspection de sortie avec un item.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id           uuid;
  v_staff_id         uuid := gen_random_uuid();
  v_tenant_id        uuid := gen_random_uuid();
  v_prop_id          uuid;
  v_lease_id         uuid;
  v_inspection_entree uuid;
  v_inspection_sortie uuid;
  v_item_entree      uuid;
  v_item_sortie      uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org Photo No Reuse', 'test-org-photo-no-reuse-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-photo-no-reuse@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  -- Déclenche la création automatique de la ligne tenant_accounts
  -- correspondante (trigger Module 1) — leases.tenant_account_id référence
  -- public.tenant_accounts, pas directement auth.users.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-photo-no-reuse@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien Photo No Reuse', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_id, 'entree', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_entree;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_id, 'sortie', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_sortie;

  insert into public.inspection_items (organization_id, inspection_id, zone, condition)
  values (v_org_id, v_inspection_entree, 'Salon', 'bon')
  returning id into v_item_entree;

  insert into public.inspection_items (organization_id, inspection_id, zone, condition)
  values (v_org_id, v_inspection_sortie, 'Salon', 'bon')
  returning id into v_item_sortie;

  create table pg_temp.fixtures as
  select
    v_staff_id          as staff_id,
    v_item_entree       as item_entree,
    v_item_sortie       as item_sortie;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — UPLOAD RÉUSSIT DÉSORMAIS SUR UNE PHOTO D'ENTRÉE (avant
--    correctif : 42703 sur tout insert, entrée incluse).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.inspection_photos (organization_id, inspection_item_id, storage_path, file_hash)
    select organization_id, f.item_entree, 'test/photo-entree.jpg', 'hash-shared-A'
    from public.inspection_items where id = f.item_entree;
    perform pg_temp.record('1 upload photo entrée -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('1 upload photo entrée -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — UPLOAD RÉUSSIT SUR UNE PHOTO DE SORTIE, EMPREINTE
--    DIFFÉRENTE (pas de réutilisation détectée).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.inspection_photos (organization_id, inspection_item_id, storage_path, file_hash)
    select organization_id, f.item_sortie, 'test/photo-sortie-b.jpg', 'hash-different-B'
    from public.inspection_items where id = f.item_sortie;
    perform pg_temp.record('2 upload photo sortie, empreinte différente -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('2 upload photo sortie, empreinte différente -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — RÉGRESSION : LA MÊME EMPREINTE QU'EN ENTRÉE RESTE
--    REFUSÉE EN SORTIE.
-- ----------------------------------------------------------------------------

do $$
declare
  f         record;
  v_message text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.inspection_photos (organization_id, inspection_item_id, storage_path, file_hash)
    select organization_id, f.item_sortie, 'test/photo-sortie-reuse.jpg', 'hash-shared-A'
    from public.inspection_items where id = f.item_sortie;
    perform pg_temp.record('3 upload photo sortie, empreinte réutilisée de l''entrée -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_message = message_text;
    perform pg_temp.check_message(
      '3 upload photo sortie, empreinte réutilisée de l''entrée -> refusée',
      v_message,
      'Photo refusée : cette empreinte de fichier a déjà été utilisée dans l''état des lieux d''entrée de ce contrat (réutilisation interdite)'
    );
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. RÉSUMÉ.
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
