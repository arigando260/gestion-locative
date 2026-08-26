-- ============================================================================
-- MODULE 12o — Fondation assignation bien↔agent (Phase 3, sous-module 3,
-- brique 1/2).
--
-- Table property_agent_assignments : les deux FK composites (organization_id,
-- property_id) et (organization_id, agent_id) référencent les contraintes
-- uniques déjà existantes properties_org_id_key (Module 3) et
-- profiles_org_id_key (Module 1) -- garantissent, au niveau contrainte, qu'un
-- agent d'une organisation ne peut jamais être assigné à un bien d'une autre
-- organisation, sans dépendre d'un trigger applicatif pour ça. on delete
-- restrict sur les deux : même convention que les FK composites existantes
-- vers properties (maintenance_tickets_property_org_fk, Module 7) --
-- properties/profiles ne sont jamais réellement supprimés dans ce schéma
-- (désactivation via is_active, pas de policy DELETE), mais la contrainte
-- reste explicite plutôt que reposer sur le NO ACTION implicite.
--
-- Permissions catalogue property_agent_assignments:create/delete -- admin
-- les reçoit automatiquement (son seed prend tout le catalogue,
-- seed_default_roles_for_org), backfillées ici pour les organisations déjà
-- existantes (même patron que le backfill properties, Module 2).
-- Volontairement absentes des listes explicites agent/comptable :
-- seed_default_roles_for_org énumère leurs permissions une par une (pas un
-- blanket comme admin), donc une nouvelle entrée catalogue ne leur est
-- jamais accordée automatiquement -- aucune modification de cette fonction
-- n'est nécessaire ici pour préserver cette absence, "assigner" reste une
-- décision admin par construction.
--
-- private.agent_property_scope(p_property_id) : le rôle le plus large gagne
-- (admin ou comptable -> toujours true, même si agent est également
-- détenu) -- décision actée en conception. Un agent qui n'a NI admin NI
-- comptable NI d'assignation sur ce bien -> false. Ne vérifie pas
-- is_internal() elle-même : conçue pour être combinée en AND avec les
-- policies existantes (is_internal() + has_permission(...) déjà posés),
-- pas pour les dupliquer -- un compte tenant n'a ni user_roles ni
-- property_agent_assignments le référençant, donc retourne false de toute
-- façon si jamais appelée hors contexte staff.
--
-- N'APPLIQUE PAS encore ce filtre aux 7 policies existantes (properties,
-- leases, maintenance_tickets, lease_termination_requests, payment_
-- schedules, schedule_invoices, payment_receipts) -- fondation seule,
-- brique suivante du sous-module.
-- ============================================================================

create table public.property_agent_assignments (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  property_id     uuid not null,
  agent_id        uuid not null,
  assigned_by     uuid not null references public.profiles (id) on delete restrict,
  assigned_at     timestamptz not null default now(),

  constraint property_agent_assignments_unique unique (property_id, agent_id),

  constraint property_agent_assignments_property_org_fk
    foreign key (organization_id, property_id)
    references public.properties (organization_id, id)
    on delete restrict,

  constraint property_agent_assignments_agent_org_fk
    foreign key (organization_id, agent_id)
    references public.profiles (organization_id, id)
    on delete restrict
);

create index property_agent_assignments_organization_id_idx on public.property_agent_assignments (organization_id);
create index property_agent_assignments_property_id_idx on public.property_agent_assignments (property_id);
create index property_agent_assignments_agent_id_idx on public.property_agent_assignments (agent_id);

comment on table public.property_agent_assignments is
  'Assignation d''un agent à un bien -- restreint la visibilité de ce dernier pour ce rôle une fois private.agent_property_scope() branchée sur les policies (brique suivante). admin/comptable ne sont jamais concernés par cette restriction.';

alter table public.property_agent_assignments enable row level security;

-- Lecture : tout membre interne de l'organisation, sans permission dédiée
-- (même patron que properties_select/maintenance_tickets_select -- aucun de
-- ces deux ne gate non plus leur lecture staff par has_permission).
create policy property_agent_assignments_select on public.property_agent_assignments
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
  );

create policy property_agent_assignments_insert on public.property_agent_assignments
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('property_agent_assignments', 'create')
    and assigned_by = auth.uid()
  );

create policy property_agent_assignments_delete on public.property_agent_assignments
  for delete
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('property_agent_assignments', 'delete')
  );

-- Pas de policy UPDATE : une assignation existe ou n'existe pas, aucun champ
-- mutable en dehors de sa propre suppression/recréation.

-- ----------------------------------------------------------------------------
-- CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('property_agent_assignments', 'create', 'Assigner un agent à un bien'),
  ('property_agent_assignments', 'delete', 'Retirer l''assignation d''un agent à un bien');

-- Backfill pour les organisations déjà créées (ex: "Agence Demo") : les
-- permissions sont matérialisées dans role_permissions à la création de
-- l'organisation, donc une organisation existante n'hérite pas
-- automatiquement des nouvelles lignes du catalogue -- même patron que le
-- backfill properties (Module 2).
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'property_agent_assignments'
where r.code = 'admin'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- FONCTION DE SCOPE.
-- ----------------------------------------------------------------------------

create or replace function private.agent_property_scope(p_property_id uuid)
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
      from public.property_agent_assignments paa
      where paa.property_id = p_property_id
        and paa.agent_id = auth.uid()
    )
$$;

comment on function private.agent_property_scope is
  'true si l''appelant a le rôle admin ou comptable (accès non restreint, quelle que soit une éventuelle assignation), ou si un agent, true seulement si une ligne property_agent_assignments l''assigne à ce bien précis. À combiner en AND avec is_internal()/has_permission() déjà posés sur chaque policy, jamais pour les remplacer.';
