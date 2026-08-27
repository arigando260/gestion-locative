-- ============================================================================
-- MODULE 13 — Regroupement de biens par immeuble (Phase 4, sous-module 1).
--
-- Table buildings : porte l'adresse structurée (country_code/city/
-- neighborhood/address_complement) quand plusieurs biens partagent le même
-- bâtiment physique. Même patron d'adresse que properties (Module 12c) --
-- mêmes colonnes, même FK vers countries(code) ON DELETE RESTRICT.
--
-- properties.building_id nullable : le rattachement est optionnel, un bien
-- autonome (maison individuelle, etc.) garde sa propre adresse. FK composite
-- (organization_id, building_id) -> buildings(organization_id, id), même
-- garde-fou anti cross-organisation que toutes les FK composites existantes
-- vers properties (property_agent_assignments, Module 12o ; leases, Module 3 ;
-- etc.) -- nécessite la contrainte unique buildings_org_id_key, même rôle que
-- properties_org_id_key.
--
-- CHECK properties_building_address_exclusive : source d'adresse UNIQUE et
-- non ambiguë par construction -- un bien rattaché à un immeuble ne peut pas
-- porter en même temps sa propre country_code/city/neighborhood (l'adresse
-- viendrait de deux endroits à la fois, sans règle de priorité définie).
-- address_complement du bien reste toujours utilisable dans les deux cas :
-- adresse libre si bien autonome, identifiant d'unité ("Appartement A1, 2e
-- étage") si rattaché -- ce n'est pas un champ d'adresse au sens de cette
-- contrainte, volontairement absent de son périmètre.
--
-- ON DELETE RESTRICT sur properties.building_id : même convention que toutes
-- les FK composites existantes vers properties (jamais de suppression
-- silencieuse d'un parent référencé) -- supprimer un immeuble qui a encore
-- des biens rattachés doit échouer explicitement, pas les détacher.
--
-- private.resolve_property_address() : ne vérifie AUCUNE permission --
-- appelée uniquement depuis du code qui a déjà lu la ligne properties
-- concernée via le RLS normal (properties_select). SECURITY DEFINER ici sert
-- seulement à traverser la FK vers buildings sans dépendre d'une deuxième
-- policy SELECT sur buildings pour l'appelant (même schéma d'accès qu'un
-- simple JOIN aurait donné si l'appelant avait aussi accès direct à
-- buildings, ce qui est déjà le cas pour tout membre interne -- cette
-- fonction est un raccourci de présentation, pas une élévation de droit).
--
-- Permissions 'buildings' : même partage que 'properties' (Module 2) --
-- admin CRUD complet (automatique, blanket), agent CRUD complet (regroupe
-- des biens qu'il gère déjà en autonomie), comptable lecture seule. Même
-- domaine opérationnel que properties, pas de raison de le traiter comme une
-- décision structurelle réservée à admin (contrairement à
-- property_agent_assignments, Module 12o).
--
-- create_property() : DROP explicite puis recréation (pas un simple CREATE
-- OR REPLACE) -- ajouter un paramètre en fin de liste change le type de
-- signature de la fonction, donc son identité pg_proc ; un CREATE OR REPLACE
-- avec une liste de paramètres différente crée une DEUXIÈME fonction
-- surchargée au lieu de remplacer l'existante, ce qui aurait laissé les deux
-- versions coexister et rendu l'appel RPC ambigu côté PostgREST (mêmes
-- symptômes que le piège RETURNING/RLS déjà rencontré au Module 12q, cette
-- fois côté signature plutôt que timing).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE buildings.
-- ----------------------------------------------------------------------------

create table public.buildings (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations (id) on delete cascade,
  name               text not null,
  country_code       text references public.countries (code) on delete restrict,
  city               text,
  neighborhood       text,
  address_complement text,
  floors_count       integer check (floors_count is null or floors_count >= 0),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint buildings_org_id_key unique (organization_id, id)
);

create index buildings_organization_id_idx on public.buildings (organization_id);

create trigger trg_buildings_updated_at
  before update on public.buildings
  for each row execute function private.set_updated_at();

comment on table public.buildings is
  'Regroupement optionnel de plusieurs biens sous un même bâtiment physique. Porte l''adresse structurée quand elle est partagée -- voir properties_building_address_exclusive sur properties.';

-- ----------------------------------------------------------------------------
-- 2. properties.building_id -- rattachement optionnel.
-- ----------------------------------------------------------------------------

alter table public.properties
  add column building_id uuid;

alter table public.properties
  add constraint properties_building_org_fk
    foreign key (organization_id, building_id)
    references public.buildings (organization_id, id)
    on delete restrict;

alter table public.properties
  add constraint properties_building_address_exclusive
    check (
      building_id is null
      or (country_code is null and city is null and neighborhood is null)
    );

create index properties_building_id_idx on public.properties (building_id);

-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY -- patron identique à staff_invitations (Module 12m).
-- ----------------------------------------------------------------------------

alter table public.buildings enable row level security;

create policy buildings_select on public.buildings
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'read')
  );

