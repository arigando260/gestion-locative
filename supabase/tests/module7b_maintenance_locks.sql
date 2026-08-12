-- ============================================================================
-- TEST — Module 7b (verrou photo locataire/staff aligné sur le statut du
-- ticket, gel de estimated_cost/actual_cost après imputation de caution).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/.
--
-- Fonctionnement :
--   - Tout s'exécute dans une seule transaction, ROLLBACK en toute fin :
--     aucune donnée de test ne persiste, le script est rejouable à volonté.
--   - Les fixtures (organisation, comptes, bien, baux, tickets, mouvements
--     de caution) sont créées avec le rôle de connexion (superuser, bypasse
--     RLS). Chaque scénario bascule ensuite explicitement sur le rôle
--     Postgres et l'identité (request.jwt.claims) voulus via pg_temp.act_as().
--   - Résultats : RAISE NOTICE '[PASS|FAIL] ...' au fil de l'eau, plus un
--     résumé tabulaire (pg_temp.test_results) juste avant le ROLLBACK.
--
-- Hypothèses sur l'instance locale (Supabase CLI standard) :
--   - rôles Postgres authenticated / service_role présents avec leurs GRANTs
--     par défaut sur le schéma public et storage.
--   - connexion effectuée avec un rôle superuser (postgres) : seul capable
--     de SET ROLE vers authenticated/service_role et de bypasser RLS pour
--     monter les fixtures.
--   - auth.uid() lit request.jwt.claims ->> 'sub' (implémentation standard
--     de l'extension auth Supabase).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module7b_maintenance_locks.sql
--
--   (le port 54322 est le port Postgres local par défaut de `supabase
--   start` ; ajuster si `supabase status` en indique un autre)
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- Autorise le DELETE direct sur storage.objects pour cette transaction
-- uniquement (protection storage.protect_delete() propre aux projets Supabase
-- hébergés, hors périmètre de nos migrations) — SET LOCAL est scopé à la
-- transaction courante, donc annulé par le ROLLBACK final comme tout le reste.
set local storage.allow_delete_query = 'true';

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (schéma temporaire de session, jamais persisté).
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

-- pg_temp.record/check_detail/act_as/act_as_owner : aucun GRANT EXECUTE
-- explicite nécessaire — Postgres accorde EXECUTE à PUBLIC par défaut sur
-- toute fonction nouvellement créée (schéma pg_temp compris), tant que rien
-- ne le révoque explicitement, ce qui n'est pas fait ici.
--
-- pg_temp.test_results, en revanche, n'est accessible qu'à son propriétaire
-- (le rôle de connexion) tant qu'aucun GRANT n'est posé : record() n'est PAS
-- security definer, donc l'INSERT qu'elle effectue s'exécute avec les droits
-- du rôle courant au moment de l'appel (authenticated/service_role une fois
-- basculé via pg_temp.act_as). Sans ce GRANT, tout appel à record()/
-- check_detail() depuis un scénario non-owner échouerait par permission
-- refusée — pas de test qui échoue, un script qui plante. Le PK "serial"
-- crée aussi une séquence implicite : nextval() dessus exige USAGE, non
-- couvert par le GRANT SELECT/INSERT sur la table elle-même.
grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_staff_id     uuid := gen_random_uuid();
  v_tenant_id    uuid := gen_random_uuid();
  v_property_id  uuid;
  v_lease_id     uuid;
  v_property2_id uuid;
  v_lease2_id    uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 7b', 'test-org-7b-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  -- Staff interne (admin), via le flux d'inscription standard : déclenche
  -- private.handle_new_user (after insert on auth.users).
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-7b@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  -- Locataire, même flux : crée aussi l'adhésion active à l'organisation
  -- (Module 1b) puisque organization_id est fourni dans les métadonnées.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_id, 'tenant-7b@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant Test'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien Test 7b', '1 rue du Test', 500000, 'longue_duree')
  returning id into v_property_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (
    v_org_id, v_property_id, v_tenant_id, current_date,
    100000, 'mensuel', 200000, 'postpaye'
  ) returning id into v_lease_id;

  -- Second bien/bail (même locataire), uniquement pour le test de
  -- non-régression "incohérence bail ticket vs bail imputation".
  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien Test 7b (bis)', '2 rue du Test', 450000, 'longue_duree')
  returning id into v_property2_id;

  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (
    v_org_id, v_property2_id, v_tenant_id, current_date,
    90000, 'mensuel', 180000, 'postpaye'
  ) returning id into v_lease2_id;

  create table pg_temp.fixtures as
  select
    v_org_id       as org_id,
    v_staff_id     as staff_id,
    v_tenant_id    as tenant_id,
    v_property_id  as property_id,
    v_lease_id     as lease_id,
    v_property2_id as property2_id,
    v_lease2_id    as lease2_id;
