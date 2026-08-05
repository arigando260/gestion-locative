-- ============================================================================
-- MODULE 3 — LEASE (contrat de location longue durée / meublé simple)
-- ============================================================================

-- Nécessaire pour la FK composite (organization_id, property_id) -> properties.
-- Absente du Module 2 (property_types.organization_id est nullable, properties
-- ne l'est pas : rien ne s'y opposait, juste pas encore fait).
alter table public.properties
  add constraint properties_org_id_key unique (organization_id, id);

create table public.leases (
  id                       uuid primary key default gen_random_uuid(),
  organization_id          uuid not null references public.organizations (id) on delete restrict,
  property_id              uuid not null,
  tenant_account_id        uuid not null,
  start_date               date not null,
  end_date                 date,
  rent_amount              numeric(12, 2) not null check (rent_amount >= 0),
  payment_frequency        text not null
                              check (payment_frequency in ('mensuel', 'trimestriel', 'semestriel', 'annuel')),
  security_deposit_amount  numeric(12, 2) not null check (security_deposit_amount >= 0),
  utility_deposit_amount   numeric(12, 2) check (utility_deposit_amount >= 0),
  status                   text not null default 'actif'
                              check (status in ('actif', 'termine', 'resilie')),
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint leases_end_after_start
    check (end_date is null or end_date >= start_date),

  -- Garantit que le bien appartient à la même organisation que le contrat.
  -- restrict (pas cascade) : on ne supprime jamais silencieusement l'historique
  -- contractuel via la suppression d'un bien.
  constraint leases_property_org_fk
    foreign key (organization_id, property_id)
    references public.properties (organization_id, id)
    on delete restrict,

  -- Garantit que le locataire appartient à la même organisation que le contrat.
  -- restrict pour la même raison : historique contractuel jamais effacé
  -- silencieusement par la suppression d'un tenant_account.
  constraint leases_tenant_org_fk
    foreign key (organization_id, tenant_account_id)
    references public.tenant_accounts (organization_id, id)
    on delete restrict
);

comment on table public.leases is
  'Contrats de location longue durée / meublé simple. Un bien ne peut avoir qu''un seul contrat "actif" à la fois (index partiel unique).';

-- Un bien ne doit pas avoir deux contrats actifs simultanément.
create unique index leases_one_active_per_property
  on public.leases (property_id)
  where status = 'actif';

create index leases_organization_id_idx on public.leases (organization_id);
create index leases_property_id_idx on public.leases (property_id);
create index leases_tenant_account_id_idx on public.leases (tenant_account_id);

create trigger trg_leases_updated_at
  before update on public.leases
  for each row execute function private.set_updated_at();

create trigger trg_leases_prevent_org_change
  before update on public.leases
  for each row execute function private.prevent_org_change();

-- Un Lease n'est autorisé que sur un bien dont location_type est
-- longue_duree ou meuble_simple.
create or replace function private.validate_lease_property_location_type()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_location_type text;
begin
  select location_type into v_location_type
  from public.properties
  where id = new.property_id;

  if v_location_type not in ('longue_duree', 'meuble_simple') then
    raise exception
      'Lease impossible : le bien % a le type de location "%", incompatible (attendu longue_duree ou meuble_simple)',
      new.property_id, v_location_type;
  end if;
  return new;
end;
$$;

create trigger trg_leases_validate_property_location_type
  before insert or update of property_id on public.leases
  for each row execute function private.validate_lease_property_location_type();

-- ----------------------------------------------------------------------------
-- CATALOGUE DE PERMISSIONS — extension pour 'leases'.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('leases', 'create', 'Créer un contrat de location'),
  ('leases', 'read',   'Consulter les contrats de location'),
  ('leases', 'update', 'Modifier un contrat de location'),
  ('leases', 'delete', 'Résilier / supprimer un contrat de location');

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
    (v_agent_id, 'leases', 'create'),
    (v_agent_id, 'leases', 'read'),
    (v_agent_id, 'leases', 'update'),
    (v_agent_id, 'leases', 'delete');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read'),
    (v_comptable_id, 'leases', 'read');

  return new;
end;
$$;

-- Backfill pour les organisations déjà créées (ex: "Agence Demo").
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'leases'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('leases', 'create'),
  ('leases', 'read'),
  ('leases', 'update'),
  ('leases', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'leases', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ----------------------------------------------------------------------------

alter table public.leases enable row level security;

-- Lecture : le locataire concerné voit son propre contrat ; tout profil
-- interne de l'organisation voit tous les contrats de l'organisation.
create policy leases_select on public.leases
  for select
  using (
    tenant_account_id = auth.uid()
    or (organization_id = private.current_org_id() and private.is_internal())
  );

create policy leases_insert on public.leases
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'create')
  );

create policy leases_update on public.leases
  for update
  using (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'update')
  )
  with check (organization_id = private.current_org_id());

create policy leases_delete on public.leases
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'delete')
  );
