-- ============================================================================
-- MODULE 2 — PROPERTY / PROPERTY_TYPE
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PROPERTY_TYPES — catalogue configurable, global ou par organisation.
-- ----------------------------------------------------------------------------

create table public.property_types (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations (id) on delete cascade,
  code            text not null,
  name            text not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

comment on table public.property_types is
  'Types de location configurables. organization_id NULL = type global partagé par toutes les organisations ; renseigné = type personnalisé propre à une organisation.';

create unique index property_types_global_code_key
  on public.property_types (code)
  where organization_id is null;

create unique index property_types_org_code_key
  on public.property_types (organization_id, code)
  where organization_id is not null;

create index property_types_organization_id_idx
  on public.property_types (organization_id);

create trigger trg_property_types_updated_at
  before update on public.property_types
  for each row execute function private.set_updated_at();

-- Empêche la collision de code entre un type global et un type personnalisé
-- (dans les deux sens), pour éviter toute ambiguïté d'affichage/résolution.
create or replace function private.prevent_property_type_code_collision()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organization_id is not null then
    if exists (
      select 1 from public.property_types pt
      where pt.organization_id is null
        and pt.code = new.code
        and pt.id is distinct from new.id
    ) then
      raise exception 'Le code "%" est déjà utilisé par un type global', new.code;
    end if;
  else
    if exists (
      select 1 from public.property_types pt
      where pt.organization_id is not null
        and pt.code = new.code
        and pt.id is distinct from new.id
    ) then
      raise exception 'Le code "%" est déjà utilisé par un type personnalisé d''une organisation', new.code;
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_property_types_prevent_code_collision
  before insert or update of code, organization_id on public.property_types
  for each row execute function private.prevent_property_type_code_collision();

-- Seed des 3 types globaux de départ (passe par le trigger ci-dessus,
-- sans collision possible puisque la table est vide à ce stade).
insert into public.property_types (code, name) values
  ('longue_duree',   'Longue durée'),
  ('meuble_simple',  'Meublé simple'),
  ('courte_duree',   'Courte durée');

-- ----------------------------------------------------------------------------
-- 2. PROPERTIES — biens immobiliers, un par organisation.
-- ----------------------------------------------------------------------------

create table public.properties (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations (id) on delete cascade,
  name               text not null,
  address            text not null,
  status             text not null default 'disponible'
                        check (status in ('disponible', 'occupe', 'en_travaux')),
  price              numeric(12, 2) not null check (price >= 0),
  location_type      text not null,
  -- Référence future vers ExternalOwner (table non construite). Pas de FK
  -- pour ne pas bloquer l'architecture ; simple pointeur textuel pour l'instant.
  external_owner_id  text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

comment on table public.properties is
  'Biens immobiliers d''une organisation. location_type validé par trigger contre property_types (global ou propre à l''organisation).';

create index properties_organization_id_idx on public.properties (organization_id);
create index properties_location_type_idx on public.properties (location_type);

create trigger trg_properties_updated_at
  before update on public.properties
  for each row execute function private.set_updated_at();

create trigger trg_properties_prevent_org_change
  before update on public.properties
  for each row execute function private.prevent_org_change();

-- Validation de location_type : équivalent fonctionnel d'une FK, en trigger
-- car une FK composite (organization_id, code) ne peut pas matcher les lignes
-- globales (organization_id IS NULL) puisque properties.organization_id n'est
-- jamais NULL.
create or replace function private.validate_property_location_type()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.property_types pt
    where pt.code = new.location_type
      and (pt.organization_id is null or pt.organization_id = new.organization_id)
  ) then
    raise exception 'location_type invalide: % (aucun PropertyType visible pour cette organisation)', new.location_type;
  end if;
  return new;
end;
$$;

create trigger trg_properties_validate_location_type
  before insert or update of location_type, organization_id on public.properties
  for each row execute function private.validate_property_location_type();

-- ----------------------------------------------------------------------------
-- 3. CATALOGUE DE PERMISSIONS — extension pour 'properties'.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('properties', 'create', 'Créer un bien immobilier'),
  ('properties', 'read',   'Consulter les biens immobiliers'),
  ('properties', 'update', 'Modifier un bien immobilier'),
  ('properties', 'delete', 'Supprimer un bien immobilier');

-- Étend le seed pour les FUTURES organisations : agent (Gestionnaire) obtient
-- le CRUD complet sur properties, comptable la lecture seule. Admin obtient
-- automatiquement 'properties' via son insert générique (select * from permissions).
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
    (v_agent_id, 'properties', 'delete');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read');

  return new;
end;
$$;

-- Backfill pour les organisations déjà créées (ex: "Agence Demo") : les
-- permissions sont matérialisées dans role_permissions à la création de
-- l'organisation, donc une organisation existante n'hérite pas automatiquement
-- des nouvelles lignes du catalogue.
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'properties'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('properties', 'create'),
  ('properties', 'read'),
  ('properties', 'update'),
  ('properties', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'properties', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.property_types enable row level security;
alter table public.properties     enable row level security;

-- property_types : visible si global ou propre à l'organisation courante,
-- réservé aux comptes internes (un compte tenant ne doit pas voir Property
-- ni son catalogue de types pour l'instant).
create policy property_types_select on public.property_types
  for select
  using (
    (organization_id is null or organization_id = private.current_org_id())
    and private.is_internal()
  );

-- properties : lecture ouverte à tout membre interne de l'organisation
-- (comme organizations_select / roles_select), écriture gated par permission.
-- private.is_internal() exclut explicitement les comptes tenant, car
-- current_org_id() résout aussi l'organisation pour tenant_accounts.
create policy properties_select on public.properties
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
  );

create policy properties_insert on public.properties
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('properties', 'create')
  );

create policy properties_update on public.properties
  for update
  using (
    organization_id = private.current_org_id()
    and private.has_permission('properties', 'update')
  )
  with check (organization_id = private.current_org_id());

create policy properties_delete on public.properties
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('properties', 'delete')
  );
