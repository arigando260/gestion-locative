-- ============================================================================
-- TEST — Module 6k (validation locataire jamais avant finalisation).
--
-- 1. Locataire ne voit pas un brouillon (SELECT vide).
-- 2. Tentative de validation sur un brouillon -> refusée (nouveau slug).
-- 3. Validation sur un finalisé non contesté -> acceptée (non-régression).
-- 4. Non-régression 6f : doublon refusé tant qu'un brouillon existe.
-- 5. Non-régression 10j : exit_inspection_done toujours correct.
-- 6. Non-régression 10k : entry_inspection_done toujours correct.
--
-- Script SQL autonome — PAS une migration. Même patron que les tests
-- précédents (BEGIN/ROLLBACK, helpers pg_temp, force_lease_status).
-- ============================================================================

\set ON_ERROR_STOP on

begin;

create table pg_temp.test_results (
  id serial primary key, name text not null,
  status text not null check (status in ('PASS','FAIL')), detail text
);

create or replace function pg_temp.record(p_name text, p_status text, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into pg_temp.test_results (name, status, detail) values (p_name, p_status, p_detail);
  raise notice '[%] % %', p_status, p_name, coalesce('— ' || p_detail, '');
end;
$$;

create or replace function pg_temp.check_bool(p_name text, p_got boolean, p_expected boolean)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then perform pg_temp.record(p_name,'PASS');
  else perform pg_temp.record(p_name,'FAIL', format('attendu=%L, obtenu=%L', p_expected, p_got)); end if;
end;
$$;

create or replace function pg_temp.check_detail(p_name text, p_got text, p_expected text)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then perform pg_temp.record(p_name,'PASS');
  else perform pg_temp.record(p_name,'FAIL', format('détail attendu=%L, obtenu=%L', p_expected, p_got)); end if;
end;
$$;

create or replace function pg_temp.act_as(p_pg_role text, p_user_id uuid)
returns void language plpgsql as $$
begin
  execute format('set local role %I', p_pg_role);
  if p_user_id is null then perform set_config('request.jwt.claims', '{}', true);
  else perform set_config('request.jwt.claims', json_build_object('sub', p_user_id::text, 'role', p_pg_role)::text, true);
  end if;
end;
$$;

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claims', '{}', true); end;
$$;

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
-- FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id uuid; v_staff_id uuid := gen_random_uuid(); v_tenant_id uuid := gen_random_uuid();
  v_prop1 uuid; v_prop2 uuid; v_prop3 uuid; v_prop4 uuid;
  v_lease1 uuid; v_lease2 uuid; v_lease3 uuid; v_lease4 uuid;
  v_insp_brouillon uuid; v_insp_finalise uuid;
  v_insp_exit_ok uuid; v_insp_entry_ok uuid;
begin
  insert into public.organizations (name, slug) values ('Test Org 6k', 'test-org-6k-' || substr(gen_random_uuid()::text,1,8)) returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (v_staff_id, 'staff-6k@example.com', jsonb_build_object('account_type','internal','organization_id',v_org_id,'full_name','Staff 6k'), '{}'::jsonb, 'authenticated','authenticated');
  insert into public.user_roles (user_id, role_id) select v_staff_id, r.id from public.roles r where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (v_tenant_id, 'tenant-6k@example.com', jsonb_build_object('account_type','tenant','organization_id',v_org_id,'full_name','Tenant 6k'), '{}'::jsonb, 'authenticated','authenticated');

  insert into public.properties (organization_id, name, address, price, location_type) values (v_org_id,'Bien 6k A','1 rue Test',500000,'longue_duree') returning id into v_prop1;
  insert into public.properties (organization_id, name, address, price, location_type) values (v_org_id,'Bien 6k B','2 rue Test',500000,'longue_duree') returning id into v_prop2;
  insert into public.properties (organization_id, name, address, price, location_type) values (v_org_id,'Bien 6k C','3 rue Test',500000,'longue_duree') returning id into v_prop3;
  insert into public.properties (organization_id, name, address, price, location_type) values (v_org_id,'Bien 6k D','4 rue Test',500000,'longue_duree') returning id into v_prop4;

  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
    values (v_org_id, v_prop1, v_tenant_id, current_date - 60, 100000,'mensuel',200000,'postpaye') returning id into v_lease1;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
    values (v_org_id, v_prop2, v_tenant_id, current_date - 60, 100000,'mensuel',200000,'postpaye') returning id into v_lease2;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
    values (v_org_id, v_prop3, v_tenant_id, current_date - 60, 100000,'mensuel',200000,'postpaye') returning id into v_lease3;
  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, security_deposit_amount, payment_timing)
    values (v_org_id, v_prop4, v_tenant_id, current_date - 60, 100000,'mensuel',200000,'postpaye') returning id into v_lease4;

  perform pg_temp.force_lease_status(v_lease1,'actif');
  perform pg_temp.force_lease_status(v_lease2,'actif');
  perform pg_temp.force_lease_status(v_lease3,'actif');
  perform pg_temp.force_lease_status(v_lease4,'actif');

  -- Lease 1 : entree brouillon, créée par le staff (scénario "répond à une demande staff").
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, created_by_tenant)
  values (v_org_id, v_lease1, 'entree', current_date - 60, 'brouillon', v_staff_id, false)
  returning id into v_insp_brouillon;

  -- Lease 2 : entree finalisée, non contestée.
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by, finalized_at)
  values (v_org_id, v_lease2, 'entree', current_date - 60, 'finalise', v_staff_id, now())
  returning id into v_insp_finalise;

  -- Lease 3 : sortie finalisée non contestée (10j non-régression).
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, tenant_validation_status, tenant_validation_at, conducted_by, finalized_at)
  values (v_org_id, v_lease3, 'sortie', current_date - 5, 'finalise', 'valide', now(), v_staff_id, now())
  returning id into v_insp_exit_ok;
  update public.leases set keys_returned_at = current_date - 5 where id = v_lease3;

  -- Lease 4 : entree finalisée non contestée (10k non-régression).
  insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, tenant_validation_status, tenant_validation_at, conducted_by, finalized_at)
  values (v_org_id, v_lease4, 'entree', current_date - 60, 'finalise', 'valide', now(), v_staff_id, now())
  returning id into v_insp_entry_ok;

  create table pg_temp.fixtures as
  select v_org_id as org_id, v_staff_id as staff_id, v_tenant_id as tenant_id,
    v_lease1 as lease1, v_lease3 as lease3, v_lease4 as lease4,
    v_insp_brouillon as insp_brouillon, v_insp_finalise as insp_finalise;
