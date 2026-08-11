-- ============================================================================
-- MODULE 7 — TICKETS DE MAINTENANCE / TRAVAUX
-- Signalement délégable au locataire (sur son bail actif uniquement),
-- pilotage (statut, priorité, coûts) réservé au staff. Lien optionnel et
-- jamais automatique vers une imputation de caution (Module 5).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. MAINTENANCE_TICKETS.
-- ----------------------------------------------------------------------------

create table public.maintenance_tickets (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations (id) on delete restrict,
  property_id           uuid not null,
  lease_id              uuid,
  reported_by_tenant_id uuid,
  reported_by_staff_id  uuid,
  title                 text not null,
  description           text,
  priority              text not null default 'normale'
                           check (priority in ('basse', 'normale', 'haute', 'urgente')),
  status                text not null default 'signale'
                           check (status in ('signale', 'en_cours', 'resolu', 'ferme')),
  estimated_cost        numeric(12, 2) check (estimated_cost is null or estimated_cost >= 0),
  actual_cost           numeric(12, 2) check (actual_cost is null or actual_cost >= 0),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  -- Posé par le serveur (trigger) à l'entrée dans 'resolu'. Recalculé à
  -- chaque nouvelle entrée dans 'resolu' (pas figé à la première date) ;
  -- effacé si le ticket est rouvert (repasse à signale/en_cours) ; conservé
  -- si le ticket passe ensuite à 'ferme' (clôture après résolution).
  resolved_at           timestamptz,

  constraint maintenance_tickets_org_id_key unique (organization_id, id),

  constraint maintenance_tickets_reporter_exactly_one check (
    (reported_by_tenant_id is not null and reported_by_staff_id is null)
    or (reported_by_tenant_id is null and reported_by_staff_id is not null)
  ),

  -- Un ticket locataire ne peut jamais être "sur un bien vacant" : le bail
  -- qui le justifie est obligatoire dès la contrainte, la correspondance
  -- réelle (bail actif, bon locataire, bon bien) est vérifiée par trigger
  -- pour un message clair.
  constraint maintenance_tickets_tenant_requires_lease check (
    reported_by_tenant_id is null or lease_id is not null
  ),

  constraint maintenance_tickets_property_org_fk
    foreign key (organization_id, property_id)
    references public.properties (organization_id, id)
    on delete restrict,

  constraint maintenance_tickets_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint maintenance_tickets_reported_by_staff_org_fk
    foreign key (organization_id, reported_by_staff_id)
    references public.profiles (organization_id, id),

  -- tenant_accounts n'a plus organization_id depuis le Module 1b : FK simple
  -- (comme leases.tenant_account_id), l'appartenance active au bail est
  -- vérifiée par trigger, pas par une FK composite.
  constraint maintenance_tickets_reported_by_tenant_fkey
    foreign key (reported_by_tenant_id) references public.tenant_accounts (id)
);

comment on table public.maintenance_tickets is
  'Tickets de maintenance/travaux. Signalement délégable au locataire (sur son bail actif), pilotage (statut/priorité/coûts) réservé au staff.';

create index maintenance_tickets_organization_id_idx on public.maintenance_tickets (organization_id);
create index maintenance_tickets_property_id_idx on public.maintenance_tickets (property_id);
create index maintenance_tickets_lease_id_idx on public.maintenance_tickets (lease_id);
create index maintenance_tickets_reported_by_tenant_id_idx on public.maintenance_tickets (reported_by_tenant_id);
create index maintenance_tickets_status_idx on public.maintenance_tickets (status);

create trigger trg_maintenance_tickets_updated_at
  before update on public.maintenance_tickets
  for each row execute function private.set_updated_at();

-- organization_id/property_id/lease_id/identité du déclarant immuables
-- après création (defense in depth au-delà des RLS, même principe que
-- prevent_org_change).
create or replace function private.prevent_maintenance_ticket_identity_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.property_id is distinct from old.property_id
     or new.lease_id is distinct from old.lease_id
     or new.reported_by_tenant_id is distinct from old.reported_by_tenant_id
     or new.reported_by_staff_id is distinct from old.reported_by_staff_id
  then
    raise exception 'organization_id, property_id, lease_id et l''identité du déclarant sont immuables après création'
      using detail = 'maintenance_ticket.identity.immutable', errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_maintenance_tickets_prevent_identity_change
  before update on public.maintenance_tickets
  for each row execute function private.prevent_maintenance_ticket_identity_change();

