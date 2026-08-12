-- ============================================================================
-- TEST — Module 8 (résiliation anticipée de bail par consensus obligatoire,
-- table lease_termination_requests) + extension Module 5b (statut effectif
-- 'hors_periode').
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/.
--
-- Fonctionnement : même patron que supabase/tests/module7b_maintenance_locks.sql.
--   - Tout s'exécute dans une seule transaction, ROLLBACK en toute fin :
--     aucune donnée de test ne persiste, le script est rejouable à volonté.
--   - Les fixtures (organisation, comptes, biens, baux) sont créées avec le
--     rôle de connexion (superuser, bypasse RLS). Chaque scénario bascule
--     ensuite explicitement sur le rôle Postgres et l'identité
--     (request.jwt.claims) voulus via pg_temp.act_as().
--   - Résultats : RAISE NOTICE '[PASS|FAIL] ...' au fil de l'eau, plus un
--     résumé tabulaire (pg_temp.test_results) juste avant le ROLLBACK.
--
-- Hypothèses sur l'instance locale (Supabase CLI standard), identiques à
-- module7b_maintenance_locks.sql :
--   - rôles Postgres authenticated / service_role présents avec leurs GRANTs
--     par défaut sur le schéma public (service_role : BYPASSRLS).
--   - connexion effectuée avec un rôle superuser (postgres).
--   - auth.uid() lit request.jwt.claims ->> 'sub'.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 8 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module8_lease_termination_consensus.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques à module7b_maintenance_locks.sql).
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
    perform pg_temp.record(p_name, 'FAIL', format('detail attendu=%L, obtenu=%L', p_expected, p_got));
  end if;
end;
$$;

-- Bascule la session sur le rôle Postgres p_pg_role, avec request.jwt.claims
-- simulant l'utilisateur p_user_id (ce que auth.uid() lit). p_user_id = null
-- simule un rôle sans identité applicative (service_role "brut").
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

