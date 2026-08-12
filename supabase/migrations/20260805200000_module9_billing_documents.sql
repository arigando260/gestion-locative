-- ============================================================================
-- MODULE 9 — DOCUMENTS DE FACTURATION : reçu de paiement (automatique) et
-- facture d'échéance(s) (à la demande, individuelle ou groupée sur UN SEUL
-- bail/réservation — jamais de répartition entre plusieurs locataires).
--
-- Les deux documents sont des PDF stockés et immuables (Storage privé, URL
-- signée) — pas une donnée calculée à la volée : un document remis à
-- quelqu'un doit rester identique à ce qu'il a reçu, contrairement à un
-- statut qui doit toujours refléter l'état courant (voir message
-- d'accompagnement). Correction = nouveau document, jamais d'édition.
--
-- Rendu PDF lui-même hors périmètre de cette migration (aucune dépendance
-- @react-pdf/renderer installée ici) : uniquement le schéma, les triggers
-- de cohérence/immuabilité, RLS, et les buckets Storage qui accueilleront
-- les fichiers une fois le rendu implémenté.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. ORGANIZATIONS — coordonnées, absentes jusqu'ici (nécessaires au
--    contenu minimal du reçu/de la facture). Nullable : aucun écran
--    d'édition dans cette migration (mini-écran prévu dans une passe
--    ultérieure), permission 'organizations'/'update' déjà existante
--    (Module 1) pour quand cet écran sera construit.
-- ----------------------------------------------------------------------------

alter table public.organizations
  add column address text,
  add column phone   text,
  add column email    text;

-- ----------------------------------------------------------------------------
-- 1. PAYMENT_RECEIPTS — 1 reçu par paiement confirmé, jamais plus.
-- ----------------------------------------------------------------------------

create table public.payment_receipts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  payment_id      uuid not null unique,
  -- NULL = éligibilité posée par le trigger payments (voir section 2),
  -- rendu pas encore effectué. Renseigné une seule fois, par le serveur,
  -- au moment où le PDF est effectivement généré et déposé — jamais avant,
  -- jamais modifié ensuite (voir trg_payment_receipts_fill_storage_path).
  storage_path    text,
  created_at      timestamptz not null default now(),
  generated_at    timestamptz,

  -- Défense en profondeur en plus du trigger ci-dessous : storage_path et
  -- generated_at sont renseignés ensemble ou pas du tout, jamais l'un sans
  -- l'autre — même esprit que lease_termination_requests_response_consistency
  -- (Module 8).
  constraint payment_receipts_generated_consistency check (
    (storage_path is null and generated_at is null)
    or (storage_path is not null and generated_at is not null)
  ),

  constraint payment_receipts_payment_org_fk
    foreign key (organization_id, payment_id)
    references public.payments (organization_id, id)
    on delete restrict
);

comment on table public.payment_receipts is
  'Reçus de paiement. Une ligne est créée automatiquement (trigger sur payments, voir private.ensure_payment_receipt_pending) dès qu''un paiement passe à confirme, storage_path=null jusqu''au rendu effectif du PDF (côté application). Immuable une fois storage_path renseigné.';

create index payment_receipts_organization_id_idx on public.payment_receipts (organization_id);

-- Immuabilité de l'identité, et transition storage_path null -> renseigné
-- strictement unique et server-timed (generated_at posé ici, jamais par le
-- client) — même discipline que resolved_at (Module 7) / finalized_at
-- (Module 6), appliquée ici à un couple de colonnes plutôt qu'une seule.
create or replace function private.fill_payment_receipt_storage_path()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.payment_id is distinct from old.payment_id
     or new.created_at is distinct from old.created_at
  then
    raise exception 'organization_id, payment_id et created_at sont immuables'
      using detail = 'payment_receipt.identity.immutable', errcode = 'P0001';
  end if;

  if old.storage_path is not null then
    if new.storage_path is distinct from old.storage_path
       or new.generated_at is distinct from old.generated_at
    then
      raise exception 'Un reçu déjà généré est immuable : storage_path/generated_at ne peuvent plus être modifiés'
        using detail = 'payment_receipt.storage_path.immutable', errcode = 'P0001';
    end if;
    return new;
  end if;

  if new.storage_path is not null then
    new.generated_at := now();
  elsif new.generated_at is distinct from old.generated_at then
    raise exception 'generated_at est posé par le serveur au moment où storage_path est renseigné, jamais avant'
      using detail = 'payment_receipt.generated_at.server_only', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_payment_receipts_fill_storage_path
  before update on public.payment_receipts
  for each row execute function private.fill_payment_receipt_storage_path();