-- Un ticket locataire doit référencer un bail ACTIF de ce locataire, sur ce
-- bien, dans cette organisation — pas seulement une adhésion active (plus
-- strict : "un bail actif", pas "un rattachement à l'organisation").
create or replace function private.validate_maintenance_ticket_tenant_lease()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.reported_by_tenant_id is null then
    return new;
  end if;

  if not exists (
    select 1 from public.leases l
    where l.id = new.lease_id
      and l.tenant_account_id = new.reported_by_tenant_id
      and l.property_id = new.property_id
      and l.organization_id = new.organization_id
      and l.status = 'actif'
  ) then
    raise exception 'Ticket refusé : aucun bail actif de ce locataire ne correspond à ce bien'
      using detail = 'maintenance_ticket.tenant_report.invalid_lease', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_tickets_validate_tenant_lease
  before insert or update of lease_id, property_id, reported_by_tenant_id, organization_id
  on public.maintenance_tickets
  for each row execute function private.validate_maintenance_ticket_tenant_lease();

-- Un locataire ne peut modifier que titre/description, et seulement tant
-- que le staff n'a pas commencé à traiter le ticket (status = 'signale').
-- Le staff (is_internal()) n'est pas concerné, sa policy + permission le
-- gouvernent séparément. Même principe que
-- restrict_tenant_inspection_update_fields (Module 6).
create or replace function private.restrict_tenant_maintenance_ticket_update_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if private.is_internal() then
    return new;
  end if;

  if old.status <> 'signale' then
    raise exception 'Ce ticket ne peut plus être modifié par le locataire : le traitement a déjà commencé'
      using detail = 'maintenance_ticket.tenant_update.locked_after_staff_action', errcode = 'P0001';
  end if;

  if new.status is distinct from old.status
     or new.priority is distinct from old.priority
     or new.estimated_cost is distinct from old.estimated_cost
     or new.actual_cost is distinct from old.actual_cost
     or new.resolved_at is distinct from old.resolved_at
  then
    raise exception 'Un locataire ne peut modifier que le titre et la description de son ticket, jamais son statut, sa priorité ou ses coûts'
      using detail = 'maintenance_ticket.tenant_update.forbidden_field', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_tickets_restrict_tenant_update
  before update on public.maintenance_tickets
  for each row execute function private.restrict_tenant_maintenance_ticket_update_fields();

-- resolved_at : posé par le serveur à chaque ENTRÉE dans 'resolu' (recalculé
-- si le ticket est rouvert puis re-résolu), effacé si le ticket est rouvert
-- (repasse à signale/en_cours), conservé s'il passe ensuite à 'ferme'.
-- Toute tentative de le fixer autrement est rejetée.
create or replace function private.set_maintenance_ticket_resolved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'resolu' and (TG_OP = 'INSERT' or old.status is distinct from 'resolu') then
    new.resolved_at := now();
    return new;
  end if;

  if TG_OP = 'UPDATE' and old.status = 'resolu' and new.status in ('signale', 'en_cours') then
    new.resolved_at := null;
    return new;
  end if;

  if TG_OP = 'UPDATE' and new.resolved_at is distinct from old.resolved_at then
    raise exception 'resolved_at est posé par le serveur au moment du passage à ''resolu'', jamais modifiable directement'
      using detail = 'maintenance_ticket.resolved_at.server_only', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_tickets_set_resolved_at
  before insert or update on public.maintenance_tickets
  for each row execute function private.set_maintenance_ticket_resolved_at();

-- ----------------------------------------------------------------------------
-- 2. MAINTENANCE_TICKET_PHOTOS — même discipline que inspection_photos.
-- ----------------------------------------------------------------------------

create table public.maintenance_ticket_photos (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations (id) on delete restrict,
  maintenance_ticket_id uuid not null,
  storage_path          text not null,
  file_hash             text not null,
  uploaded_at           timestamptz not null default now(),

  constraint maintenance_ticket_photos_org_id_key unique (organization_id, id),

  constraint maintenance_ticket_photos_ticket_org_fk
    foreign key (organization_id, maintenance_ticket_id)
    references public.maintenance_tickets (organization_id, id)
    on delete restrict
);

comment on column public.maintenance_ticket_photos.file_hash is
  'Empreinte calculée côté client sur les octets effectivement envoyés (après compression) — mêmes garanties/limites que inspection_photos.file_hash.';

create index maintenance_ticket_photos_organization_id_idx on public.maintenance_ticket_photos (organization_id);
create index maintenance_ticket_photos_ticket_id_idx on public.maintenance_ticket_photos (maintenance_ticket_id);

create or replace function private.set_maintenance_ticket_photo_uploaded_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.uploaded_at := now();
  return new;
end;
$$;