-- Revient au rôle de connexion (superuser, bypasse RLS) pour monter les
-- fixtures entre deux scénarios.
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
-- 1. FIXTURES — une organisation, un staff (admin), un locataire, et un bail
--    actif dédié par scénario (one_pending_per_lease + immutabilité post-
--    résiliation obligent à ne jamais réutiliser un bail entre scénarios
--    indépendants). lease_i est créé directement à un statut non-actif ;
--    lease_k a un start_date dans le passé pour isoler proprement le test
--    de date rétroactive du test "avant le début du bail".
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id    uuid;
  v_staff_id  uuid := gen_random_uuid();
  v_tenant_id uuid := gen_random_uuid();
  v_prop_id   uuid;
  v_lease_a   uuid;
  v_lease_b   uuid;
  v_lease_c   uuid;
  v_lease_d   uuid;
  v_lease_e   uuid;
  v_lease_f   uuid;
  v_lease_g   uuid;
  v_lease_i   uuid;
  v_lease_k   uuid;
  v_lease_l   uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 8', 'test-org-8-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-8@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 8'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-8@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test 8'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- lease_a : scénario 1 (locataire initie -> staff accepte).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — A', '1 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_a;

  -- lease_b : scénario 2 (staff initie -> locataire accepte).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — B', '2 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_b;

  -- lease_c : scénario 3a (locataire initie, staff refuse).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — C', '3 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_c;

  -- lease_d : scénario 3b (staff initie, locataire refuse).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — D', '4 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_d;

  -- lease_e : scénarios 4/5/6a/7 (annulation, annulation refusée par
  -- l'adverse, auto-réponse locataire, doublon en_attente, nouvelle demande
  -- après annulation).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — E', '5 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_e;

  -- lease_f : scénario 6b (auto-réponse staff).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — F', '6 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_f;

  -- lease_g : scénarios 8/9 (immutabilité des termes, champs de réponse
  -- non modifiables directement).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — G', '7 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_g;

  -- lease_i : scénario 10 (bail non-actif dès la création — statut posé
  -- directement, hors cycle de vie normal, uniquement pour ce test).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — I', '8 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing, status
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye', 'termine')
  returning id into v_lease_i;

  -- lease_k : scénario 11 (date rétroactive). start_date dans le passé pour
  -- que "requested_end_date < aujourd'hui" ne soit jamais aussi
  -- "< start_date" (les deux checks seraient sinon indissociables).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — K', '9 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date - 30, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_k;

  -- lease_l : scénario 13 (défense en profondeur, service_role).
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 8 — L', '10 rue du Test', 500000, 'longue_duree') returning id into v_prop_id;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_id, v_tenant_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_l;

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
    v_lease_f   as lease_f,
    v_lease_g   as lease_g,
    v_lease_i   as lease_i,
    v_lease_k   as lease_k,
    v_lease_l   as lease_l;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIO 1 — LOCATAIRE INITIE -> STAFF ACCEPTE -> BAIL RÉSILIÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_status text;
  v_end_date date;
  v_expected_end date := current_date + 10;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_a, f.tenant_id, null, v_expected_end, 'Mutation professionnelle')
    returning id into v_request_id;
    perform pg_temp.record('1a locataire initie une demande -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('1a locataire initie une demande -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.lease_termination_requests set status = 'validee' where id = v_request_id;
    perform pg_temp.record('1b staff accepte -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('1b staff accepte -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status, end_date into v_status, v_end_date from public.leases where id = f.lease_a;
  if v_status = 'resilie' and v_end_date = v_expected_end then
    perform pg_temp.record('1c leases.status=resilie et end_date correcte après consensus', 'PASS');
  else
    perform pg_temp.record('1c leases.status=resilie et end_date correcte après consensus', 'FAIL',
      format('status=%L end_date=%L, attendu resilie/%L', v_status, v_end_date, v_expected_end));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIO 2 — STAFF INITIE -> LOCATAIRE ACCEPTE -> BAIL RÉSILIÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_status text;
  v_end_date date;
  v_expected_end date := current_date + 15;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_b, null, f.staff_id, v_expected_end, 'Vente du bien')
    returning id into v_request_id;
    perform pg_temp.record('2a staff initie une demande -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2a staff initie une demande -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    update public.lease_termination_requests set status = 'validee' where id = v_request_id;
    perform pg_temp.record('2b locataire accepte -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2b locataire accepte -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status, end_date into v_status, v_end_date from public.leases where id = f.lease_b;
  if v_status = 'resilie' and v_end_date = v_expected_end then
    perform pg_temp.record('2c leases.status=resilie et end_date correcte après consensus', 'PASS');
  else
    perform pg_temp.record('2c leases.status=resilie et end_date correcte après consensus', 'FAIL',
      format('status=%L end_date=%L, attendu resilie/%L', v_status, v_end_date, v_expected_end));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIO 3 — REFUS DANS LES DEUX SENS : bail INCHANGÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_status text;
  v_lease_status text;
  v_lease_end date;
begin
  select * into f from pg_temp.fixtures;

  -- 3a. Locataire initie, staff refuse.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_c, f.tenant_id, null, current_date + 5, 'Test refus 3a')
  returning id into v_request_id;

  perform pg_temp.act_as('authenticated', f.staff_id);
  update public.lease_termination_requests set status = 'refusee' where id = v_request_id;

  select status into v_status from public.lease_termination_requests where id = v_request_id;
  select status, end_date into v_lease_status, v_lease_end from public.leases where id = f.lease_c;

  if v_status = 'refusee' and v_lease_status = 'actif' and v_lease_end is null then
    perform pg_temp.record('3a staff refuse une demande locataire -> refusee, bail inchangé', 'PASS');
  else
    perform pg_temp.record('3a staff refuse une demande locataire -> refusee, bail inchangé', 'FAIL',
      format('request.status=%L lease.status=%L lease.end_date=%L', v_status, v_lease_status, v_lease_end));
  end if;

  -- 3b. Staff initie, locataire refuse.
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_d, null, f.staff_id, current_date + 5, 'Test refus 3b')
  returning id into v_request_id;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  update public.lease_termination_requests set status = 'refusee' where id = v_request_id;

  select status into v_status from public.lease_termination_requests where id = v_request_id;
  select status, end_date into v_lease_status, v_lease_end from public.leases where id = f.lease_d;

  if v_status = 'refusee' and v_lease_status = 'actif' and v_lease_end is null then
    perform pg_temp.record('3b locataire refuse une demande staff -> refusee, bail inchangé', 'PASS');
  else
    perform pg_temp.record('3b locataire refuse une demande staff -> refusee, bail inchangé', 'FAIL',
      format('request.status=%L lease.status=%L lease.end_date=%L', v_status, v_lease_status, v_lease_end));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIOS 4/5/6a/7 — bail E : annulation par l'initiateur, annulation
--    refusée à l'adverse, auto-réponse locataire refusée, doublon en_attente
--    refusé, nouvelle demande autorisée après annulation.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_request2_id uuid;
  v_detail text;
  v_status text;
  v_cancelled_at timestamptz;
begin
  select * into f from pg_temp.fixtures;

  -- Le locataire initie.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_e, f.tenant_id, null, current_date + 5, 'Test bail E')
  returning id into v_request_id;

  -- [7a] Doublon en_attente sur le même bail -> refusé (index partiel unique).
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_e, null, f.staff_id, current_date + 6, 'Doublon');
    perform pg_temp.record('7a deuxième demande en_attente sur bail déjà en attente -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = returned_sqlstate;
    if v_detail = '23505' then
      perform pg_temp.record('7a deuxième demande en_attente sur bail déjà en attente -> refusé', 'PASS');
    else
      perform pg_temp.record('7a deuxième demande en_attente sur bail déjà en attente -> refusé', 'FAIL',
        'sqlstate attendu 23505, obtenu ' || v_detail || ' (' || sqlerrm || ')');
    end if;
  end;

  -- [5] La partie adverse (staff) tente d'annuler -> refusé.
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.lease_termination_requests set status = 'annulee' where id = v_request_id;
    perform pg_temp.record('5 staff tente d''annuler une demande initiée par le locataire -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5 staff tente d''annuler une demande initiée par le locataire -> refusé', v_detail, 'lease_termination_request.cancel.not_initiator');
  end;

  -- [6a] Le locataire (initiateur) tente de répondre à sa propre demande -> refusé.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    update public.lease_termination_requests set status = 'validee' where id = v_request_id;
    perform pg_temp.record('6a locataire répond à sa propre demande -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6a locataire répond à sa propre demande -> refusé', v_detail, 'lease_termination_request.respond.not_authorized_staff');
  end;

  -- [4] Le locataire (initiateur légitime) annule -> autorisé.
  begin
    update public.lease_termination_requests set status = 'annulee' where id = v_request_id;
    perform pg_temp.record('4 initiateur annule sa propre demande avant réponse -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('4 initiateur annule sa propre demande avant réponse -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select status, cancelled_at into v_status, v_cancelled_at from public.lease_termination_requests where id = v_request_id;
  if v_status = 'annulee' and v_cancelled_at is not null then
    perform pg_temp.record('4b statut=annulee et cancelled_at posé', 'PASS');
  else
    perform pg_temp.record('4b statut=annulee et cancelled_at posé', 'FAIL', format('status=%L cancelled_at=%L', v_status, v_cancelled_at));
  end if;

  -- [7b] Nouvelle demande sur le même bail, après annulation -> autorisée.
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_e, f.tenant_id, null, current_date + 7, 'Nouvelle tentative après annulation')
    returning id into v_request2_id;
    perform pg_temp.record('7b nouvelle demande après annulation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('7b nouvelle demande après annulation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIO 6b — bail F : auto-réponse du staff à sa propre demande.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_f, null, f.staff_id, current_date + 5, 'Test bail F')
  returning id into v_request_id;

  begin
    update public.lease_termination_requests set status = 'validee' where id = v_request_id;
    perform pg_temp.record('6b staff répond à sa propre demande -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6b staff répond à sa propre demande -> refusé', v_detail, 'lease_termination_request.respond.not_tenant');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCÉNARIOS 8/9 — bail G : immutabilité des termes de la demande, champs
--    de réponse non modifiables hors transition.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_g, f.tenant_id, null, current_date + 5, 'Motif initial')
  returning id into v_request_id;

  -- [8a] requested_end_date immuable.
  begin
    update public.lease_termination_requests set requested_end_date = current_date + 99 where id = v_request_id;
    perform pg_temp.record('8a modifier requested_end_date après création -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('8a modifier requested_end_date après création -> refusé', v_detail, 'lease_termination_request.identity.immutable');
  end;

  -- [8b] reason immuable.
  begin
    update public.lease_termination_requests set reason = 'Motif modifié' where id = v_request_id;
    perform pg_temp.record('8b modifier reason après création -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('8b modifier reason après création -> refusé', v_detail, 'lease_termination_request.identity.immutable');
  end;

  -- [9a] responded_at non modifiable directement (staff, sans changer status).
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.lease_termination_requests set responded_at = now() where id = v_request_id;
    perform pg_temp.record('9a modifier responded_at directement -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('9a modifier responded_at directement -> refusé', v_detail, 'lease_termination_request.response_fields.server_only');
  end;

  -- [9b] responded_by_staff_id non modifiable directement.
  begin
    update public.lease_termination_requests set responded_by_staff_id = f.staff_id where id = v_request_id;
    perform pg_temp.record('9b modifier responded_by_staff_id directement -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('9b modifier responded_by_staff_id directement -> refusé', v_detail, 'lease_termination_request.response_fields.server_only');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. SCÉNARIO 10 — DEMANDE SUR UN BAIL NON-ACTIF -> refusée à l'insertion.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  -- 10a. Bail créé directement 'termine'.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_i, f.tenant_id, null, current_date + 5, 'Test bail non-actif');
    perform pg_temp.record('10a demande sur bail non-actif (termine) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('10a demande sur bail non-actif (termine) -> refusé', v_detail, 'lease_termination_request.lease.not_active');
  end;

  -- 10b (bonus). lease_a est déjà 'resilie' depuis le scénario 1 : une
  -- nouvelle demande dessus doit être refusée pour la même raison — preuve
  -- que le mécanisme se referme bien lui-même une fois la résiliation
  -- effective.
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_a, f.tenant_id, null, current_date + 20, 'Nouvelle tentative post-résiliation');
    perform pg_temp.record('10b demande sur bail déjà résilié (issu du scénario 1) -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('10b demande sur bail déjà résilié (issu du scénario 1) -> refusé', v_detail, 'lease_termination_request.lease.not_active');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. SCÉNARIO 11 — REQUESTED_END_DATE RÉTROACTIVE -> refusée.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into public.lease_termination_requests
      (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
    values (f.org_id, f.lease_k, f.tenant_id, null, current_date - 1, 'Date rétroactive');
    perform pg_temp.record('11 requested_end_date < aujourd''hui -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('11 requested_end_date < aujourd''hui -> refusé', v_detail, 'lease_termination_request.requested_end_date.retroactive');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 10. SCÉNARIO 12 — STATUT EFFECTIF 'hors_periode' (Module 5b étendu).
-- Utilise lease_a, résilié par le scénario 1 (end_date = current_date + 10).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_lease_end date;
  v_sched_unpaid_id uuid;
  v_sched_paid_id uuid;
  v_effective text;
begin
  select * into f from pg_temp.fixtures;
  select end_date into v_lease_end from public.leases where id = f.lease_a;

  perform pg_temp.act_as_owner();

  -- Échéance jamais réglée, période entièrement après la fin du bail résilié.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, f.lease_a, v_lease_end + 10, v_lease_end + 40, 1000.00, v_lease_end + 40, 'en_attente')
  returning id into v_sched_unpaid_id;

  -- Échéance intégralement réglée, même situation temporelle : ne doit
  -- jamais être réétiquetée 'hors_periode'.
  insert into public.payment_schedules
    (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (f.org_id, f.lease_a, v_lease_end + 15, v_lease_end + 45, 500.00, v_lease_end + 45, 'en_attente')
  returning id into v_sched_paid_id;

  insert into public.payments
    (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (f.org_id, f.lease_a, v_sched_paid_id, 500.00, current_date, 'virement', 'loyer', 'entrant', 'confirme');

  select effective_status into v_effective
  from public.payment_schedules_effective_status where id = v_sched_unpaid_id;
  perform pg_temp.check_detail('12a échéance non réglée après fin de bail résilié -> hors_periode', v_effective, 'hors_periode');

  select effective_status into v_effective
  from public.payment_schedules_effective_status where id = v_sched_paid_id;
  perform pg_temp.check_detail('12b échéance déjà payee après fin de bail résilié -> reste payee', v_effective, 'payee');
end;
$$;

-- ----------------------------------------------------------------------------
-- 11. SCÉNARIO 13 — DÉFENSE EN PROFONDEUR (service_role, bypasse RLS).
-- Rejoue 3 refus déjà observés sous 'authenticated' pour prouver qu'ils
-- tiennent uniquement aux triggers (identité/état), jamais aux policies RLS.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_request_id uuid;
  v_detail text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_id);
  insert into public.lease_termination_requests
    (organization_id, lease_id, initiated_by_tenant_id, initiated_by_staff_id, requested_end_date, reason)
  values (f.org_id, f.lease_l, f.tenant_id, null, current_date + 5, 'Test bail L')
  returning id into v_request_id;

  -- 13.1 : locataire (initiateur) répond à sa propre demande, via service_role.
  perform pg_temp.act_as('service_role', f.tenant_id);
  begin
    update public.lease_termination_requests set status = 'validee' where id = v_request_id;
    perform pg_temp.record('13.1 service_role+locataire auto-réponse -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('13.1 service_role+locataire auto-réponse -> refusé malgré bypass RLS', v_detail, 'lease_termination_request.respond.not_authorized_staff');
  end;

  -- 13.2 : staff (partie adverse) tente d'annuler, via service_role.
  perform pg_temp.act_as('service_role', f.staff_id);
  begin
    update public.lease_termination_requests set status = 'annulee' where id = v_request_id;
    perform pg_temp.record('13.2 service_role+staff annule demande adverse -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('13.2 service_role+staff annule demande adverse -> refusé malgré bypass RLS', v_detail, 'lease_termination_request.cancel.not_initiator');
  end;

  -- 13.3 : modification de requested_end_date, via service_role.
  begin
    update public.lease_termination_requests set requested_end_date = current_date + 99 where id = v_request_id;
    perform pg_temp.record('13.3 service_role modifie requested_end_date -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('13.3 service_role modifie requested_end_date -> refusé malgré bypass RLS', v_detail, 'lease_termination_request.identity.immutable');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 12. RÉSUMÉ.
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