create policy buildings_insert on public.buildings
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'create')
  );

create policy buildings_update on public.buildings
  for update
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'update')
  )
  with check (organization_id = private.current_org_id());

create policy buildings_delete on public.buildings
  for delete
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('buildings', 'delete')
  );

-- ----------------------------------------------------------------------------
-- 4. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('buildings', 'create', 'Créer un immeuble'),
  ('buildings', 'read',   'Consulter les immeubles'),
  ('buildings', 'update', 'Modifier un immeuble'),
  ('buildings', 'delete', 'Supprimer un immeuble');

-- Étend le seed pour les FUTURES organisations. Redéfinition complète de la
-- fonction (dernière version : remove_reservations_d_followup_seed_default_
-- roles.sql), même convention que chaque module qui a ajouté un rôle/
-- ressource à ce seed -- pas de diff partiel possible sur un corps de
-- fonction.
create or replace function private.seed_default_roles_for_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id     uuid;
  v_agent_id     uuid;
  v_comptable_id uuid;
begin
  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'admin', 'Administrateur', 'Accès complet à l''organisation', true)
  returning id into v_admin_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'agent', 'Gestionnaire / Agent', 'Gestion opérationnelle des locataires', true)
  returning id into v_agent_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'comptable', 'Comptable', 'Accès en lecture, périmètre financier à venir', true)
  returning id into v_comptable_id;

  insert into public.role_permissions (role_id, resource, action)
  select v_admin_id, resource, action from public.permissions;

  insert into public.role_permissions (role_id, resource, action) values
    (v_agent_id, 'tenant_accounts', 'create'),
    (v_agent_id, 'tenant_accounts', 'read'),
    (v_agent_id, 'tenant_accounts', 'update'),
    (v_agent_id, 'users', 'read'),
    (v_agent_id, 'roles', 'read'),
    (v_agent_id, 'properties', 'create'),
    (v_agent_id, 'properties', 'read'),
    (v_agent_id, 'properties', 'update'),
    (v_agent_id, 'properties', 'delete'),
    (v_agent_id, 'buildings', 'create'),
    (v_agent_id, 'buildings', 'read'),
    (v_agent_id, 'buildings', 'update'),
    (v_agent_id, 'buildings', 'delete'),
    (v_agent_id, 'leases', 'create'),
    (v_agent_id, 'leases', 'read'),
    (v_agent_id, 'leases', 'update'),
    (v_agent_id, 'leases', 'delete'),
    (v_agent_id, 'payment_schedules', 'create'),
    (v_agent_id, 'payment_schedules', 'read'),
    (v_agent_id, 'payment_schedules', 'update'),
    (v_agent_id, 'payment_schedules', 'delete'),
    (v_agent_id, 'payments', 'create'),
    (v_agent_id, 'payments', 'read'),
    (v_agent_id, 'payments', 'update'),
    (v_agent_id, 'payments', 'delete'),
    (v_agent_id, 'deposit_ledger', 'create'),
    (v_agent_id, 'deposit_ledger', 'read'),
    (v_agent_id, 'property_inspections', 'create'),
    (v_agent_id, 'property_inspections', 'read'),
    (v_agent_id, 'property_inspections', 'update'),
    (v_agent_id, 'property_inspections', 'delete'),
    (v_agent_id, 'maintenance_tickets', 'create'),
    (v_agent_id, 'maintenance_tickets', 'read'),
    (v_agent_id, 'maintenance_tickets', 'update'),
    (v_agent_id, 'maintenance_tickets', 'delete'),
    (v_agent_id, 'lease_termination_requests', 'create'),
    (v_agent_id, 'lease_termination_requests', 'read'),
    (v_agent_id, 'lease_termination_requests', 'update'),
    (v_agent_id, 'payment_receipts', 'read'),
    (v_agent_id, 'payment_receipts', 'update'),
    (v_agent_id, 'schedule_invoices', 'create'),
    (v_agent_id, 'schedule_invoices', 'read'),
    (v_agent_id, 'lease_contracts', 'create'),
    (v_agent_id, 'lease_contracts', 'read');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read'),
    (v_comptable_id, 'buildings', 'read'),
    (v_comptable_id, 'leases', 'read'),
    (v_comptable_id, 'payment_schedules', 'read'),
    (v_comptable_id, 'payments', 'read'),
    (v_comptable_id, 'payments', 'create'),
    (v_comptable_id, 'deposit_ledger', 'read'),
    (v_comptable_id, 'property_inspections', 'read'),
    (v_comptable_id, 'maintenance_tickets', 'read'),
    (v_comptable_id, 'lease_termination_requests', 'read'),
    (v_comptable_id, 'payment_receipts', 'read'),
    (v_comptable_id, 'payment_receipts', 'update'),
    (v_comptable_id, 'schedule_invoices', 'read'),
    (v_comptable_id, 'lease_contracts', 'read');

  return new;
end;
$$;