-- Défense en profondeur : suppression bloquée même pour un rôle qui
-- bypasserait RLS (service_role) — même principe que testé aux Modules 7b/8.
create or replace function private.prevent_payment_receipt_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Un reçu de paiement est immuable : suppression impossible'
    using detail = 'payment_receipt.delete.immutable', errcode = 'P0001';
end;
$$;

create trigger trg_payment_receipts_prevent_delete
  before delete on public.payment_receipts
  for each row execute function private.prevent_payment_receipt_delete();

-- ----------------------------------------------------------------------------
-- 2. TRIGGER SUR PAYMENTS — pose l'éligibilité au reçu de façon
--    inconditionnelle au chemin d'écriture (INSERT direct avec
--    status='confirme', comme le fait aujourd'hui recordPayment(), OU un
--    futur UPDATE vers 'confirme' que la RLS payments_update autorise déjà
--    mais qu'aucune Server Action n'exerce encore) — jamais une décision
--    qui ne vivrait que dans une Server Action. security definer :
--    l'appelant (staff, ou un futur webhook de passerelle de paiement) n'a
--    pas forcément de policy INSERT sur payment_receipts (il n'y en a
--    d'ailleurs aucune, voir section 5). on conflict : idempotent quel que
--    soit le nombre de fois où la condition redevient vraie.
-- ----------------------------------------------------------------------------

create or replace function private.ensure_payment_receipt_pending()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'confirme' and (TG_OP = 'INSERT' or old.status is distinct from 'confirme') then
    insert into public.payment_receipts (organization_id, payment_id)
    values (new.organization_id, new.id)
    on conflict (payment_id) do nothing;
  end if;
  return new;
end;
$$;

create trigger trg_payments_ensure_receipt_pending
  after insert or update of status on public.payments
  for each row execute function private.ensure_payment_receipt_pending();

-- ----------------------------------------------------------------------------
-- 3. SCHEDULE_INVOICES + INVOICE_SCHEDULE_ITEMS — facture(s) d'échéance(s),
--    toujours générée synchrone côté application (staff), jamais par
--    trigger : geste toujours délibéré, comme la création d'un ticket.
-- ----------------------------------------------------------------------------

create table public.schedule_invoices (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  lease_id        uuid,
  reservation_id  uuid,
  -- Toujours renseigné à la création (contrairement à payment_receipts) :
  -- la facture est générée de façon synchrone par la Server Action, jamais
  -- en deux temps.
  storage_path    text not null,
  generated_by    uuid not null,
  generated_at    timestamptz not null default now(),

  constraint schedule_invoices_org_id_key unique (organization_id, id),

  constraint schedule_invoices_exactly_one_link check (
    (lease_id is not null and reservation_id is null)
    or (lease_id is null and reservation_id is not null)
  ),

  constraint schedule_invoices_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint schedule_invoices_reservation_org_fk
    foreign key (organization_id, reservation_id)
    references public.reservations (organization_id, id)
    on delete restrict,

  constraint schedule_invoices_generated_by_org_fk
    foreign key (organization_id, generated_by)
    references public.profiles (organization_id, id)
);

comment on table public.schedule_invoices is
  'Factures d''échéance(s), générées à la demande par le staff. Toujours scopées à UN SEUL bail ou UNE SEULE réservation (jamais de répartition entre locataires) — voir invoice_schedule_items pour le détail des échéances couvertes. Immuable après génération.';

create index schedule_invoices_organization_id_idx on public.schedule_invoices (organization_id);
create index schedule_invoices_lease_id_idx on public.schedule_invoices (lease_id);
create index schedule_invoices_reservation_id_idx on public.schedule_invoices (reservation_id);

-- Immuabilité totale (aucune policy UPDATE n'est de toute façon exposée,
-- voir section 5, mais défense en profondeur contre un bypass RLS).
create or replace function private.prevent_schedule_invoice_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Une facture générée est immuable : aucune modification possible, réémettez un nouveau document'
    using detail = 'schedule_invoice.immutable', errcode = 'P0001';
end;
$$;

create trigger trg_schedule_invoices_prevent_change
  before update or delete on public.schedule_invoices
  for each row execute function private.prevent_schedule_invoice_change();

create table public.invoice_schedule_items (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete restrict,
  invoice_id          uuid not null,
  payment_schedule_id uuid not null,
  created_at          timestamptz not null default now(),

  constraint invoice_schedule_items_unique unique (invoice_id, payment_schedule_id),

  constraint invoice_schedule_items_invoice_org_fk
    foreign key (organization_id, invoice_id)
    references public.schedule_invoices (organization_id, id)
    on delete restrict,

  constraint invoice_schedule_items_schedule_org_fk
    foreign key (organization_id, payment_schedule_id)
    references public.payment_schedules (organization_id, id)
    on delete restrict
);

comment on table public.invoice_schedule_items is
  'Détail des échéances couvertes par une facture (1:N — c''est ce qui porte la facturation groupée). Pas de verrou sur payment_schedules : une même échéance peut apparaître sur plusieurs factures dans le temps, payment_schedules_effective_status reste seule source de vérité sur ce qui est réellement dû/payé.';

create index invoice_schedule_items_organization_id_idx on public.invoice_schedule_items (organization_id);
create index invoice_schedule_items_invoice_id_idx on public.invoice_schedule_items (invoice_id);
create index invoice_schedule_items_payment_schedule_id_idx on public.invoice_schedule_items (payment_schedule_id);

-- Rend structurellement impossible qu'un lot mélange deux locataires : la
-- vérification porte sur les baux/réservations, pas sur une liste de
-- locataires reconstruite côté application.
create or replace function private.validate_invoice_schedule_item_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_invoice_lease_id       uuid;
  v_invoice_reservation_id uuid;
  v_schedule_lease_id       uuid;
  v_schedule_reservation_id uuid;
begin
  select lease_id, reservation_id into v_invoice_lease_id, v_invoice_reservation_id
  from public.schedule_invoices where id = new.invoice_id;

  select lease_id, reservation_id into v_schedule_lease_id, v_schedule_reservation_id
  from public.payment_schedules where id = new.payment_schedule_id;

  if v_schedule_lease_id is distinct from v_invoice_lease_id
     or v_schedule_reservation_id is distinct from v_invoice_reservation_id
  then
    raise exception 'Incohérence : l''échéance % n''appartient pas au même bail/réservation que la facture %',
      new.payment_schedule_id, new.invoice_id
      using detail = 'invoice_schedule_item.mismatch.lease_or_reservation', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_invoice_schedule_items_validate_consistency
  before insert on public.invoice_schedule_items
  for each row execute function private.validate_invoice_schedule_item_consistency();

create or replace function private.prevent_invoice_schedule_item_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Une ligne de facture est immuable : aucune modification ni suppression possible'
    using detail = 'invoice_schedule_item.immutable', errcode = 'P0001';
end;
$$;

create trigger trg_invoice_schedule_items_prevent_change
  before update or delete on public.invoice_schedule_items
  for each row execute function private.prevent_invoice_schedule_item_change();

-- ----------------------------------------------------------------------------
-- 4. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('payment_receipts',  'read',   'Consulter les reçus de paiement'),
  ('payment_receipts',  'update', 'Finaliser la génération d''un reçu de paiement (dépôt du PDF)'),
  ('schedule_invoices', 'create', 'Générer une facture d''échéance(s)'),
  ('schedule_invoices', 'read',   'Consulter les factures d''échéance');

-- Pas d'action 'create'/'delete' pour payment_receipts : la ligne initiale
-- est exclusivement posée par le trigger (section 2), jamais par un appel
-- client ; pas d'action 'delete' pour schedule_invoices : immuable (section 3).

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
    (v_agent_id, 'maintenance_tickets', 'delete'),
    (v_agent_id, 'lease_termination_requests', 'create'),
    (v_agent_id, 'lease_termination_requests', 'read'),
    (v_agent_id, 'lease_termination_requests', 'update'),
    (v_agent_id, 'payment_receipts', 'read'),
    (v_agent_id, 'payment_receipts', 'update'),
    (v_agent_id, 'schedule_invoices', 'create'),
    (v_agent_id, 'schedule_invoices', 'read');

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
    (v_comptable_id, 'maintenance_tickets', 'read'),
    (v_comptable_id, 'lease_termination_requests', 'read'),
    (v_comptable_id, 'payment_receipts', 'read'),
    (v_comptable_id, 'payment_receipts', 'update'),
    (v_comptable_id, 'schedule_invoices', 'read');

  return new;
end;
$$;

insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource in ('payment_receipts', 'schedule_invoices')
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('payment_receipts', 'read'), ('payment_receipts', 'update'),
  ('schedule_invoices', 'create'), ('schedule_invoices', 'read')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('payment_receipts', 'read'), ('payment_receipts', 'update'),
  ('schedule_invoices', 'read')
) as v(resource, action)
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY.
-- ----------------------------------------------------------------------------