create trigger trg_maintenance_ticket_photos_set_uploaded_at
  before insert on public.maintenance_ticket_photos
  for each row execute function private.set_maintenance_ticket_photo_uploaded_at();

create or replace function private.prevent_maintenance_ticket_photo_uploaded_at_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.uploaded_at is distinct from old.uploaded_at then
    raise exception 'uploaded_at est immuable, y compris pour un profil interne'
      using detail = 'maintenance_ticket_photo.uploaded_at.immutable', errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_maintenance_ticket_photos_prevent_uploaded_at_change
  before update on public.maintenance_ticket_photos
  for each row execute function private.prevent_maintenance_ticket_photo_uploaded_at_change();

-- Immuabilité totale du contenu (posée directement ici, sans attendre un
-- correctif ultérieur type Module 6d).
create or replace function private.prevent_maintenance_ticket_photo_content_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.file_hash is distinct from old.file_hash
     or new.storage_path is distinct from old.storage_path then
    raise exception 'file_hash et storage_path sont immuables après insertion : pour corriger une photo, supprimez-la et envoyez-en une nouvelle'
      using detail = 'maintenance_ticket_photo.content.immutable', errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_maintenance_ticket_photos_prevent_content_change
  before update on public.maintenance_ticket_photos
  for each row execute function private.prevent_maintenance_ticket_photo_content_change();

create or replace function private.validate_maintenance_ticket_photo_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.maintenance_ticket_photos
  where maintenance_ticket_id = new.maintenance_ticket_id;

  if v_count >= 10 then
    raise exception 'Limite atteinte : maximum 10 photos par ticket de maintenance'
      using detail = 'maintenance_ticket_photo.limit.exceeded', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_ticket_photos_validate_limit
  before insert on public.maintenance_ticket_photos
  for each row execute function private.validate_maintenance_ticket_photo_limit();

-- Verrouillage confirmé : plus aucune photo ajoutée/supprimée une fois le
-- ticket résolu ou fermé (absent des règles initiales, ajouté sur
-- confirmation explicite).
create or replace function private.prevent_maintenance_ticket_photo_when_closed()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.maintenance_tickets
  where id = coalesce(new.maintenance_ticket_id, old.maintenance_ticket_id);

  if v_status in ('resolu', 'ferme') then
    raise exception 'Impossible d''ajouter ou de supprimer une photo : ce ticket de maintenance est déjà % ',
      case when v_status = 'resolu' then 'résolu' else 'fermé' end
      using detail = 'maintenance_ticket_photo.ticket_closed.locked', errcode = 'P0001';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_maintenance_ticket_photos_prevent_when_closed
  before insert or delete on public.maintenance_ticket_photos
  for each row execute function private.prevent_maintenance_ticket_photo_when_closed();

-- ----------------------------------------------------------------------------
-- 3. LIEN OPTIONNEL AVEC DEPOSIT_LEDGER (MODULE 5) — jamais automatique.
-- ----------------------------------------------------------------------------

alter table public.deposit_ledger
  add column maintenance_ticket_id uuid,
  add constraint deposit_ledger_maintenance_ticket_org_fk
    foreign key (organization_id, maintenance_ticket_id)
    references public.maintenance_tickets (organization_id, id)
    on delete restrict;

comment on column public.deposit_ledger.maintenance_ticket_id is
  'Lien de traçabilité optionnel vers le ticket de maintenance justifiant une imputation dégâts. Jamais posé automatiquement : décision distincte du staff au moment d''enregistrer l''imputation (Module 5).';

-- Si le ticket référencé a lui-même un bail, il doit correspondre au bail
-- de l'imputation — sinon aucune contrainte (ticket sans bail = bien
-- vacant à l'époque, rien à croiser).
create or replace function private.validate_deposit_ledger_maintenance_ticket_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_ticket_lease_id uuid;
begin
  if new.maintenance_ticket_id is null then
    return new;
  end if;

  select lease_id into v_ticket_lease_id
  from public.maintenance_tickets
  where id = new.maintenance_ticket_id;

  if v_ticket_lease_id is not null and v_ticket_lease_id is distinct from new.lease_id then
    raise exception 'Incohérence : le ticket de maintenance référencé concerne un autre bail que celui de cette imputation'
      using detail = 'deposit_ledger.maintenance_ticket_mismatch.lease', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_deposit_ledger_validate_maintenance_ticket_consistency
  before insert on public.deposit_ledger
  for each row execute function private.validate_deposit_ledger_maintenance_ticket_consistency();