-- Backfill pour les organisations déjà créées -- même patron que le backfill
-- properties (Module 2) et property_agent_assignments (Module 12o) : les
-- permissions sont matérialisées à la création de l'organisation, une
-- organisation existante n'hérite pas automatiquement des nouvelles lignes
-- du catalogue.
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'buildings'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('buildings', 'create'),
  ('buildings', 'read'),
  ('buildings', 'update'),
  ('buildings', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'buildings', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 5. private.resolve_property_address() -- adresse effective d'un bien.
-- ----------------------------------------------------------------------------

create or replace function private.resolve_property_address(p_property_id uuid)
returns table (
  formatted_address  text,
  country_code       text,
  city               text,
  neighborhood       text,
  address_complement text,
  unit_complement    text,
  building_id        uuid,
  building_name      text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_property public.properties;
  v_building public.buildings;
  v_location text;
begin
  select * into v_property from public.properties p where p.id = p_property_id;

  if not found then
    return;
  end if;

  if v_property.building_id is not null then
    select * into v_building from public.buildings b where b.id = v_property.building_id;

    country_code       := v_building.country_code;
    city               := v_building.city;
    neighborhood       := v_building.neighborhood;
    address_complement := v_building.address_complement;
    unit_complement    := v_property.address_complement;
    building_id        := v_building.id;
    building_name      := v_building.name;

    v_location := concat_ws(', ', nullif(v_building.neighborhood, ''), nullif(v_building.city, ''));

    if v_location <> '' and v_building.address_complement is not null and v_building.address_complement <> '' then
      formatted_address := v_location || ' — ' || v_building.address_complement;
    else
      formatted_address := nullif(v_location, '');
      formatted_address := coalesce(formatted_address, v_building.address_complement, '—');
    end if;

    if v_property.address_complement is not null and v_property.address_complement <> '' then
      formatted_address := formatted_address || ', ' || v_property.address_complement;
    end if;
  else
    country_code       := v_property.country_code;
    city               := v_property.city;
    neighborhood       := v_property.neighborhood;
    address_complement := v_property.address_complement;
    unit_complement    := null;
    building_id        := null;
    building_name      := null;

    v_location := concat_ws(', ', nullif(v_property.neighborhood, ''), nullif(v_property.city, ''));

    if v_location <> '' and v_property.address_complement is not null and v_property.address_complement <> '' then
      formatted_address := v_location || ' — ' || v_property.address_complement;
    else
      formatted_address := nullif(v_location, '');
      formatted_address := coalesce(formatted_address, v_property.address_complement, '—');
    end if;
  end if;

  return next;
end;
$$;

comment on function private.resolve_property_address is
  'Adresse effective d''un bien (propre ou héritée de son immeuble). Ne vérifie aucune permission : appelée uniquement depuis du code qui a déjà lu la ligne properties concernée via properties_select -- pas un point d''entrée RPC indépendant, jamais exposée directement à un client sans ce filtrage préalable.';

-- ----------------------------------------------------------------------------
-- 6. create_property() -- ajout de p_building_id.
-- ----------------------------------------------------------------------------

drop function public.create_property(uuid, text, text, text, text, text, numeric, text);

create function public.create_property(
  p_organization_id   uuid,
  p_name               text,
  p_country_code       text,
  p_city               text,
  p_neighborhood       text,
  p_address_complement text,
  p_price              numeric,
  p_location_type      text,
  p_building_id        uuid default null
)
returns public.properties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_property      public.properties;
  v_is_agent      boolean;
  v_is_broad_role boolean;
begin
  if not private.has_permission('properties', 'create') then
    raise exception 'Vous n''avez pas la permission de créer un bien'
      using detail = 'create_property.permission_denied', errcode = 'P0001';
  end if;

  if p_organization_id is distinct from private.current_org_id() then
    raise exception 'Organisation invalide'
      using detail = 'create_property.organization_mismatch', errcode = 'P0001';
  end if;

  if p_building_id is not null then
    if not exists (
      select 1 from public.buildings b
      where b.id = p_building_id
        and b.organization_id = p_organization_id
    ) then
      raise exception 'Immeuble invalide'
        using detail = 'create_property.building_mismatch', errcode = 'P0001';
    end if;

    -- Jamais laisser l'appelant contourner properties_building_address_exclusive :
    -- un bien rattaché à un immeuble ne porte pas sa propre country_code/city/
    -- neighborhood, quoi que le client ait transmis.
    p_country_code := null;
    p_city := null;
    p_neighborhood := null;
  end if;

  insert into public.properties (
    organization_id, name, country_code, city, neighborhood,
    address_complement, price, location_type, building_id
  )
  values (
    p_organization_id, p_name, p_country_code, p_city, p_neighborhood,
    p_address_complement, p_price, p_location_type, p_building_id
  )
  returning * into v_property;

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
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (p_organization_id, v_property.id, auth.uid(), auth.uid());
  end if;

  return v_property;
end;
$$;

revoke execute on function public.create_property(uuid, text, text, text, text, text, numeric, text, uuid) from public;
revoke execute on function public.create_property(uuid, text, text, text, text, text, numeric, text, uuid) from anon;
grant execute on function public.create_property(uuid, text, text, text, text, text, numeric, text, uuid) to authenticated;