alter table public.payment_receipts     enable row level security;
alter table public.schedule_invoices    enable row level security;
alter table public.invoice_schedule_items enable row level security;

-- payment_receipts : le locataire lit ses propres reçus (via le paiement ->
-- bail ou réservation), jamais n'en crée. Aucune policy INSERT pour aucun
-- rôle : seul le trigger security definer (section 2) écrit la ligne
-- initiale.
create policy payment_receipts_select on public.payment_receipts
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('payment_receipts', 'read'))
    or exists (
      select 1 from public.payments p
      left join public.leases l on l.id = p.lease_id
      left join public.reservations r on r.id = p.reservation_id
      where p.id = payment_receipts.payment_id
        and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
    )
  );

create policy payment_receipts_update on public.payment_receipts
  for update
  using (
    organization_id = private.current_org_id()
    and private.has_permission('payment_receipts', 'update')
  )
  with check (organization_id = private.current_org_id());

-- Pas de policy DELETE : voir trg_payment_receipts_prevent_delete.

-- schedule_invoices : même principe. Le locataire lit ses propres factures
-- (via le bail/la réservation directement, pas via un paiement), jamais
-- n'en crée.
create policy schedule_invoices_select on public.schedule_invoices
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('schedule_invoices', 'read'))
    or exists (select 1 from public.leases l where l.id = schedule_invoices.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = schedule_invoices.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy schedule_invoices_insert on public.schedule_invoices
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('schedule_invoices', 'create')
    and generated_by = auth.uid()
  );

