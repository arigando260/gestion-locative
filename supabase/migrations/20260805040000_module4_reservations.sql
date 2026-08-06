-- ============================================================================
-- MODULE 4 — RESERVATION (courte durée)
-- ============================================================================

create extension if not exists btree_gist;

-- Buffer de turnover par défaut au niveau organisation (hérité si le bien
-- ne précise rien).
alter table public.organizations
  add column default_turnover_buffer_days integer not null default 0
    check (default_turnover_buffer_days >= 0);

-- Buffer de turnover propre au bien. NULL = hérite du défaut organisation.
alter table public.properties
  add column turnover_buffer_days integer
    check (turnover_buffer_days is null or turnover_buffer_days >= 0);

create table public.reservations (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete restrict,
  property_id         uuid not null,
  tenant_account_id   uuid not null references public.tenant_accounts (id) on delete restrict,
  check_in_date       date not null,
  check_out_date      date not null,
  nightly_rate        numeric(12, 2) not null check (nightly_rate >= 0),
  total_amount        numeric(12, 2) not null check (total_amount >= 0),
  status              text not null default 'confirmee'
                         check (status in ('confirmee', 'annulee', 'terminee')),
  -- Snapshot du buffer effectif au moment de la création (ou du changement
  -- de property_id) — jamais recalculé ensuite (voir message d'accompagnement :
  -- un recalcul rétroactif pourrait invalider des réservations déjà
  -- confirmées et payées).
  -- Rempli par trigger (private.set_reservation_turnover_buffer), pas par
  -- le client : toute valeur envoyée par l'API est écrasée.
  turnover_buffer_days integer not null check (turnover_buffer_days >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint reservations_checkout_after_checkin
    check (check_out_date > check_in_date),

  constraint reservations_property_org_fk
    foreign key (organization_id, property_id)
    references public.properties (organization_id, id)
    on delete restrict,

  -- Aucun chevauchement entre réservations confirmées sur le même bien,
  -- en tenant compte du buffer de turnover propre à chaque réservation.
  constraint reservations_no_overlap_confirmed
    exclude using gist (
      property_id with =,
      daterange(check_in_date, check_out_date + turnover_buffer_days, '[)') with &&
    )
    where (status = 'confirmee')
);

comment on table public.reservations is
  'Réservations courte durée. location_type du bien doit être courte_duree. Aucun chevauchement (buffer de turnover inclus) entre réservations confirmées sur le même bien (contrainte d''exclusion GiST). turnover_buffer_days est figé à la création, jamais recalculé rétroactivement.';

create index reservations_organization_id_idx on public.reservations (organization_id);
create index reservations_property_id_idx on public.reservations (property_id);
create index reservations_tenant_account_id_idx on public.reservations (tenant_account_id);

create trigger trg_reservations_updated_at
  before update on public.reservations
  for each row execute function private.set_updated_at();

create trigger trg_reservations_prevent_org_change
  before update on public.reservations
  for each row execute function private.prevent_org_change();

-- Calcule et fige turnover_buffer_days : valeur du bien si renseignée,
-- sinon défaut de l'organisation. Toute valeur fournie par le client est
-- ignorée/écrasée (colonne non pilotable directement depuis l'API).
create or replace function private.set_reservation_turnover_buffer()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_property_buffer    integer;
  v_org_default_buffer integer;
begin
  select p.turnover_buffer_days, o.default_turnover_buffer_days
    into v_property_buffer, v_org_default_buffer
  from public.properties p
  join public.organizations o on o.id = p.organization_id
  where p.id = new.property_id;

  new.turnover_buffer_days := coalesce(v_property_buffer, v_org_default_buffer);
  return new;
end;
$$;

create trigger trg_reservations_set_turnover_buffer
  before insert or update of property_id on public.reservations
  for each row execute function private.set_reservation_turnover_buffer();

-- Le bien référencé doit avoir location_type = courte_duree.
create or replace function private.validate_reservation_property_location_type()
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

  if v_location_type <> 'courte_duree' then
    raise exception
      'Réservation impossible : le bien % a le type de location "%", incompatible (attendu courte_duree)',
      new.property_id, v_location_type;
  end if;
  return new;
end;
$$;

create trigger trg_reservations_validate_property_location_type
  before insert or update of property_id on public.reservations
  for each row execute function private.validate_reservation_property_location_type();

-- Le locataire doit avoir un rattachement actif à l'organisation de la
-- réservation (même principe que la correction Module 1b sur leases).
create or replace function private.validate_reservation_tenant_membership()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.tenant_organization_memberships m
    where m.tenant_account_id = new.tenant_account_id
      and m.organization_id = new.organization_id
      and m.status = 'actif'
  ) then
    raise exception
      'Réservation impossible : le locataire % n''a pas de rattachement actif à l''organisation %',
      new.tenant_account_id, new.organization_id;
  end if;
  return new;
end;
$$;

create trigger trg_reservations_validate_tenant_membership
  before insert or update of tenant_account_id, organization_id on public.reservations
  for each row execute function private.validate_reservation_tenant_membership();

-- ----------------------------------------------------------------------------
-- CATALOGUE DE PERMISSIONS — extension pour 'reservations'.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('reservations', 'create', 'Créer une réservation courte durée'),
  ('reservations', 'read',   'Consulter les réservations courte durée'),
  ('reservations', 'update', 'Modifier une réservation courte durée'),
  ('reservations', 'delete', 'Annuler / supprimer une réservation courte durée');

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
    (v_agent_id, 'leases', 'delete'),
    (v_agent_id, 'reservations', 'create'),
    (v_agent_id, 'reservations', 'read'),
    (v_agent_id, 'reservations', 'update'),
    (v_agent_id, 'reservations', 'delete');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read'),
    (v_comptable_id, 'leases', 'read'),
    (v_comptable_id, 'reservations', 'read');

  return new;
end;
$$;

-- Backfill pour les organisations déjà créées (ex: "Agence Demo").
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'reservations'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('reservations', 'create'),
  ('reservations', 'read'),
  ('reservations', 'update'),
  ('reservations', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'reservations', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY — même principe que leases.
-- ----------------------------------------------------------------------------

alter table public.reservations enable row level security;

create policy reservations_select on public.reservations
  for select
  using (
    tenant_account_id = auth.uid()
    or (organization_id = private.current_org_id() and private.is_internal())
  );

create policy reservations_insert on public.reservations
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('reservations', 'create')
  );

create policy reservations_update on public.reservations
  for update
  using (
    organization_id = private.current_org_id()
    and private.has_permission('reservations', 'update')
  )
  with check (organization_id = private.current_org_id());

create policy reservations_delete on public.reservations
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('reservations', 'delete')
  );
