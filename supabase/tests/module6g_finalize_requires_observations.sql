-- ============================================================================
-- TEST — Module 6g (observations obligatoires à la finalisation).
--
-- 4 scénarios sur deux fixtures : finalisation refusée sans observations,
-- refusée avec observations vide/espaces, acceptée une fois renseignées,
-- et non-régression sur l'exigence conducted_by déjà existante (Module 6,
-- CHECK constraint, inchangée par ce trigger).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que
-- supabase/tests/module10f_lease_contract_viewed_gate.sql.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que cette migration soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module6g_finalize_requires_observations.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module10f_lease_contract_viewed_gate.sql).
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

-- Bascule la session sur le rôle Postgres p_pg_role, avec request.jwt.claims
-- simulant l'utilisateur p_user_id — nécessaire ici : finaliser un état des
-- lieux passe par private.prevent_tenant_finalizing_inspection (Module 6),
-- qui revérifie has_permission('property_inspections', 'update') sur la
-- session courante. Un superuser sans session (act_as_owner) échoue cette
-- vérification comme n'importe quelle session sans rôle — il faut une
-- vraie session staff pour dépasser ce garde-fou et atteindre le trigger
-- réellement testé ici (Module 6g).
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
-- 1. FIXTURES — un bail brouillon (peu importe son statut, seule la FK
--    composite organization_id/lease_id compte ici), deux états des lieux
--    brouillon : l'un avec conducted_by et sans observations (scénarios
--    1-3), l'autre sans conducted_by mais avec observations (scénario 4,
--    régression).
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id           uuid;
  v_staff_id         uuid := gen_random_uuid();
  v_tenant_id        uuid := gen_random_uuid();
  v_prop_id          uuid;
  v_lease_id         uuid;
  v_inspection_main  uuid;
  v_inspection_noconductor uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 6g', 'test-org-6g-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-6g@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 6g'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-6g@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 6g'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 6g', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_prop_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_id;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
  values (v_org_id, v_lease_id, 'entree', current_date, 'brouillon', v_staff_id)
  returning id into v_inspection_main;

  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, observations)
  values (v_org_id, v_lease_id, 'sortie', current_date, 'brouillon', 'Observations déjà renseignées')
  returning id into v_inspection_noconductor;

  create table pg_temp.fixtures as
  select
    v_staff_id               as staff_id,
    v_inspection_main        as inspection_main,
    v_inspection_noconductor as inspection_noconductor;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — FINALISATION REFUSÉE SANS OBSERVATIONS (NULL).
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections set document_status = 'finalise' where id = f.inspection_main;
    perform pg_temp.record('1 finalisation sans observations (NULL) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('1 finalisation sans observations (NULL) -> refusée', v_detail, 'property_inspection.finalize.observations_required');
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — FINALISATION REFUSÉE AVEC OBSERVATIONS VIDE/ESPACES.
-- ----------------------------------------------------------------------------

do $$
declare
  f        record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections
    set observations = '   ', document_status = 'finalise'
    where id = f.inspection_main;
    perform pg_temp.record('2 finalisation avec observations espaces seuls -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2 finalisation avec observations espaces seuls -> refusée', v_detail, 'property_inspection.finalize.observations_required');
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — FINALISATION ACCEPTÉE AVEC OBSERVATIONS RENSEIGNÉES.
-- ----------------------------------------------------------------------------

do $$
declare
  f          record;
  v_status   text;
  v_finalized_at timestamptz;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections
    set observations = 'RAS, rien à signaler', document_status = 'finalise'
    where id = f.inspection_main;
    perform pg_temp.record('3 finalisation avec observations renseignées -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('3 finalisation avec observations renseignées -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as_owner();

  select document_status, finalized_at into v_status, v_finalized_at
  from public.property_inspections where id = f.inspection_main;
  perform pg_temp.check_detail('3b document_status = finalise après succès', v_status, 'finalise');
  perform pg_temp.record(
    '3c finalized_at posé automatiquement',
    case when v_finalized_at is not null then 'PASS' else 'FAIL' end,
    case when v_finalized_at is null then 'finalized_at est resté NULL' else null end
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIO 4 — RÉGRESSION : conducted_by TOUJOURS REQUIS, INCHANGÉ
--    (CHECK constraint property_inspections_finalized_requires_conductor,
--    Module 6, observations déjà renseignées sur cette ligne n'y change rien).
-- ----------------------------------------------------------------------------

do $$
declare
  f            record;
  v_sqlstate   text;
  v_constraint text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    update public.property_inspections set document_status = 'finalise' where id = f.inspection_noconductor;
    perform pg_temp.record('4 finalisation sans conducted_by (observations OK) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate, v_constraint = constraint_name;
    if v_sqlstate = '23514' and v_constraint = 'property_inspections_finalized_requires_conductor' then
      perform pg_temp.record('4 finalisation sans conducted_by (observations OK) -> refusée', 'PASS');
    else
      perform pg_temp.record('4 finalisation sans conducted_by (observations OK) -> refusée', 'FAIL',
        format('sqlstate=%L constraint=%L — %s', v_sqlstate, v_constraint, sqlerrm));
    end if;
  end;

  perform pg_temp.act_as_owner();
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. RÉSUMÉ.
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