-- ----------------------------------------------------------------------------
-- 4. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('maintenance_tickets', 'create', 'Créer un ticket de maintenance'),
  ('maintenance_tickets', 'read',   'Consulter les tickets de maintenance'),
  ('maintenance_tickets', 'update', 'Modifier / traiter un ticket de maintenance'),
  ('maintenance_tickets', 'delete', 'Supprimer un ticket de maintenance');

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
    (v_agent_id, 'reservations', 'delete'),
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
    (v_agent_id, 'maintenance_tickets', 'delete');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read'),
    (v_comptable_id, 'leases', 'read'),
    (v_comptable_id, 'reservations', 'read'),
    (v_comptable_id, 'payment_schedules', 'read'),
    (v_comptable_id, 'payments', 'read'),
    (v_comptable_id, 'payments', 'create'),
    (v_comptable_id, 'deposit_ledger', 'read'),
    (v_comptable_id, 'property_inspections', 'read'),
    (v_comptable_id, 'maintenance_tickets', 'read');

  return new;
end;
$$;

insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'maintenance_tickets'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('maintenance_tickets', 'create'), ('maintenance_tickets', 'read'),
  ('maintenance_tickets', 'update'), ('maintenance_tickets', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'maintenance_tickets', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY.
-- ----------------------------------------------------------------------------

alter table public.maintenance_tickets enable row level security;
alter table public.maintenance_ticket_photos enable row level security;

create policy maintenance_tickets_select on public.maintenance_tickets
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or reported_by_tenant_id = auth.uid()
  );

create policy maintenance_tickets_insert on public.maintenance_tickets
  for insert
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('maintenance_tickets', 'create')
      and reported_by_staff_id = auth.uid()
    )
    or (
      reported_by_tenant_id = auth.uid()
      and reported_by_staff_id is null
      and status = 'signale'
      and priority = 'normale'
      and actual_cost is null
    )
  );

create policy maintenance_tickets_update on public.maintenance_tickets
  for update
  using (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'update'))
    or (reported_by_tenant_id = auth.uid() and status = 'signale')
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'update'))
    or reported_by_tenant_id = auth.uid()
  );

create policy maintenance_tickets_delete on public.maintenance_tickets
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('maintenance_tickets', 'delete')
  );

create policy maintenance_ticket_photos_select on public.maintenance_ticket_photos
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.maintenance_tickets t
      where t.id = maintenance_ticket_photos.maintenance_ticket_id
        and t.reported_by_tenant_id = auth.uid()
    )
  );

create policy maintenance_ticket_photos_insert on public.maintenance_ticket_photos
  for insert
  with check (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'update'))
    or exists (
      select 1 from public.maintenance_tickets t
      where t.id = maintenance_ticket_photos.maintenance_ticket_id
        and t.reported_by_tenant_id = auth.uid()
        and t.status not in ('resolu', 'ferme')
    )
  );

create policy maintenance_ticket_photos_delete on public.maintenance_ticket_photos
  for delete
  using (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'delete'))
    or exists (
      select 1 from public.maintenance_tickets t
      where t.id = maintenance_ticket_photos.maintenance_ticket_id
        and t.reported_by_tenant_id = auth.uid()
        and t.status not in ('resolu', 'ferme')
    )
  );

-- Pas de policy UPDATE sur maintenance_ticket_photos : correction par
-- suppression + nouvel envoi, jamais par modification (même principe que
-- inspection_photos).

-- ----------------------------------------------------------------------------
-- 6. SUPABASE STORAGE — bucket privé + policies.
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('maintenance-photos', 'maintenance-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Chemin : {organization_id}/{maintenance_ticket_id}/{uuid}.{ext}
-- (pas de niveau "item" intermédiaire, contrairement à inspection-photos).

create policy maintenance_ticket_photos_storage_select on storage.objects
  for select
  using (
    bucket_id = 'maintenance-photos'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text)
      or exists (
        select 1 from public.maintenance_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and t.reported_by_tenant_id = auth.uid()
      )
    )
  );

create policy maintenance_ticket_photos_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'maintenance-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('maintenance_tickets', 'update')
      )
      or exists (
        select 1 from public.maintenance_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and t.reported_by_tenant_id = auth.uid()
          and t.status not in ('resolu', 'ferme')
          and (storage.foldername(name))[1] = t.organization_id::text
      )
    )
  );

create policy maintenance_ticket_photos_storage_delete on storage.objects
  for delete
  using (
    bucket_id = 'maintenance-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('maintenance_tickets', 'delete')
      )
      or exists (
        select 1 from public.maintenance_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and t.reported_by_tenant_id = auth.uid()
          and t.status not in ('resolu', 'ferme')
      )
    )
  );

-- Pas de policy UPDATE sur storage.objects : correction par suppression +
-- nouvel envoi (même principe que inspection-photos).