end;
$$;

grant select on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. SELECT locataire sur un brouillon -> vide.
-- ----------------------------------------------------------------------------

do $$
declare f record; v_count int;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);
  select count(*) into v_count from public.property_inspections where id = f.insp_brouillon;
  perform pg_temp.act_as_owner();
  perform pg_temp.check_bool('1 SELECT locataire sur brouillon -> vide', v_count = 0, true);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. Validation sur un brouillon -> refusée.
-- ----------------------------------------------------------------------------

-- Postgres RLS exige qu'une ligne satisfasse À LA FOIS la policy UPDATE et
-- la policy SELECT pour qu'une UPDATE la trouve (vérifié empiriquement) :
-- avec la policy SELECT du point 1 en place, le locataire ne peut même
-- plus CIBLER un brouillon via UPDATE — 0 ligne affectée, silencieusement,
-- avant que le trigger n'ait sa chance de s'exécuter. Scénario 2a couvre
-- ce cas réel (RLS). Scénario 2b vérifie le trigger EN ISOLATION (en
-- superuser, qui bypass RLS mais pas les triggers), pour prouver que le
-- point 2 protège bien indépendamment — défense en profondeur réelle,
-- pas du code mort, si jamais la policy SELECT est un jour desserrée sans
-- revoir ce trigger.
do $$
declare f record; v_rowcount int; v_status text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);
  update public.property_inspections set tenant_validation_status = 'valide', tenant_validation_at = now() where id = f.insp_brouillon;
  get diagnostics v_rowcount = row_count;
  perform pg_temp.act_as_owner();
  perform pg_temp.check_bool('2a validation sur brouillon (locataire, RLS) -> 0 ligne affectée', v_rowcount = 0, true);
  select tenant_validation_status into v_status from public.property_inspections where id = f.insp_brouillon;
  perform pg_temp.check_detail('2a bis tenant_validation_status inchangé', v_status, 'en_attente');
