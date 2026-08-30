-- ============================================================================
-- TEST — Module 13c (private.agent_building_scope() branchée sur buildings :
-- table building_agent_assignments, fonction de scope, policies select/
-- update/delete, RPC create_building()).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que module12p_agent_property_scope_
-- applied.sql : transaction begin/rollback, helpers pg_temp, identité
-- simulée via pg_temp.act_as(), résumé PASS/FAIL avant le ROLLBACK final.
--
-- PRINCIPE VÉRIFIÉ DANS CHAQUE TEST : l'accès à un immeuble ne dépend jamais
-- du fait qu'il contienne ou non des logements — seulement des permissions
-- et des relations d'assignation (directe, via un logement géré, ou rôle
-- global). building_a3 (créé vide par l'agent) reste visible malgré
-- l'absence de logement ; building_a2 (a un logement, mais non géré par
-- l'agent) reste invisible malgré sa présence.
--
-- Fixtures : org_a (admin_a réel, agent_a et comptable_a via staff
-- invitation), org_b entièrement séparée (admin_b réel) pour le test
-- cross-org.
--   - building_a1 : 1 logement (property_a1), géré par agent_a
--     (property_agent_assignments) -- scope "via logement".
--   - building_a2 : 1 logement (property_a2), NON géré par agent_a, aucune
--     assignation directe -- doit rester invisible à agent_a.
--   - building_a4 : 1 logement (property_a4a, géré par agent_a au départ)
--     ET une assignation directe (building_agent_assignments) posée par
--     admin_a -- sert au test "perd son dernier logement, garde l'accès".
--   - building_a5 : vide, non géré, non assigné à agent_a -- isole
--     spécifiquement le DELETE bloqué par RLS (pas par la contrainte FK
--     restrict, qui ne s'appliquerait de toute façon pas à un immeuble sans
--     logement).
--   - building_a6 : vide et SANS AUCUNE référence (ni logement, ni
--     building_agent_assignments) -- contrôle positif du DELETE (scénario
--     8), supprimé par admin_a. Ne peut PAS être un agent qui le supprime :
--     par construction, être dans le périmètre d'un agent (autre que via
--     admin/comptable) exige justement une ligne property.building_id ou
--     building_agent_assignments qui référence l'immeuble -- et cette même
--     ligne bloque ensuite le DELETE physique via ON DELETE RESTRICT. Un
--     agent ne peut donc JAMAIS supprimer un immeuble qui est dans son
--     propre périmètre (découvert en écrivant ce test, pas un défaut de la
--     migration -- comportement correct et volontaire des deux FK restrict,
--     voir rapport d'exécution).
--   - building_a3 : créé PENDANT le test par agent_a via create_building()
--     (scénarios 2/3), jamais par les fixtures.
--   - building_b1 (org_b) : pour le test cross-org (scénario 10).
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805690000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module13c_agent_building_scope_applied.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

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
-- Helpers de vérification.
-- ----------------------------------------------------------------------------

create or replace function pg_temp.check_select_count(
  p_name text, p_table text, p_org_id uuid, p_expected int
) returns void language plpgsql as $$
declare
  v_count int;
begin
  execute format('select count(*) from public.%I where organization_id = %L', p_table, p_org_id) into v_count;
  if v_count = p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('obtenu=%s attendu=%s', v_count, p_expected));
  end if;
end;
$$;

-- Vérifie la visibilité d'une ligne précise par id direct (couvre
-- explicitement "un id deviné/connu directement", même patron que
-- module12p).
create or replace function pg_temp.check_id_visible(
  p_name text, p_table text, p_id uuid, p_expected int
) returns void language plpgsql as $$
declare
  v_count int;