end;
$$;

-- pg_temp.fixtures n'existe qu'à partir d'ici : le GRANT ne peut pas être
-- monté plus tôt avec ceux de test_results (la table n'existait pas encore).
grant select, insert on pg_temp.fixtures to authenticated, service_role;

do $$
declare
  f record;
  v_signale_id          uuid;
  v_en_cours_id         uuid;
  v_resolu_id           uuid;
  v_ferme_id            uuid;
  v_cost_locked_id      uuid;
  v_cost_free_id        uuid;
  v_novacant_locked_id  uuid;
  v_flow_id             uuid;
  v_photolimit_id       uuid;
  v_mismatch_id         uuid;
begin
  select * into f from pg_temp.fixtures;

  -- Verrou photo : un ticket par statut, signalé par le locataire.
  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_tenant_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.tenant_id, 'Fuite évier — signalé', 'signale')
  returning id into v_signale_id;

  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_tenant_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.tenant_id, 'Chauffe-eau — en cours', 'en_cours')
  returning id into v_en_cours_id;

  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_tenant_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.tenant_id, 'Volet cassé — résolu', 'resolu')
  returning id into v_resolu_id;

  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_tenant_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.tenant_id, 'Serrure — fermé', 'ferme')
  returning id into v_ferme_id;

  -- Gel des coûts : un ticket qui sera référencé par une imputation, un qui
  -- ne le sera jamais (contrôle), un sans bail (bien vacant).
  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_staff_id, title, status, estimated_cost)
  values (f.org_id, f.property_id, f.lease_id, f.staff_id, 'Peinture — sera imputé', 'en_cours', 150.00)
  returning id into v_cost_locked_id;

  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_staff_id, title, status, estimated_cost)
  values (f.org_id, f.property_id, f.lease_id, f.staff_id, 'Robinet — jamais imputé', 'en_cours', 50.00)
  returning id into v_cost_free_id;

  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_staff_id, title, status, estimated_cost)
  values (f.org_id, f.property_id, null, f.staff_id, 'Dégât bien vacant — sans bail', 'en_cours', 80.00)
  returning id into v_novacant_locked_id;

  -- Non-régression : transitions de statut / resolved_at.
  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_tenant_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.tenant_id, 'Test resolved_at', 'signale')
  returning id into v_flow_id;

  -- Non-régression : plafond de 10 photos + immutabilité du contenu.
  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_staff_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.staff_id, 'Test limite photos', 'en_cours')
  returning id into v_photolimit_id;

  -- Non-régression : cohérence deposit_ledger.maintenance_ticket_id / bail.
  insert into public.maintenance_tickets
    (organization_id, property_id, lease_id, reported_by_staff_id, title, status)
  values (f.org_id, f.property_id, f.lease_id, f.staff_id, 'Test incohérence bail', 'en_cours')
  returning id into v_mismatch_id;

  create table pg_temp.tickets as
  select
    v_signale_id         as signale_id,
    v_en_cours_id        as en_cours_id,
    v_resolu_id          as resolu_id,
    v_ferme_id           as ferme_id,
    v_cost_locked_id     as cost_locked_id,
    v_cost_free_id       as cost_free_id,
    v_novacant_locked_id as novacant_locked_id,
    v_flow_id            as flow_id,
    v_photolimit_id      as photolimit_id,
    v_mismatch_id        as mismatch_id;

  -- Dépôt initial suffisant sur les deux baux, puis imputations "impayes_
  -- utilities" pointant vers les tickets qui doivent être gelés. Catégorie
  -- choisie délibérément à la place de 'degats' : le trigger de gel
  -- (Module 7b) ne regarde que l'existence d'une ligne deposit_ledger, quelle
  -- que soit sa catégorie, alors que 'degats' entraîne des prérequis sans
  -- rapport avec ce test (état des lieux d'entrée finalisé ET validé par le
  -- locataire, leases.keys_returned_at, état des lieux de sortie finalisé —
  -- voir private.validate_deposit_ledger_damage_imputation_requires_inspections,
  -- Module 6). deposit_type suit : 'impayes_utilities' exige
  -- 'caution_utilities' (contrainte deposit_ledger_category_matches_deposit_type).
  insert into public.deposit_ledger (organization_id, lease_id, deposit_type, entry_type, amount)
  values
    (f.org_id, f.lease_id, 'caution_utilities', 'depot_initial', 1000.00),
    (f.org_id, f.lease2_id, 'caution_utilities', 'depot_initial', 1000.00);

  insert into public.deposit_ledger
    (organization_id, lease_id, deposit_type, entry_type, imputation_category, amount, reason, maintenance_ticket_id)
  values
    (f.org_id, f.lease_id, 'caution_utilities', 'imputation', 'impayes_utilities', 100.00,
     'Test 7b — imputation ticket avec bail', v_cost_locked_id),
    (f.org_id, f.lease_id, 'caution_utilities', 'imputation', 'impayes_utilities', 100.00,
     'Test 7b — imputation ticket sans bail', v_novacant_locked_id);