-- Pas de policy UPDATE ni DELETE : voir trg_schedule_invoices_prevent_change.

create policy invoice_schedule_items_select on public.invoice_schedule_items
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('schedule_invoices', 'read'))
    or exists (
      select 1 from public.schedule_invoices si
      left join public.leases l on l.id = si.lease_id
      left join public.reservations r on r.id = si.reservation_id
      where si.id = invoice_schedule_items.invoice_id
        and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
    )
  );

create policy invoice_schedule_items_insert on public.invoice_schedule_items
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('schedule_invoices', 'create')
  );

-- Pas de policy UPDATE ni DELETE : voir trg_invoice_schedule_items_prevent_change.

-- ----------------------------------------------------------------------------
-- 6. SUPABASE STORAGE — deux buckets privés, même discipline que
--    inspection-photos/maintenance-photos (Modules 6/7) : pas de policy
--    UPDATE (immuabilité), pas de policy DELETE non plus ici (contrairement
--    aux photos : un document erroné se corrige par réémission, jamais par
--    remplacement du fichier existant).
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-receipts', 'payment-receipts', false, 2097152, array['application/pdf'])
on conflict (id) do nothing;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('schedule-invoices', 'schedule-invoices', false, 2097152, array['application/pdf'])
on conflict (id) do nothing;

-- Chemin payment-receipts : {organization_id}/{payment_id}/{uuid}.pdf
create policy payment_receipts_storage_select on storage.objects
  for select
  using (
    bucket_id = 'payment-receipts'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('payment_receipts', 'read'))
      or exists (
        select 1 from public.payments p
        left join public.leases l on l.id = p.lease_id
        left join public.reservations r on r.id = p.reservation_id
        where p.id::text = (storage.foldername(name))[2]
          and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
      )
    )
  );

create policy payment_receipts_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'payment-receipts'
    and private.is_internal()
    and (storage.foldername(name))[1] = private.current_org_id()::text
    and private.has_permission('payment_receipts', 'update')
  );

-- Chemin schedule-invoices : {organization_id}/{invoice_id}/{uuid}.pdf
create policy schedule_invoices_storage_select on storage.objects
  for select
  using (
    bucket_id = 'schedule-invoices'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('schedule_invoices', 'read'))
      or exists (
        select 1 from public.schedule_invoices si
        left join public.leases l on l.id = si.lease_id
        left join public.reservations r on r.id = si.reservation_id
        where si.id::text = (storage.foldername(name))[2]
          and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
      )
    )
  );

create policy schedule_invoices_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'schedule-invoices'
    and private.is_internal()
    and (storage.foldername(name))[1] = private.current_org_id()::text
    and private.has_permission('schedule_invoices', 'create')
  );
