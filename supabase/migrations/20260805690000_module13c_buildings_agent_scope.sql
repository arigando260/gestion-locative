-- ============================================================================
-- MODULE 13c — Branchement du scope agent sur buildings (Phase 4, suite
-- module immeubles -- correctif de sécurité).
--
-- DIAGNOSTIC (posé avant cette migration, non répété en détail ici) : les 4
-- policies buildings (Module 13) ne vérifient ni assignation directe ni
-- logement géré -- un agent au périmètre restreint (property_agent_
-- assignments, Module 12o/12p) voit et peut modifier/supprimer TOUS les
-- immeubles de l'organisation, pas seulement ceux liés à ses biens assignés.
-- properties/leases/maintenance_tickets/etc. ont déjà ce filtre depuis le
-- Module 12p ; buildings avait été oublié lors du Module 13.
--
-- RÈGLE MÉTIER (validée) : un immeuble existe indépendamment de ses
-- logements. Un agent y a accès s'il y est directement assigné (notamment
-- comme créateur), OU s'il gère au moins un logement à l'intérieur.
-- L'absence de logement ne doit JAMAIS, à elle seule, retirer l'accès --
-- ni à la création (immeuble encore vide), ni après coup (agent qui perd
-- son dernier logement dans un immeuble où il a une assignation directe
-- garde l'accès, l'assignation directe et le scope "via logement" sont deux
-- branches indépendantes d'un OR, aucune ne revoke l'autre).
--
-- Trois pièces, dans l'ordre de dépendance :
--   1. building_agent_assignments -- même patron que property_agent_
--      assignments (Module 12o) : assignation directe, posée uniquement à
--      la création (pas d'écran de gestion pour l'instant -- brique
--      ultérieure si besoin, même séquencement que 12o -> 12p pour
--      properties).
--   2. private.agent_building_scope(building_id) -- combine assignation
--      directe ET jointure vers properties.building_id (agent_property_
--      scope() par logement rattaché). admin/comptable toujours vrai,
--      vérifié explicitement en plus des deux branches ci-dessus : un
--      immeuble sans AUCUN logement n'a par construction aucune ligne
--      properties à joindre, donc la branche "via logement" ne peut jamais
--      être vraie pour lui -- sans le check direct du rôle, un immeuble vide
--      serait invisible même pour admin/comptable.
--   3. Application aux policies buildings_select/update/delete (USING, et
--      WITH CHECK pour update). buildings_insert INCHANGÉE, volontairement
--      -- même piège que properties_insert (Module 12p) : au moment de
--      l'INSERT la ligne n'existe pas encore, donc agent_building_scope(id)
--      y serait toujours fausse, ce qui retirerait silencieusement le droit
--      buildings:create à tout agent.
--
-- Corollaire du point 3 (piège RETURNING/RLS, déjà rencontré et documenté au
-- Module 12q pour create_property()) : `insert into buildings ... returning
-- *` échouerait pour un agent dès que buildings_select dépend de agent_
-- building_scope(), car RETURNING est filtré par la policy SELECT et la
-- ligne fraîche n'a par construction aucune assignation au moment où
-- RETURNING est évalué. Solution identique : create_building(), fonction
-- SECURITY DEFINER qui pose l'auto-assignation AVANT son propre `returning *
-- into`, jamais soumise elle-même au RETURNING/RLS de la table sous-jacente.
-- data/buildings.ts (hors périmètre SQL de cette migration) devra appeler ce
-- RPC au lieu d'un insert direct -- même changement que createProperty() /
-- create_property() (Module 12q).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE building_agent_assignments -- même patron que property_agent_
--    assignments (Module 12o, comparé caractère pour caractère avant
--    d'écrire ce qui suit).
-- ----------------------------------------------------------------------------

create table public.building_agent_assignments (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  building_id     uuid not null,
  agent_id        uuid not null,
  assigned_by     uuid not null references public.profiles (id) on delete restrict,
  assigned_at     timestamptz not null default now(),

  constraint building_agent_assignments_unique unique (building_id, agent_id),

  constraint building_agent_assignments_building_org_fk
    foreign key (organization_id, building_id)
    references public.buildings (organization_id, id)
    on delete restrict,

  constraint building_agent_assignments_agent_org_fk
    foreign key (organization_id, agent_id)
    references public.profiles (organization_id, id)
    on delete restrict
);

create index building_agent_assignments_organization_id_idx on public.building_agent_assignments (organization_id);
create index building_agent_assignments_building_id_idx on public.building_agent_assignments (building_id);
create index building_agent_assignments_agent_id_idx on public.building_agent_assignments (agent_id);

comment on table public.building_agent_assignments is
  'Assignation directe d''un agent à un immeuble -- indépendante des logements qu''il gère à l''intérieur (property_agent_assignments, Module 12o). Combinée en OR avec le scope "via logement géré" dans private.agent_building_scope(). Posée uniquement à la création (create_building()) pour l''instant, pas d''écran de gestion dédié.';

alter table public.building_agent_assignments enable row level security;

-- Lecture : tout membre interne de l'organisation, sans permission dédiée --
-- même patron que property_agent_assignments_select (Module 12o).
create policy building_agent_assignments_select on public.building_agent_assignments
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
  );

create policy building_agent_assignments_insert on public.building_agent_assignments
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('building_agent_assignments', 'create')
    and assigned_by = auth.uid()
  );

create policy building_agent_assignments_delete on public.building_agent_assignments
  for delete
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('building_agent_assignments', 'delete')
  );

-- Pas de policy UPDATE -- une assignation existe ou n'existe pas, même
-- raisonnement que property_agent_assignments (Module 12o).

-- ----------------------------------------------------------------------------
-- 2. CATALOGUE DE PERMISSIONS -- building_agent_assignments:create/delete.
--
-- Volontairement absentes des listes explicites agent/comptable dans
-- seed_default_roles_for_org (Module 13) : cette fonction énumère leurs
-- permissions une par une (pas un blanket comme admin), donc une nouvelle
-- entrée catalogue ne leur est jamais accordée automatiquement -- aucune
-- redéfinition de seed_default_roles_for_org n'est nécessaire ici. "Assigner
-- un agent à un immeuble" reste une décision admin par construction, même
-- raisonnement que property_agent_assignments (Module 12o).
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('building_agent_assignments', 'create', 'Assigner un agent à un immeuble'),
  ('building_agent_assignments', 'delete', 'Retirer l''assignation d''un agent à un immeuble');

-- Backfill pour les organisations déjà créées (admin uniquement -- son seed
-- prend tout le catalogue automatiquement pour les futures organisations,
-- mais une organisation existante n'hérite pas des nouvelles lignes) -- même
-- patron que le backfill property_agent_assignments (Module 12o).
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'building_agent_assignments'
where r.code = 'admin'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 3. FONCTION DE SCOPE -- private.agent_building_scope(building_id).
-- ----------------------------------------------------------------------------

create or replace function private.agent_building_scope(p_building_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1
      from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid()
        and r.code in ('admin', 'comptable')
    )
    or exists (
      select 1
      from public.building_agent_assignments baa
      where baa.building_id = p_building_id
        and baa.agent_id = auth.uid()
    )
    or exists (
      select 1
      from public.properties p
      where p.building_id = p_building_id
        and private.agent_property_scope(p.id)
    )
$$;

comment on function private.agent_building_scope is
  'true si l''appelant a le rôle admin ou comptable (accès non restreint), ou si un agent est directement assigné à cet immeuble (building_agent_assignments), ou s''il gère au moins un logement rattaché (agent_property_scope() vrai pour au moins une ligne properties.building_id = p_building_id). Un immeuble sans aucun logement reste visible pour admin/comptable via la première branche -- la troisième ne peut jamais matcher pour lui, par construction. À combiner en AND avec is_internal()/has_permission() déjà posés sur chaque policy, jamais pour les remplacer -- même convention que agent_property_scope (Module 12o).';

-- ----------------------------------------------------------------------------
-- 4. APPLICATION AUX POLICIES buildings -- select/update/delete uniquement.
--    buildings_insert INCHANGÉE (voir en-tête -- même circularité que
--    properties_insert, Module 12p).
-- ----------------------------------------------------------------------------

alter policy buildings_select on public.buildings
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'read')
    and private.agent_building_scope(id)
  );

alter policy buildings_update on public.buildings
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'update')
    and private.agent_building_scope(id)
  )
  with check (
    organization_id = private.current_org_id()
    and private.agent_building_scope(id)
  );

alter policy buildings_delete on public.buildings
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'delete')
    and private.agent_building_scope(id)
  );

-- ----------------------------------------------------------------------------
-- 5. RPC public.create_building() -- contourne le piège RETURNING/RLS
--    (même solution que create_property(), Module 12q) et auto-assigne
--    l'agent créateur (même solution que create_property(), Module 13).
--
-- has_permission et organization_id revérifiés explicitement ici : SECURITY
-- DEFINER élève les privilèges pour ACCÉDER à la table sans RLS, ça ne
-- dispense jamais l'appelant du droit métier lui-même -- exactement ce que
-- buildings_insert fait déjà aujourd'hui, jamais contourné silencieusement.
--
-- Auto-assignation réservée à un agent "pur" (rôle agent, ni admin ni
-- comptable en plus) -- cohérent avec agent_building_scope()/agent_property_
-- scope() où le rôle le plus large gagne déjà en cas de cumul.
-- ----------------------------------------------------------------------------

create or replace function public.create_building(
  p_organization_id    uuid,
  p_name               text,
  p_country_code       text,
  p_city               text,
  p_neighborhood       text,
  p_address_complement text,
  p_floors_count       integer
)
returns public.buildings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_building      public.buildings;
  v_is_agent      boolean;
  v_is_broad_role boolean;
begin
  if not private.has_permission('buildings', 'create') then
    raise exception 'Vous n''avez pas la permission de créer un immeuble'
      using detail = 'create_building.permission_denied', errcode = 'P0001';
  end if;

  if p_organization_id is distinct from private.current_org_id() then
    raise exception 'Organisation invalide'
      using detail = 'create_building.organization_mismatch', errcode = 'P0001';
  end if;

  insert into public.buildings (
    organization_id, name, country_code, city, neighborhood,
    address_complement, floors_count
  )
  values (
    p_organization_id, p_name, p_country_code, p_city, p_neighborhood,
    p_address_complement, p_floors_count
  )
  returning * into v_building;

  select
    exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid() and r.code = 'agent'
    ),
    exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid() and r.code in ('admin', 'comptable')
    )
  into v_is_agent, v_is_broad_role;

  if v_is_agent and not v_is_broad_role then
    insert into public.building_agent_assignments (organization_id, building_id, agent_id, assigned_by)
    values (p_organization_id, v_building.id, auth.uid(), auth.uid());
  end if;

  return v_building;
end;
$$;

-- Même leçon que create_property() (Module 12q) : un ALTER DEFAULT
-- PRIVILEGES du projet regrante EXECUTE à anon directement sur toute
-- nouvelle fonction du schéma public créée par postgres -- un grant à
-- authenticated seul ne suffit pas à l'exclure, il faut explicitement
-- révoquer public ET anon.
revoke execute on function public.create_building(uuid, text, text, text, text, text, integer) from public;
revoke execute on function public.create_building(uuid, text, text, text, text, text, integer) from anon;
grant execute on function public.create_building(uuid, text, text, text, text, text, integer) to authenticated;