end;
$$;

-- Même remarque que pour pg_temp.fixtures : pg_temp.tickets vient d'être créée.
grant select, insert on pg_temp.tickets to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. VERROU PHOTO — TABLE public.maintenance_ticket_photos.
-- ----------------------------------------------------------------------------

-- 2.1 Locataire, ticket 'signale' : insert + delete autorisés.
do $$
declare
  f record; t record; v_photo_id uuid; v_detail text; v_rows int;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;
  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, t.signale_id, f.org_id || '/' || t.signale_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.1')
    returning id into v_photo_id;
    perform pg_temp.record('2.1a tenant/signale insert photo -> autorisé', 'PASS');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.record('2.1a tenant/signale insert photo -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm || coalesce(' / ' || v_detail, ''));
  end;

  begin
    delete from public.maintenance_ticket_photos where id = v_photo_id;
    get diagnostics v_rows = row_count;
    if v_rows = 1 then
      perform pg_temp.record('2.1b tenant/signale delete photo -> autorisé', 'PASS');
    else
      perform pg_temp.record('2.1b tenant/signale delete photo -> autorisé', 'FAIL', format('%s ligne(s) supprimée(s), attendu 1', v_rows));
    end if;
  exception when others then
    perform pg_temp.record('2.1b tenant/signale delete photo -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;
end;
$$;

-- 2.2 Locataire, ticket 'en_cours' : insert + delete refusés (nouveau verrou).
do $$
declare
  f record; t record; v_photo_id uuid; v_detail text; v_rows int;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  -- Photo pré-existante déposée par le staff, pour tester le delete. Seedée
  -- via l'identité staff (is_internal() = true), jamais via act_as_owner() :
  -- ce rôle superuser n'a pas de profil interne reconnu (auth.uid() = null
  -- une fois basculé), donc private.is_internal() y renvoie false et la
  -- branche locataire du trigger le traiterait comme un locataire non-staff
  -- dès que status <> 'signale'.
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
  values (f.org_id, t.en_cours_id, f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.2')
  returning id into v_photo_id;

  perform pg_temp.act_as('authenticated', f.tenant_id);

  begin
    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, t.en_cours_id, f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.2b');
    perform pg_temp.record('2.2a tenant/en_cours insert photo -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('2.2a tenant/en_cours insert photo -> refusé', v_detail, 'maintenance_ticket_photo.tenant_write.locked_after_staff_action');
  end;

  -- DELETE : la policy RLS locataire (status = 'signale') filtre la ligne
  -- avant même que le trigger BEFORE DELETE ne s'exécute -> 0 ligne, pas
  -- d'exception (voir section 4 pour la preuve que le trigger bloque quand
  -- même, indépendamment de RLS).
  delete from public.maintenance_ticket_photos where id = v_photo_id;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform pg_temp.record('2.2b tenant/en_cours delete photo -> refusé (silencieux via RLS)', 'PASS');
  else
    perform pg_temp.record('2.2b tenant/en_cours delete photo -> refusé (silencieux via RLS)', 'FAIL', format('%s ligne(s) supprimée(s), attendu 0', v_rows));
  end if;
end;
$$;

-- 2.3 Locataire, tickets 'resolu' et 'ferme' : toujours refusés (protection
-- pré-existante, message ticket_closed.locked, inchangée par 7b).
do $$
declare
  f record; t record; v_photo_id uuid; v_detail text; v_rows int;
  v_case record;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  for v_case in
    select t.resolu_id as ticket_id, 'resolu' as label
    union all
    select t.ferme_id, 'ferme'
  loop
    -- Seedée via l'identité staff (is_internal() = true) : act_as_owner()
    -- serait aussi traité comme "non-staff" par la branche locataire du
    -- trigger (auth.uid() = null -> is_internal() = false). Le check
    -- resolu/ferme, lui, s'applique à staff comme à owner (pas d'exception
    -- is_internal() dessus) : la photo doit donc être insérée pendant que le
    -- ticket est encore signale/en_cours, puis le ticket transitionné vers
    -- son statut cible ensuite — même sous identité staff.
    perform pg_temp.act_as('authenticated', f.staff_id);
    update public.maintenance_tickets set status = 'signale' where id = v_case.ticket_id;

    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, v_case.ticket_id, f.org_id || '/' || v_case.ticket_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.3-' || v_case.label)
    returning id into v_photo_id;

    update public.maintenance_tickets set status = v_case.label where id = v_case.ticket_id;

    perform pg_temp.act_as('authenticated', f.tenant_id);

    begin
      insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
      values (f.org_id, v_case.ticket_id, f.org_id || '/' || v_case.ticket_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.3b-' || v_case.label);
      perform pg_temp.record('2.3 tenant/' || v_case.label || ' insert photo -> refusé', 'FAIL', 'succès inattendu');
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform pg_temp.check_detail('2.3 tenant/' || v_case.label || ' insert photo -> refusé', v_detail, 'maintenance_ticket_photo.ticket_closed.locked');
    end;

    delete from public.maintenance_ticket_photos where id = v_photo_id;
    get diagnostics v_rows = row_count;
    if v_rows = 0 then
      perform pg_temp.record('2.3 tenant/' || v_case.label || ' delete photo -> refusé (silencieux via RLS)', 'PASS');
    else
      perform pg_temp.record('2.3 tenant/' || v_case.label || ' delete photo -> refusé (silencieux via RLS)', 'FAIL', format('%s ligne(s) supprimée(s), attendu 0', v_rows));
    end if;
  end loop;
end;
$$;

-- 2.4 Staff, ticket 'en_cours' : fenêtre inchangée, insert + delete autorisés.
do $$
declare
  f record; t record; v_photo_id uuid; v_rows int;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;
  perform pg_temp.act_as('authenticated', f.staff_id);

  begin
    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, t.en_cours_id, f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.4')
    returning id into v_photo_id;
    perform pg_temp.record('2.4a staff/en_cours insert photo -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2.4a staff/en_cours insert photo -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  delete from public.maintenance_ticket_photos where id = v_photo_id;
  get diagnostics v_rows = row_count;
  if v_rows = 1 then
    perform pg_temp.record('2.4b staff/en_cours delete photo -> autorisé', 'PASS');
  else
    perform pg_temp.record('2.4b staff/en_cours delete photo -> autorisé', 'FAIL', format('%s ligne(s) supprimée(s), attendu 1', v_rows));
  end if;
end;
$$;

-- 2.5 Staff, tickets 'resolu'/'ferme' : toujours refusé (RLS staff n'a pas de
-- condition de statut -> c'est le trigger, pas RLS, qui protège ici : la
-- ligne est visible, le delete atteint le trigger et lève l'exception).
do $$
declare
  f record; t record; v_photo_id uuid; v_detail text;
  v_case record;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  for v_case in
    select t.resolu_id as ticket_id, 'resolu' as label
    union all
    select t.ferme_id, 'ferme'
  loop
    -- Seedée via l'identité staff, même raison qu'en 2.3 (act_as_owner()
    -- n'est pas reconnu is_internal()) : ticket redescendu à signale le
    -- temps de l'insertion, le check resolu/ferme n'ayant pas d'exception
    -- pour un profil interne.
    perform pg_temp.act_as('authenticated', f.staff_id);
    update public.maintenance_tickets set status = 'signale' where id = v_case.ticket_id;

    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, v_case.ticket_id, f.org_id || '/' || v_case.ticket_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.5-' || v_case.label)
    returning id into v_photo_id;

    update public.maintenance_tickets set status = v_case.label where id = v_case.ticket_id;

    perform pg_temp.act_as('authenticated', f.staff_id);

    begin
      insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
      values (f.org_id, v_case.ticket_id, f.org_id || '/' || v_case.ticket_id || '/' || gen_random_uuid() || '.jpg', 'hash-2.5b-' || v_case.label);
      perform pg_temp.record('2.5 staff/' || v_case.label || ' insert photo -> refusé', 'FAIL', 'succès inattendu');
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform pg_temp.check_detail('2.5 staff/' || v_case.label || ' insert photo -> refusé', v_detail, 'maintenance_ticket_photo.ticket_closed.locked');
    end;

    begin
      delete from public.maintenance_ticket_photos where id = v_photo_id;
      perform pg_temp.record('2.5 staff/' || v_case.label || ' delete photo -> refusé', 'FAIL', 'succès inattendu');
    exception when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      perform pg_temp.check_detail('2.5 staff/' || v_case.label || ' delete photo -> refusé', v_detail, 'maintenance_ticket_photo.ticket_closed.locked');
    end;
  end loop;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. VERROU PHOTO — STORAGE storage.objects (bucket maintenance-photos).
-- Pas de trigger métier ici, uniquement RLS : insert bloqué -> erreur
-- générique 42501 ; delete bloqué -> filtré silencieusement (0 ligne), pour
-- le locataire comme pour le staff (aucune des deux policies storage n'a de
-- trigger de secours, contrairement à la table).
-- ----------------------------------------------------------------------------

do $$
declare
  f record; t record; v_path text; v_sqlstate text; v_rows int;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  -- 3.1 Locataire, 'signale' : insert + delete autorisés.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  v_path := f.org_id || '/' || t.signale_id || '/' || gen_random_uuid() || '.jpg';
  begin
    insert into storage.objects (bucket_id, name) values ('maintenance-photos', v_path);
    perform pg_temp.record('3.1a tenant/signale storage insert -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('3.1a tenant/signale storage insert -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  delete from storage.objects where bucket_id = 'maintenance-photos' and name = v_path;
  get diagnostics v_rows = row_count;
  if v_rows = 1 then
    perform pg_temp.record('3.1b tenant/signale storage delete -> autorisé', 'PASS');
  else
    perform pg_temp.record('3.1b tenant/signale storage delete -> autorisé', 'FAIL', format('%s ligne(s) supprimée(s), attendu 1', v_rows));
  end if;

  -- 3.2 Locataire, 'en_cours' : insert refusé (42501), delete filtré (0 ligne).
  -- Pas de trigger métier sur storage.objects (uniquement RLS), donc pas de
  -- souci d'is_internal() ici contrairement à la table — seedée via staff
  -- par cohérence avec le reste du script.
  perform pg_temp.act_as('authenticated', f.staff_id);
  v_path := f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name) values ('maintenance-photos', v_path);

  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into storage.objects (bucket_id, name)
    values ('maintenance-photos', f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg');
    perform pg_temp.record('3.2a tenant/en_cours storage insert -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate;
    if v_sqlstate = '42501' then
      perform pg_temp.record('3.2a tenant/en_cours storage insert -> refusé', 'PASS');
    else
      perform pg_temp.record('3.2a tenant/en_cours storage insert -> refusé', 'FAIL', 'sqlstate attendu 42501, obtenu ' || v_sqlstate || ' (' || sqlerrm || ')');
    end if;
  end;

  delete from storage.objects where bucket_id = 'maintenance-photos' and name = v_path;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform pg_temp.record('3.2b tenant/en_cours storage delete -> refusé (0 ligne)', 'PASS');
  else
    perform pg_temp.record('3.2b tenant/en_cours storage delete -> refusé (0 ligne)', 'FAIL', format('%s ligne(s) supprimée(s), attendu 0', v_rows));
  end if;

  -- 3.3 Staff, 'en_cours' : insert + delete toujours autorisés.
  perform pg_temp.act_as('authenticated', f.staff_id);
  v_path := f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg';
  begin
    insert into storage.objects (bucket_id, name) values ('maintenance-photos', v_path);
    perform pg_temp.record('3.3a staff/en_cours storage insert -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('3.3a staff/en_cours storage insert -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  delete from storage.objects where bucket_id = 'maintenance-photos' and name = v_path;
  get diagnostics v_rows = row_count;
  if v_rows = 1 then
    perform pg_temp.record('3.3b staff/en_cours storage delete -> autorisé', 'PASS');
  else
    perform pg_temp.record('3.3b staff/en_cours storage delete -> autorisé', 'FAIL', format('%s ligne(s) supprimée(s), attendu 1', v_rows));
  end if;

  -- 3.4 Locataire, 'resolu' : insert refusé (42501), delete filtré (0 ligne).
  -- Idem 3.2 : storage.objects n'a pas de trigger, seedée via staff par
  -- cohérence (la policy staff n'a d'ailleurs aucune condition de statut, à
  -- la différence de la table).
  perform pg_temp.act_as('authenticated', f.staff_id);
  v_path := f.org_id || '/' || t.resolu_id || '/' || gen_random_uuid() || '.jpg';
  insert into storage.objects (bucket_id, name) values ('maintenance-photos', v_path);

  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into storage.objects (bucket_id, name)
    values ('maintenance-photos', f.org_id || '/' || t.resolu_id || '/' || gen_random_uuid() || '.jpg');
    perform pg_temp.record('3.4a tenant/resolu storage insert -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate;
    if v_sqlstate = '42501' then
      perform pg_temp.record('3.4a tenant/resolu storage insert -> refusé', 'PASS');
    else
      perform pg_temp.record('3.4a tenant/resolu storage insert -> refusé', 'FAIL', 'sqlstate attendu 42501, obtenu ' || v_sqlstate);
    end if;
  end;

  delete from storage.objects where bucket_id = 'maintenance-photos' and name = v_path;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform pg_temp.record('3.4b tenant/resolu storage delete -> refusé (0 ligne)', 'PASS');
  else
    perform pg_temp.record('3.4b tenant/resolu storage delete -> refusé (0 ligne)', 'FAIL', format('%s ligne(s) supprimée(s), attendu 0', v_rows));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. DÉFENSE EN PROFONDEUR — service_role (bypasse RLS entièrement).
-- Prouve que le blocage ne dépend pas uniquement des policies RLS.
-- ----------------------------------------------------------------------------

do $$
declare
  f record; t record; v_photo_id uuid; v_detail text;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  -- 4.1 INSERT : déjà observable sans service_role (section 2.2a), rejoué
  -- ici pour confirmer explicitement l'indépendance vis-à-vis de RLS.
  perform pg_temp.act_as('service_role', f.tenant_id);
  begin
    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, t.en_cours_id, f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg', 'hash-4.1');
    perform pg_temp.record('4.1 service_role+tenant/en_cours insert photo -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.1 service_role+tenant/en_cours insert photo -> refusé malgré bypass RLS', v_detail, 'maintenance_ticket_photo.tenant_write.locked_after_staff_action');
  end;

  -- 4.2 DELETE : LE cas où service_role change vraiment le résultat observé
  -- (en 2.2b, RLS filtrait la ligne avant que le trigger ne s'exécute -> 0
  -- ligne silencieuse ; ici RLS est bypassée, la ligne est un candidat au
  -- delete, le trigger s'exécute et lève l'exception).
  perform pg_temp.act_as('authenticated', f.staff_id);
  insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
  values (f.org_id, t.en_cours_id, f.org_id || '/' || t.en_cours_id || '/' || gen_random_uuid() || '.jpg', 'hash-4.2')
  returning id into v_photo_id;

  perform pg_temp.act_as('service_role', f.tenant_id);
  begin
    delete from public.maintenance_ticket_photos where id = v_photo_id;
    perform pg_temp.record('4.2 service_role+tenant/en_cours delete photo -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu (RLS bypassée, aucune exception)');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.2 service_role+tenant/en_cours delete photo -> refusé malgré bypass RLS', v_detail, 'maintenance_ticket_photo.tenant_write.locked_after_staff_action');
  end;

  -- 4.3 Gel des coûts : bypass RLS, le trigger de gel s'applique quand même
  -- (il ne fait aucune distinction d'acteur). Utilise le ticket déjà imputé
  -- (cost_locked_id, imputation posée en section 1).
  perform pg_temp.act_as('service_role', f.staff_id);
  begin
    update public.maintenance_tickets set estimated_cost = 999.00 where id = t.cost_locked_id;
    perform pg_temp.record('4.3 service_role cost update sur ticket imputé -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('4.3 service_role cost update sur ticket imputé -> refusé malgré bypass RLS', v_detail, 'maintenance_ticket.cost.locked_after_imputation');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. GEL DE estimated_cost / actual_cost APRÈS IMPUTATION.
-- ----------------------------------------------------------------------------

do $$
declare
  f record; t record; v_detail text;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;
  perform pg_temp.act_as('authenticated', f.staff_id);

  -- 5.1 / 5.2 Ticket jamais imputé : modification des deux coûts autorisée.
  begin
    update public.maintenance_tickets set estimated_cost = 200.00 where id = t.cost_free_id;
    perform pg_temp.record('5.1 staff estimated_cost sur ticket sans imputation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('5.1 staff estimated_cost sur ticket sans imputation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  begin
    update public.maintenance_tickets set actual_cost = 180.00 where id = t.cost_free_id;
    perform pg_temp.record('5.2 staff actual_cost sur ticket sans imputation -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('5.2 staff actual_cost sur ticket sans imputation -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  -- 5.3 Champ non lié au coût : toujours modifiable, même sur un ticket
  -- imputé (le gel ne porte que sur estimated_cost/actual_cost).
  begin
    update public.maintenance_tickets set title = 'Peinture — sera imputé (modifié)' where id = t.cost_locked_id;
    perform pg_temp.record('5.3 staff title sur ticket imputé -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('5.3 staff title sur ticket imputé -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  -- 5.4 No-op : réécrire la même valeur ne doit pas être bloqué.
  begin
    update public.maintenance_tickets set estimated_cost = 150.00 where id = t.cost_locked_id;
    perform pg_temp.record('5.4 staff estimated_cost=valeur identique sur ticket imputé -> autorisé (no-op)', 'PASS');
  exception when others then
    perform pg_temp.record('5.4 staff estimated_cost=valeur identique sur ticket imputé -> autorisé (no-op)', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  -- 5.5 estimated_cost seul : refusé.
  begin
    update public.maintenance_tickets set estimated_cost = 175.00 where id = t.cost_locked_id;
    perform pg_temp.record('5.5 staff estimated_cost sur ticket imputé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5.5 staff estimated_cost sur ticket imputé -> refusé', v_detail, 'maintenance_ticket.cost.locked_after_imputation');
  end;

  -- 5.6 actual_cost seul : refusé.
  begin
    update public.maintenance_tickets set actual_cost = 140.00 where id = t.cost_locked_id;
    perform pg_temp.record('5.6 staff actual_cost sur ticket imputé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5.6 staff actual_cost sur ticket imputé -> refusé', v_detail, 'maintenance_ticket.cost.locked_after_imputation');
  end;

  -- 5.7 Les deux à la fois : refusé.
  begin
    update public.maintenance_tickets set estimated_cost = 175.00, actual_cost = 140.00 where id = t.cost_locked_id;
    perform pg_temp.record('5.7 staff estimated_cost+actual_cost sur ticket imputé -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5.7 staff estimated_cost+actual_cost sur ticket imputé -> refusé', v_detail, 'maintenance_ticket.cost.locked_after_imputation');
  end;

  -- 5.8 Ticket sans bail mais imputé : gelé quand même.
  begin
    update public.maintenance_tickets set estimated_cost = 999.00 where id = t.novacant_locked_id;
    perform pg_temp.record('5.8 staff estimated_cost sur ticket imputé sans bail -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('5.8 staff estimated_cost sur ticket imputé sans bail -> refusé', v_detail, 'maintenance_ticket.cost.locked_after_imputation');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. NON-RÉGRESSION — protections existantes du Module 7.
-- ----------------------------------------------------------------------------

do $$
declare
  f record; t record; v_detail text; v_resolved_at timestamptz;
  v_first_photo_id_for_hash_test uuid; v_rows int;
begin
  select * into f from pg_temp.fixtures;
  select * into t from pg_temp.tickets;

  -- 6.1 Immuabilité identité (property_id) — inchangé depuis Module 7.
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    update public.maintenance_tickets set property_id = gen_random_uuid() where id = t.cost_free_id;
    perform pg_temp.record('6.1 staff property_id -> refusé (identité immuable)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.1 staff property_id -> refusé (identité immuable)', v_detail, 'maintenance_ticket.identity.immutable');
  end;

  -- 6.2 Locataire, champ hors titre/description (priority) même en 'signale'.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    update public.maintenance_tickets set priority = 'haute' where id = t.signale_id;
    perform pg_temp.record('6.2 tenant priority sur ticket signale -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.2 tenant priority sur ticket signale -> refusé', v_detail, 'maintenance_ticket.tenant_update.forbidden_field');
  end;

  -- 6.3 Locataire, bail invalide (inexistant) au signalement -> refusé.
  perform pg_temp.act_as('authenticated', f.tenant_id);
  begin
    insert into public.maintenance_tickets
      (organization_id, property_id, lease_id, reported_by_tenant_id, title, status, priority)
    values (f.org_id, f.property_id, gen_random_uuid(), f.tenant_id, 'Ticket bail invalide', 'signale', 'normale');
    perform pg_temp.record('6.3 tenant signalement avec bail invalide -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.3 tenant signalement avec bail invalide -> refusé', v_detail, 'maintenance_ticket.tenant_report.invalid_lease');
  end;

  -- 6.4 resolved_at posé à l'entrée en 'resolu', effacé à la réouverture.
  perform pg_temp.act_as('authenticated', f.staff_id);
  update public.maintenance_tickets set status = 'resolu' where id = t.flow_id;
  select resolved_at into v_resolved_at from public.maintenance_tickets where id = t.flow_id;
  if v_resolved_at is not null then
    perform pg_temp.record('6.4a resolved_at posé automatiquement à l''entrée en resolu', 'PASS');
  else
    perform pg_temp.record('6.4a resolved_at posé automatiquement à l''entrée en resolu', 'FAIL', 'resolved_at est null');
  end if;

  update public.maintenance_tickets set status = 'en_cours' where id = t.flow_id;
  select resolved_at into v_resolved_at from public.maintenance_tickets where id = t.flow_id;
  if v_resolved_at is null then
    perform pg_temp.record('6.4b resolved_at effacé à la réouverture (resolu -> en_cours)', 'PASS');
  else
    perform pg_temp.record('6.4b resolved_at effacé à la réouverture (resolu -> en_cours)', 'FAIL', 'resolved_at toujours renseigné');
  end if;

  -- 6.5 resolved_at non modifiable directement.
  begin
    update public.maintenance_tickets set resolved_at = now() where id = t.flow_id;
    perform pg_temp.record('6.5 staff resolved_at direct -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.5 staff resolved_at direct -> refusé', v_detail, 'maintenance_ticket.resolved_at.server_only');
  end;

  -- 6.6 Plafond de 10 photos par ticket + immutabilité du contenu.
  perform pg_temp.act_as('authenticated', f.staff_id);
  declare
    v_i int;
    v_photo_id_iter uuid;
  begin
    for v_i in 1..10 loop
      insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
      values (f.org_id, t.photolimit_id, f.org_id || '/' || t.photolimit_id || '/' || gen_random_uuid() || '.jpg', 'hash-limit-' || v_i)
      returning id into v_photo_id_iter;
      if v_i = 1 then
        v_first_photo_id_for_hash_test := v_photo_id_iter;
      end if;
    end loop;
    perform pg_temp.record('6.6a 10 photos acceptées', 'PASS');
  exception when others then
    perform pg_temp.record('6.6a 10 photos acceptées', 'FAIL', 'exception inattendue avant la 10e: ' || sqlerrm);
  end;

  begin
    insert into public.maintenance_ticket_photos (organization_id, maintenance_ticket_id, storage_path, file_hash)
    values (f.org_id, t.photolimit_id, f.org_id || '/' || t.photolimit_id || '/' || gen_random_uuid() || '.jpg', 'hash-limit-11');
    perform pg_temp.record('6.6b 11e photo refusée (plafond)', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.6b 11e photo refusée (plafond)', v_detail, 'maintenance_ticket_photo.limit.exceeded');
  end;

  -- Pas de policy UPDATE sur maintenance_ticket_photos (Module 7 : correction
  -- par suppression + nouvel envoi, jamais par modification) : RLS filtre
  -- silencieusement la ligne pour tout rôle non-bypass, avant même que le
  -- trigger prevent_maintenance_ticket_photo_content_change ne s'exécute —
  -- aucune exception à attendre ici, même principe que 2.2b/3.2b/3.4b
  -- (DELETE silencieusement filtré). row_count = 0 est le comportement
  -- correct ; row_count > 0 signifierait une vraie modification passée.
  update public.maintenance_ticket_photos set file_hash = 'hash-modifie' where id = v_first_photo_id_for_hash_test;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform pg_temp.record('6.6c file_hash immuable après insertion -> refusé (silencieux via RLS, pas de policy UPDATE)', 'PASS');
  else
    perform pg_temp.record('6.6c file_hash immuable après insertion -> refusé (silencieux via RLS, pas de policy UPDATE)', 'FAIL', format('%s ligne(s) modifiée(s), attendu 0', v_rows));
  end if;

  -- 6.7 Incohérence deposit_ledger.maintenance_ticket_id vs bail de
  -- l'imputation (ticket lié au bail 1, imputation posée sur le bail 2).
  -- Catégorie 'impayes_utilities' pour la même raison qu'en section 1 : évite
  -- de déclencher les prérequis d'état des lieux propres à 'degats', qui
  -- s'exécuteraient AVANT le contrôle de cohérence visé ici (ordre des
  -- triggers BEFORE INSERT sur deposit_ledger, alphabétique par nom).
  perform pg_temp.act_as_owner();
  begin
    insert into public.deposit_ledger
      (organization_id, lease_id, deposit_type, entry_type, imputation_category, amount, reason, maintenance_ticket_id)
    values
      (f.org_id, f.lease2_id, 'caution_utilities', 'imputation', 'impayes_utilities', 50.00, 'Test 7b — incohérence bail', t.mismatch_id);
    perform pg_temp.record('6.7 imputation bail incohérent avec le ticket -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('6.7 imputation bail incohérent avec le ticket -> refusé', v_detail, 'deposit_ledger.maintenance_ticket_mismatch.lease');
  end;
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