end;
$$;

do $$
declare f record; v_detail text;
begin
  select * into f from pg_temp.fixtures;
  -- act_as_owner (superuser) : bypass RLS mais pas les triggers — isole le
  -- comportement du trigger de celui de la policy SELECT.
  begin
    update public.property_inspections set tenant_validation_status = 'valide', tenant_validation_at = now() where id = f.insp_brouillon;
    perform pg_temp.record('2b trigger seul sur brouillon (superuser, bypass RLS) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2b trigger seul sur brouillon (superuser, bypass RLS) -> refusé', v_detail, 'property_inspection.tenant_validation.requires_finalized');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. Validation sur un finalisé non contesté -> acceptée (non-régression).
-- ----------------------------------------------------------------------------

do $$
declare f record; v_status text;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    update public.property_inspections set tenant_validation_status = 'valide', tenant_validation_at = now() where id = f.insp_finalise;
    perform pg_temp.record('3 validation sur finalisé -> acceptée', 'PASS');
  exception when others then
    perform pg_temp.record('3 validation sur finalisé -> acceptée', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
  perform pg_temp.act_as_owner();
  select tenant_validation_status into v_status from public.property_inspections where id = f.insp_finalise;
  perform pg_temp.check_detail('3b tenant_validation_status = valide', v_status, 'valide');
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. Non-régression 6f : doublon refusé tant que le brouillon existe.
-- ----------------------------------------------------------------------------

do $$
declare f record; v_detail text;
begin
  select * into f from pg_temp.fixtures;
  begin
    -- inspection_date <= lease.start_date (current_date - 60) requis par
    -- trg_property_inspections_validate_entry_date (Module 6, sans slug) :
    -- une date postérieure lèverait CETTE exception-là avant même
    -- d'atteindre le contrôle anti-doublon visé ici.
    insert into public.property_inspections (organization_id, lease_id, inspection_type, inspection_date, document_status, conducted_by)
    values (f.org_id, f.lease1, 'entree', current_date - 60, 'brouillon', f.staff_id);
    perform pg_temp.record('4 doublon entree refusé (6f) -> refusée', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4 doublon entree refusé (6f) -> refusée', v_detail, 'property_inspection.duplicate_not_contested');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Non-régression 10j : exit_inspection_done toujours correct.
-- ----------------------------------------------------------------------------

do $$
declare f record; v_done boolean;
begin
  select * into f from pg_temp.fixtures;
  select exit_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease3;
  perform pg_temp.check_bool('5 exit_inspection_done (sortie finalisée non contestée) -> true', v_done, true);
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. Non-régression 10k : entry_inspection_done toujours correct.
-- ----------------------------------------------------------------------------

do $$
declare f record; v_done boolean;
begin
  select * into f from pg_temp.fixtures;
  select entry_inspection_done into v_done from public.leases_closure_status where lease_id = f.lease4;
  perform pg_temp.check_bool('6 entry_inspection_done (entrée finalisée non contestée) -> true', v_done, true);
end;
$$;

-- ----------------------------------------------------------------------------
-- RÉSUMÉ.
-- ----------------------------------------------------------------------------

select count(*) filter (where status='PASS') as passed, count(*) filter (where status='FAIL') as failed, count(*) as total from pg_temp.test_results;
select id, name, status, detail from pg_temp.test_results order by id;

do $$
declare v_failed int;
begin
  select count(*) into v_failed from pg_temp.test_results where status='FAIL';
  if v_failed > 0 then raise warning '% test(s) en échec.', v_failed; else raise notice 'Tous les tests sont passés.'; end if;
end;
$$;

rollback;