begin
  execute format('select count(*) from public.%I where id = %L', p_table, p_id) into v_count;
  if v_count = p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('obtenu=%s attendu=%s', v_count, p_expected));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_a         uuid;
  v_admin_a       uuid := gen_random_uuid();
  v_agent_a       uuid := gen_random_uuid();
  v_comptable_a   uuid := gen_random_uuid();
  v_token_agent     text := encode(gen_random_bytes(32), 'hex');
  v_token_comptable text := encode(gen_random_bytes(32), 'hex');
  v_org_b         uuid;
  v_admin_b       uuid := gen_random_uuid();
  v_building_a1   uuid;
  v_building_a2   uuid;
  v_building_a4   uuid;
  v_building_a5   uuid;
  v_building_a6   uuid;
  v_building_b1   uuid;
  v_property_a1   uuid;
  v_property_a2   uuid;
  v_property_a4a  uuid;
begin
  -- org_a
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_a, 'admin-13c@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 13c A',
      'organization_country', 'BJ', 'organization_phone', '90000060', 'full_name', 'Admin 13c A'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_a from public.profiles where id = v_admin_a;

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'agent-13c@example.com', 'agent', encode(extensions.digest(v_token_agent, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_agent_a, 'agent-13c@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_agent, 'full_name', 'Agent 13c A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_a, 'comptable-13c@example.com', 'comptable', encode(extensions.digest(v_token_comptable, 'sha256'), 'hex'), v_admin_a, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_comptable_a, 'comptable-13c@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_comptable, 'full_name', 'Comptable 13c A'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  -- org_b — organisation totalement séparée, pour le test cross-org.
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin_b, 'admin-13c-orgb@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 13c B',
      'organization_country', 'BJ', 'organization_phone', '90000061', 'full_name', 'Admin 13c B'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_b from public.profiles where id = v_admin_b;

  -- Immeubles + logements, tous posés par admin_a (buildings_insert n'est
  -- pas scopée par agent_building_scope -- non affectée par cette
  -- migration, voir en-tête de la migration 20260805690000).
  perform pg_temp.act_as('authenticated', v_admin_a);

  insert into public.buildings (organization_id, name, country_code, city, neighborhood, floors_count)
  values (v_org_a, 'Immeuble Test13c A1 (logement géré)', 'BJ', 'Cotonou', 'Fidjrosse', 2)
  returning id into v_building_a1;

  insert into public.buildings (organization_id, name, country_code, city, neighborhood, floors_count)
  values (v_org_a, 'Immeuble Test13c A2 (non géré)', 'BJ', 'Cotonou', 'Akpakpa', 3)
  returning id into v_building_a2;

  insert into public.buildings (organization_id, name, country_code, city, neighborhood, floors_count)
  values (v_org_a, 'Immeuble Test13c A4 (assignation directe)', 'BJ', 'Cotonou', 'Cadjehoun', 1)
  returning id into v_building_a4;

  insert into public.buildings (organization_id, name, country_code, city, neighborhood, floors_count)
  values (v_org_a, 'Immeuble Test13c A5 (vide, non géré -- isole le DELETE)', 'BJ', 'Cotonou', 'Ganhi', null)
  returning id into v_building_a5;

  insert into public.buildings (organization_id, name, country_code, city, neighborhood, floors_count)
  values (v_org_a, 'Immeuble Test13c A6 (vide, aucune référence -- contrôle positif DELETE admin)', 'BJ', 'Cotonou', 'Zongo', null)
  returning id into v_building_a6;

  insert into public.properties (organization_id, name, price, location_type, building_id, address_complement)
  values (v_org_a, 'Logement Test13c A1', 500000, 'longue_duree', v_building_a1, 'Appart 1')
  returning id into v_property_a1;

  insert into public.properties (organization_id, name, price, location_type, building_id, address_complement)
  values (v_org_a, 'Logement Test13c A2', 450000, 'longue_duree', v_building_a2, 'Appart 1')
  returning id into v_property_a2;

  insert into public.properties (organization_id, name, price, location_type, building_id, address_complement)
  values (v_org_a, 'Logement Test13c A4a', 400000, 'longue_duree', v_building_a4, 'Appart 1')
  returning id into v_property_a4a;

  -- agent_a gère property_a1 et (temporairement) property_a4a -- PAS
  -- property_a2.
  insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
  values (v_org_a, v_property_a1, v_agent_a, v_admin_a);
  insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
  values (v_org_a, v_property_a4a, v_agent_a, v_admin_a);

  -- Assignation directe de agent_a à building_a4 (simule ce que create_
  -- building() aurait posé s'il en avait été le créateur -- ici posée
  -- explicitement par admin_a, la seule voie possible tant qu'aucun écran
  -- d'assignation dédié n'existe).
  insert into public.building_agent_assignments (organization_id, building_id, agent_id, assigned_by)
  values (v_org_a, v_building_a4, v_agent_a, v_admin_a);

  -- building_b1 (org_b), pour le test cross-org.
  perform pg_temp.act_as('authenticated', v_admin_b);
  insert into public.buildings (organization_id, name, country_code, city, neighborhood)
  values (v_org_b, 'Immeuble Test13c B1 (autre organisation)', 'BJ', 'Porto-Novo', 'Centre')
  returning id into v_building_b1;

  perform pg_temp.act_as_owner();

  create table pg_temp.fixtures as
  select
    v_org_a as org_a, v_admin_a as admin_a, v_agent_a as agent_a, v_comptable_a as comptable_a,
    v_org_b as org_b, v_admin_b as admin_b,
    v_building_a1 as building_a1, v_building_a2 as building_a2,
    v_building_a4 as building_a4, v_building_a5 as building_a5, v_building_a6 as building_a6,
    v_building_b1 as building_b1,
    v_property_a1 as property_a1, v_property_a2 as property_a2, v_property_a4a as property_a4a;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- Table auxiliaire pour les ids produits PENDANT le test (building_a3, créé
-- par le RPC en scénario 2 -- pas une fixture, doit être storée après coup
-- pour être réutilisée par les scénarios 3/5/8).
create table pg_temp.extra_ids (key text primary key, id uuid);
grant select, insert on pg_temp.extra_ids to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 1 — agent avec un logement dans A, aucun dans B, aucune
-- assignation directe à B -> voit A, pas B.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_a);

  perform pg_temp.check_id_visible(
    '1. agent voit building_a1 (logement géré à l''intérieur)',
    'buildings', f.building_a1, 1
  );
  perform pg_temp.check_id_visible(
    '1. agent NE voit PAS building_a2 (logement présent mais non géré, aucune assignation directe)',
    'buildings', f.building_a2, 0
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 2 — agent crée un immeuble vide via create_building() -> le voit
-- immédiatement (retour direct du RPC), puis le retrouve dans sa liste
-- après actualisation (nouvelle requête, même session).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_building_a3 public.buildings;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_a);

  select * into v_building_a3
  from public.create_building(f.org_a, 'Immeuble Test13c A3 (créé par agent, vide)', 'BJ', 'Cotonou', 'Fidjrosse', null, null);

  if v_building_a3.id is not null and v_building_a3.name = 'Immeuble Test13c A3 (créé par agent, vide)' then
    perform pg_temp.record('2. create_building() renvoie la ligne créée au créateur (RETURNING du RPC, pas soumis à buildings_select)', 'PASS');
  else
    perform pg_temp.record('2. create_building() renvoie la ligne créée au créateur (RETURNING du RPC, pas soumis à buildings_select)', 'FAIL', 'ligne non retournée ou incorrecte');
  end if;

  -- "Actualisation" = nouvelle requête SELECT, toujours dans la même
  -- session/JWT -- doit refléter l'auto-assignation posée par create_
  -- building() dans building_agent_assignments.
  perform pg_temp.check_id_visible(
    '2. agent retrouve l''immeuble vide qu''il vient de créer dans une SELECT séparée (actualisation)',
    'buildings', v_building_a3.id, 1
  );

  insert into pg_temp.extra_ids (key, id) values ('building_a3', v_building_a3.id);
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 3 — après déconnexion puis reconnexion, l'agent qui a créé cet
-- immeuble vide le voit toujours.
--
-- LIMITE DE CE SCRIPT : une vraie déconnexion/reconnexion (nouveau JWT émis
-- par GoTrue) ne peut pas être simulée depuis un script SQL autonome dans
-- une seule transaction. L'équivalent le plus proche : act_as_owner() purge
-- entièrement request.jwt.claims (retour à un contexte sans session), puis
-- act_as() ré-émet des claims frais pour agent_a -- exactement ce qu'un
-- nouveau login régénère côté GoTrue. Comme private.agent_building_scope()
-- est STABLE et ne lit que la table building_agent_assignments (persistée,
-- pas de cache de session), ce test couvre le risque réel : que l'accès
-- dépende par erreur d'un état transitoire de la requête précédente plutôt
-- que de la ligne building_agent_assignments elle-même.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_building_a3_id uuid;
begin
  select * into f from pg_temp.fixtures;
  select id into v_building_a3_id from pg_temp.extra_ids where key = 'building_a3';

  perform pg_temp.act_as_owner();
  perform pg_temp.act_as('authenticated', f.agent_a);

  perform pg_temp.check_id_visible(
    '3. agent voit toujours l''immeuble vide après purge + ré-émission des claims JWT (proxy de déconnexion/reconnexion)',
    'buildings', v_building_a3_id, 1
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 4 — agent qui perd son dernier logement dans un immeuble où il a
-- une assignation directe -> garde l'accès.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  -- Contrôle préalable : agent_a voit bien building_a4 avant la perte du
  -- logement (les deux branches OR sont vraies à ce stade).
  perform pg_temp.act_as('authenticated', f.agent_a);
  perform pg_temp.check_id_visible(
    '4. (préalable) agent voit building_a4 avant perte du logement géré',
    'buildings', f.building_a4, 1
  );

  perform pg_temp.act_as('authenticated', f.admin_a);
  delete from public.property_agent_assignments where property_id = f.property_a4a and agent_id = f.agent_a;

  perform pg_temp.act_as('authenticated', f.agent_a);
  perform pg_temp.check_id_visible(
    '4. agent garde l''accès à building_a4 après avoir perdu son dernier logement géré à l''intérieur (assignation directe restante)',
    'buildings', f.building_a4, 1
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 5 — admin et comptable voient tous les immeubles de leur
-- organisation, y compris les immeubles totalement vides.
--
-- Total attendu pour org_a à ce stade : building_a1, building_a2,
-- building_a4, building_a5, building_a6 (fixtures) + building_a3 (créé au
-- scénario 2) = 6.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_building_a3_id uuid;
begin
  select * into f from pg_temp.fixtures;
  select id into v_building_a3_id from pg_temp.extra_ids where key = 'building_a3';

  perform pg_temp.act_as('authenticated', f.admin_a);
  perform pg_temp.check_select_count('5. admin voit tous les immeubles de son organisation (6, y compris les immeubles vides)', 'buildings', f.org_a, 6);
  perform pg_temp.check_id_visible('5. admin voit spécifiquement l''immeuble totalement vide (building_a3)', 'buildings', v_building_a3_id, 1);
  perform pg_temp.check_id_visible('5. admin voit spécifiquement building_a2 (non géré par aucun agent)', 'buildings', f.building_a2, 1);

  perform pg_temp.act_as('authenticated', f.comptable_a);
  perform pg_temp.check_select_count('5. comptable voit tous les immeubles de son organisation (6, y compris les immeubles vides) -- lecture large inchangée', 'buildings', f.org_a, 6);
  perform pg_temp.check_id_visible('5. comptable voit spécifiquement l''immeuble totalement vide (building_a3)', 'buildings', v_building_a3_id, 1);
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 6 — agent hors périmètre qui tente un accès direct par id
-- (équivalent SQL de /buildings/[buildingId] -> getBuilding() ->
-- .eq("id", id).maybeSingle()) à un immeuble non assigné -> aucune ligne,
-- donc notFound() côté écran.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_a);

  perform pg_temp.check_id_visible(
    '6. accès direct par id connu à building_a2 (hors périmètre) -> 0 ligne, équivalent notFound()',
    'buildings', f.building_a2, 0
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 7 — agent hors périmètre -> ne peut pas modifier un immeuble
-- auquel il n'a aucun accès (agent a pourtant has_permission('buildings',
-- 'update') -- c'est bien le SCOPE qui doit bloquer ici, pas l'absence de
-- permission, même isolation que module12p).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_name text;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  update public.buildings set name = 'Ne doit pas passer' where id = f.building_a2;

  perform pg_temp.act_as_owner();
  select name into v_name from public.buildings where id = f.building_a2;
  if v_name <> 'Ne doit pas passer' then
    perform pg_temp.record('7. agent NE modifie PAS un immeuble hors périmètre, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('7. agent NE modifie PAS un immeuble hors périmètre, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 8 — agent hors périmètre -> ne peut pas supprimer un immeuble
-- auquel il n'a aucun accès. building_a5 est vide (aucun logement) pour
-- isoler le blocage RLS de la contrainte FK restrict (properties_building_
-- org_fk), qui ne s'appliquerait de toute façon pas ici.
--
-- PAS de contrôle positif "agent supprime un immeuble DANS son périmètre" :
-- structurellement impossible à écrire pour un agent non admin/comptable.
-- Être dans le périmètre d'un agent exige une ligne property.building_id
-- (branche "via logement") ou building_agent_assignments (branche directe)
-- référençant l'immeuble -- et cette même ligne bloque ensuite le DELETE
-- physique via ON DELETE RESTRICT (properties_building_org_fk /
-- building_agent_assignments_building_org_fk). Un agent ne peut donc
-- JAMAIS réellement supprimer un immeuble, même dans son propre périmètre
-- -- comportement correct et volontaire des deux FK restrict (même
-- convention que "supprimer un immeuble qui a encore des biens rattachés
-- doit échouer explicitement", Module 13), pas un défaut de cette
-- migration. Contrôle positif à la place : admin_a supprime building_a6
-- (vide, aucune référence d'aucune sorte) -- vérifie que buildings_delete
-- fonctionne toujours normalement quand scope ET absence de référence
-- sont réunis.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.agent_a);
  delete from public.buildings where id = f.building_a5;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.buildings where id = f.building_a5;
  if v_count = 1 then
    perform pg_temp.record('8. agent NE supprime PAS un immeuble vide hors périmètre, même par id direct (DELETE)', 'PASS');
  else
    perform pg_temp.record('8. agent NE supprime PAS un immeuble vide hors périmètre, même par id direct (DELETE)', 'FAIL', 'ligne supprimée à tort');
  end if;

  perform pg_temp.act_as('authenticated', f.admin_a);
  delete from public.buildings where id = f.building_a6;

  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.buildings where id = f.building_a6;
  if v_count = 0 then
    perform pg_temp.record('8. (contrôle positif) admin supprime un immeuble sans aucune référence (DELETE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('8. (contrôle positif) admin supprime un immeuble sans aucune référence (DELETE) -> autorisé', 'FAIL', 'ligne non supprimée');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 9 — create_building() avec organization_id différent de
-- current_org_id() -> doit échouer (organization_mismatch).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.admin_a);

  begin
    perform public.create_building(f.org_b, 'Ne doit pas être créé', 'BJ', 'Cotonou', 'Fidjrosse', null, null);
    perform pg_temp.record('9. create_building() avec organization_id d''une autre organisation -> échoue', 'FAIL', 'succès inattendu');
  exception when others then
    if sqlstate = 'P0001' and sqlerrm like '%Organisation invalide%' then
      perform pg_temp.record('9. create_building() avec organization_id d''une autre organisation -> échoue', 'PASS');
    else
      perform pg_temp.record('9. create_building() avec organization_id d''une autre organisation -> échoue', 'FAIL', 'exception inattendue: ' || sqlerrm);
    end if;
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- SCÉNARIO 10 — agent d'une organisation ne peut JAMAIS accéder à un
-- immeuble d'une autre organisation, même en connaissant directement son
-- building_id.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.agent_a);

  perform pg_temp.check_id_visible(
    '10. agent de org_a ne voit jamais building_b1 (org_b), même id connu directement',
    'buildings', f.building_b1, 0
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- RÉSUMÉ.
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
