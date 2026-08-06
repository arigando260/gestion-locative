-- ============================================================================
-- MODULE 6 — ÉTATS DES LIEUX (ENTRÉE/SORTIE) AVEC PHOTOS
-- Capture délégable au locataire, validation et finalisation réservées au
-- côté interne. Justifie les imputations pour dégâts (Module 5).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. RÉGLAGES DE DÉLÉGATION DE CAPTURE + NOUVELLES COLONNES SUR LEASES.
-- ----------------------------------------------------------------------------

alter table public.organizations
  add column tenant_capture_enabled boolean not null default false;

alter table public.leases
  -- NULL = hérite du réglage organisation (résolution à la volée, même
  -- principe que les heures standard du Module 4b).
  add column tenant_capture_enabled boolean,
  -- Date de restitution effective des clés, distincte de end_date.
  add column keys_returned_at date,
  add constraint leases_keys_returned_after_start
    check (keys_returned_at is null or keys_returned_at >= start_date);

-- ----------------------------------------------------------------------------
-- 1. PROPERTY_INSPECTIONS.
-- ----------------------------------------------------------------------------

create table public.property_inspections (
  id                      uuid primary key default gen_random_uuid(),
  organization_id         uuid not null references public.organizations (id) on delete restrict,
  lease_id                uuid,
  reservation_id          uuid,
  inspection_type         text not null check (inspection_type in ('entree', 'sortie')),
  inspection_date         date not null,
  document_status         text not null default 'brouillon'
                             check (document_status in ('brouillon', 'finalise')),
  tenant_validation_status text not null default 'en_attente'
                             check (tenant_validation_status in ('en_attente', 'valide', 'conteste', 'accepte_tacitement')),
  tenant_validation_at    timestamptz,
  tenant_comments         text,
  conducted_by            uuid,
  created_by_tenant       boolean not null default false,
  observations            text,
  -- Posé par le serveur (trigger) au moment où document_status passe à
  -- 'finalise'. Jamais par le client. Immuable ensuite. Sert de base à
  -- l'acceptation tacite (voir private.inspection_effective_validation_status).
  finalized_at            timestamptz,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  constraint property_inspections_org_id_key unique (organization_id, id),

  constraint property_inspections_exactly_one_link check (
    (lease_id is not null and reservation_id is null)
    or (lease_id is null and reservation_id is not null)
  ),

  constraint property_inspections_tenant_validation_consistency check (
    (tenant_validation_status = 'en_attente' and tenant_validation_at is null)
    or (tenant_validation_status <> 'en_attente' and tenant_validation_at is not null)
  ),

  -- Un document finalisé porte toujours un profil interne responsable,
  -- que la capture ait été déléguée ou non.
  constraint property_inspections_finalized_requires_conductor check (
    document_status <> 'finalise' or conducted_by is not null
  ),

  constraint property_inspections_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint property_inspections_reservation_org_fk
    foreign key (organization_id, reservation_id)
    references public.reservations (organization_id, id)
    on delete restrict,

  constraint property_inspections_conducted_by_org_fk
    foreign key (organization_id, conducted_by)
    references public.profiles (organization_id, id)
);

comment on table public.property_inspections is
  'États des lieux d''entrée/sortie. La capture (items/photos) peut être déléguée au locataire (created_by_tenant) ; la validation (tenant_validation_*) reste bilatérale ; la finalisation (document_status) est réservée au côté interne (trigger, pas seulement RLS).';

create index property_inspections_organization_id_idx on public.property_inspections (organization_id);
create index property_inspections_lease_id_idx on public.property_inspections (lease_id);
create index property_inspections_reservation_id_idx on public.property_inspections (reservation_id);

create trigger trg_property_inspections_updated_at
  before update on public.property_inspections
  for each row execute function private.set_updated_at();

-- L'état des lieux d'entrée ne peut pas être postérieur au début du bail.
create or replace function private.validate_inspection_entry_date_vs_lease_start()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_start_date date;
begin
  if new.inspection_type <> 'entree' or new.lease_id is null then
    return new;
  end if;

  select start_date into v_start_date from public.leases where id = new.lease_id;

  if new.inspection_date > v_start_date then
    raise exception
      'État des lieux d''entrée refusé : sa date (%) est postérieure à la date de début du bail (%)',
      new.inspection_date, v_start_date;
  end if;

  return new;
end;
$$;

create trigger trg_property_inspections_validate_entry_date
  before insert or update of inspection_date, inspection_type, lease_id on public.property_inspections
  for each row execute function private.validate_inspection_entry_date_vs_lease_start();

-- Seul un profil interne autorisé (has_permission) peut faire passer
-- document_status de brouillon à finalisé. Un locataire ne peut structurellement
-- jamais satisfaire has_permission (aucune ligne dans profiles/user_roles).
create or replace function private.prevent_tenant_finalizing_inspection()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.document_status = 'finalise' and old.document_status <> 'finalise' then
    if not private.has_permission('property_inspections', 'update') then
      raise exception 'Seul un profil interne autorisé peut finaliser un état des lieux';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_property_inspections_prevent_tenant_finalize
  before update on public.property_inspections
  for each row execute function private.prevent_tenant_finalizing_inspection();

-- Pose finalized_at au moment exact de la transition brouillon -> finalisé
-- (valeur serveur, toute valeur envoyée par le client est ignorée). Rejette
-- explicitement toute tentative de modification ultérieure (immuable),
-- plutôt que de l'écraser silencieusement : une tentative de modifier cet
-- horodatage après coup n'est jamais un cas d'usage légitime, contrairement
-- au calcul normal à la finalisation.
create or replace function private.set_inspection_finalized_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.document_status = 'finalise' and old.document_status <> 'finalise' then
    new.finalized_at := now();
    return new;
  end if;

  if new.finalized_at is distinct from old.finalized_at then
    raise exception 'finalized_at est immuable, posé uniquement par le serveur au moment de la finalisation';
  end if;

  return new;
end;
$$;

create trigger trg_property_inspections_set_finalized_at
  before update on public.property_inspections
  for each row execute function private.set_inspection_finalized_at();

-- Source unique de vérité pour la règle d'acceptation tacite : utilisée à
-- la fois par le trigger d'autorisation d'imputation (Module 5) et par la
-- vue d'affichage ci-dessous, pour ne jamais la recalculer à deux endroits.
-- stable (pas immutable) car elle dépend de now().
create or replace function private.inspection_effective_validation_status(
  p_document_status         text,
  p_tenant_validation_status text,
  p_finalized_at            timestamptz
)
returns text
language sql
stable
as $$
  select case
    when p_document_status <> 'finalise' then p_tenant_validation_status
    when p_tenant_validation_status = 'en_attente' and p_finalized_at <= now() - interval '7 days'
      then 'accepte_tacitement'
    else p_tenant_validation_status
  end
$$;

-- Statut effectif exposé pour l'affichage locataire/agence (inclut
-- l'acceptation tacite calculée à la volée). RLS héritée de
-- property_inspections via security_invoker.
create view public.property_inspections_effective_status
with (security_invoker = true)
as
select
  pi.*,
  private.inspection_effective_validation_status(
    pi.document_status, pi.tenant_validation_status, pi.finalized_at
  ) as effective_validation_status
from public.property_inspections pi;

grant select on public.property_inspections_effective_status to authenticated;

-- Une fois finalisé, plus aucune modification sauf les champs de validation
-- locataire (qui, par construction, s'appliquent APRÈS finalisation).
create or replace function private.prevent_finalized_inspection_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' then
    if old.document_status = 'finalise' then
      raise exception 'Impossible de supprimer un état des lieux finalisé';
    end if;
    return old;
  end if;

  if old.document_status = 'finalise' then
    if new.inspection_type is distinct from old.inspection_type
       or new.inspection_date is distinct from old.inspection_date
       or new.lease_id is distinct from old.lease_id
       or new.reservation_id is distinct from old.reservation_id
       or new.document_status is distinct from old.document_status
       or new.conducted_by is distinct from old.conducted_by
       or new.created_by_tenant is distinct from old.created_by_tenant
       or new.observations is distinct from old.observations
       or new.organization_id is distinct from old.organization_id
    then
      raise exception 'État des lieux finalisé : seuls les champs de validation locataire (tenant_validation_status, tenant_validation_at, tenant_comments) restent modifiables';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_property_inspections_prevent_finalized_change
  before update or delete on public.property_inspections
  for each row execute function private.prevent_finalized_inspection_change();

-- Un locataire ne peut modifier librement QUE son propre brouillon
-- (created_by_tenant = true, document_status = 'brouillon' au moment de la
-- modification). Sur toute autre inspection de son bail (brouillon créé par
-- le staff, ou inspection déjà finalisée), seuls les 3 champs de validation
-- restent modifiables — c'est le mécanisme de validation bilatérale, qui
-- doit rester possible même sur un document que le locataire n'a pas
-- lui-même créé. Le staff (is_internal()) n'est pas concerné par cette
-- restriction, sa policy RLS + permission le gouverne déjà séparément.
create or replace function private.restrict_tenant_inspection_update_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if private.is_internal() then
    return new;
  end if;

  if old.created_by_tenant = true and old.document_status = 'brouillon' then
    return new;
  end if;

  if new.inspection_type is distinct from old.inspection_type
     or new.inspection_date is distinct from old.inspection_date
     or new.lease_id is distinct from old.lease_id
     or new.reservation_id is distinct from old.reservation_id
     or new.document_status is distinct from old.document_status
     or new.conducted_by is distinct from old.conducted_by
     or new.created_by_tenant is distinct from old.created_by_tenant
     or new.observations is distinct from old.observations
     or new.organization_id is distinct from old.organization_id
  then
    raise exception 'Un locataire ne peut modifier que ses champs de validation (tenant_validation_status, tenant_validation_at, tenant_comments) sur une inspection qu''il n''a pas créée en brouillon';
  end if;

  return new;
end;
$$;

create trigger trg_property_inspections_restrict_tenant_update
  before update on public.property_inspections
  for each row execute function private.restrict_tenant_inspection_update_fields();

-- ----------------------------------------------------------------------------
-- 2. INSPECTION_ITEMS.
-- ----------------------------------------------------------------------------

create table public.inspection_items (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null references public.organizations (id) on delete restrict,
  inspection_id         uuid not null,
  zone                  text not null,
  description           text,
  condition             text not null check (condition in ('bon', 'usage_normal', 'degrade', 'hors_service')),
  estimated_repair_cost numeric(12, 2) check (estimated_repair_cost is null or estimated_repair_cost >= 0),
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint inspection_items_org_id_key unique (organization_id, id),

  constraint inspection_items_inspection_org_fk
    foreign key (organization_id, inspection_id)
    references public.property_inspections (organization_id, id)
    on delete restrict
);

create index inspection_items_organization_id_idx on public.inspection_items (organization_id);
create index inspection_items_inspection_id_idx on public.inspection_items (inspection_id);

create trigger trg_inspection_items_updated_at
  before update on public.inspection_items
  for each row execute function private.set_updated_at();

-- Immuable dès que l'inspection parente est finalisée.
create or replace function private.prevent_finalized_inspection_item_change()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
begin
  select document_status into v_status
  from public.property_inspections
  where id = coalesce(new.inspection_id, old.inspection_id);

  if v_status = 'finalise' then
    raise exception 'Impossible de modifier un élément d''un état des lieux finalisé';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_inspection_items_prevent_finalized_change
  before update or delete on public.inspection_items
  for each row execute function private.prevent_finalized_inspection_item_change();

-- ----------------------------------------------------------------------------
-- 3. INSPECTION_PHOTOS.
-- ----------------------------------------------------------------------------

create table public.inspection_photos (
  id                 uuid primary key default gen_random_uuid(),
  organization_id    uuid not null references public.organizations (id) on delete restrict,
  inspection_item_id uuid not null,
  storage_path       text not null,
  file_hash          text not null,
  -- Posé par le serveur (trigger ci-dessous), jamais par le client.
  -- Immuable après coup, même pour un profil interne.
  uploaded_at        timestamptz not null default now(),

  constraint inspection_photos_org_id_key unique (organization_id, id),

  constraint inspection_photos_item_org_fk
    foreign key (organization_id, inspection_item_id)
    references public.inspection_items (organization_id, id)
    on delete restrict
);

comment on column public.inspection_photos.file_hash is
  'Empreinte cryptographique calculée côté client sur les octets effectivement envoyés (après compression). Protège contre la réutilisation accidentelle/non technique d''une photo d''entrée en sortie ; ne constitue pas une preuve cryptographique opposable à un acteur techniquement déterminé à falsifier l''empreinte (nécessiterait un recalcul serveur, hors périmètre de ce module).';

create index inspection_photos_organization_id_idx on public.inspection_photos (organization_id);
create index inspection_photos_inspection_item_id_idx on public.inspection_photos (inspection_item_id);
create index inspection_photos_file_hash_idx on public.inspection_photos (file_hash);

-- Horodatage serveur forcé à l'insertion, quelle que soit la valeur envoyée.
create or replace function private.set_photo_uploaded_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.uploaded_at := now();
  return new;
end;
$$;

create trigger trg_inspection_photos_set_uploaded_at
  before insert on public.inspection_photos
  for each row execute function private.set_photo_uploaded_at();

-- uploaded_at immuable après coup, indépendamment du statut de finalisation.
create or replace function private.prevent_photo_uploaded_at_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.uploaded_at is distinct from old.uploaded_at then
    raise exception 'uploaded_at est immuable, y compris pour un profil interne';
  end if;
  return new;
end;
$$;

create trigger trg_inspection_photos_prevent_uploaded_at_change
  before update on public.inspection_photos
  for each row execute function private.prevent_photo_uploaded_at_change();

-- Immuable dès que l'inspection parente (via l'item) est finalisée.
create or replace function private.prevent_finalized_inspection_photo_change()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
begin
  select pi.document_status into v_status
  from public.inspection_items ii
  join public.property_inspections pi on pi.id = ii.inspection_id
  where ii.id = coalesce(new.inspection_item_id, old.inspection_item_id);

  if v_status = 'finalise' then
    raise exception 'Impossible de modifier une photo d''un état des lieux finalisé';
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_inspection_photos_prevent_finalized_change
  before update or delete on public.inspection_photos
  for each row execute function private.prevent_finalized_inspection_photo_change();

-- Anti-fraude : un fichier déjà utilisé dans l'état des lieux d'ENTRÉE du
-- même contrat est refusé s'il est envoyé dans l'état des lieux de SORTIE.
create or replace function private.validate_inspection_photo_no_reuse()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_inspection_type text;
  v_lease_id        uuid;
  v_reservation_id  uuid;
  v_conflict_count  integer;
begin
  select pi.inspection_type, pi.lease_id, pi.reservation_id
    into v_inspection_type, v_lease_id, v_reservation_id
  from public.inspection_items ii
  join public.property_inspections pi on pi.id = ii.inspection_id
  where ii.id = new.inspection_item_id;

  if v_inspection_type = 'sortie' then
    select count(*) into v_conflict_count
    from public.inspection_photos ip
    join public.inspection_items ii2 on ii2.id = ip.inspection_item_id
    join public.property_inspections pi2 on pi2.id = ii2.inspection_id
    where ip.file_hash = new.file_hash
      and pi2.inspection_type = 'entree'
      and pi2.lease_id is not distinct from v_lease_id
      and pi2.reservation_id is not distinct from v_reservation_id;

    if v_conflict_count > 0 then
      raise exception 'Photo refusée : cette empreinte de fichier a déjà été utilisée dans l''état des lieux d''entrée de ce contrat (réutilisation interdite)';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_inspection_photos_validate_no_reuse
  before insert on public.inspection_photos
  for each row execute function private.validate_inspection_photo_no_reuse();

-- Plafond de 10 photos par élément. Pas de verrou de concurrence ici
-- (contrairement au solde de caution du Module 5) : c'est une limite UX,
-- pas un invariant financier — un léger dépassement en cas de course
-- concurrente n'a aucune conséquence de fond.
create or replace function private.validate_inspection_photo_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_count integer;
begin
  select count(*) into v_count
  from public.inspection_photos
  where inspection_item_id = new.inspection_item_id;

  if v_count >= 10 then
    raise exception 'Limite atteinte : maximum 10 photos par élément d''état des lieux';
  end if;

  return new;
end;
$$;

create trigger trg_inspection_photos_validate_limit
  before insert on public.inspection_photos
  for each row execute function private.validate_inspection_photo_limit();

-- ----------------------------------------------------------------------------
-- 4. LIEN AVEC DEPOSIT_LEDGER (MODULE 5) + RENFORCEMENT DU TRIGGER
--    D'AUTORISATION POUR LES IMPUTATIONS 'degats'.
-- ----------------------------------------------------------------------------

alter table public.deposit_ledger
  add column inspection_id uuid,
  add constraint deposit_ledger_inspection_org_fk
    foreign key (organization_id, inspection_id)
    references public.property_inspections (organization_id, id)
    on delete restrict;

-- Couple catégorie <-> type de caution : loyer/degats consomment l'avance
-- de garantie, impayes_utilities consomme la caution eau/électricité.
-- Pas demandé explicitement mais découle directement des définitions déjà
-- posées au Module 3c (avance de garantie = solvabilité/dégâts) et à ce
-- message (caution eau/électricité = impayés spécifiques).
alter table public.deposit_ledger
  add constraint deposit_ledger_category_matches_deposit_type check (
    imputation_category is null
    or (deposit_type = 'avance_garantie' and imputation_category in ('loyer', 'degats'))
    or (deposit_type = 'caution_utilities' and imputation_category = 'impayes_utilities')
  );

-- Une imputation 'degats' exige : un état des lieux d'ENTRÉE finalisé dont
-- le statut EFFECTIF (private.inspection_effective_validation_status, même
-- fonction que la vue d'affichage) est valide ou tacitement accepté, ET un
-- état des lieux de SORTIE finalisé réalisé dans les 7 jours suivant
-- keys_returned_at. On retient l'état des lieux d'entrée le plus RÉCENT
-- (finalized_at desc) : une correction (nouvel état des lieux après une
-- contestation) prime sur l'ancien. Un statut 'conteste' ne peut jamais
-- devenir tacitement accepté (private.inspection_effective_validation_status
-- ne le transforme que depuis 'en_attente'), donc bloque indéfiniment sans
-- action supplémentaire ici — voir message d'accompagnement pour le
-- raisonnement. Ne concerne que les baux (reservations non couvertes par
-- ces règles temporelles, non demandées pour ce cas).
create or replace function private.validate_deposit_ledger_damage_imputation_requires_inspections()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_keys_returned_at    date;
  v_entry_status        text;
  v_entry_finalized_at  timestamptz;
  v_entry_effective     text;
  v_exit_ok             boolean;
begin
  if new.entry_type <> 'imputation' or new.imputation_category <> 'degats' then
    return new;
  end if;

  if new.lease_id is null then
    raise exception 'Imputation pour dégâts impossible : uniquement applicable à un bail (lease_id requis)';
  end if;

  select tenant_validation_status, finalized_at
    into v_entry_status, v_entry_finalized_at
  from public.property_inspections
  where lease_id = new.lease_id
    and inspection_type = 'entree'
    and document_status = 'finalise'
  order by finalized_at desc nulls last
  limit 1;

  if v_entry_status is null then
    raise exception 'Imputation pour dégâts refusée : aucun état des lieux d''entrée finalisé pour ce bail';
  end if;

  v_entry_effective := private.inspection_effective_validation_status('finalise', v_entry_status, v_entry_finalized_at);

  if v_entry_effective not in ('valide', 'accepte_tacitement') then
    if v_entry_status = 'conteste' then
      raise exception 'Imputation pour dégâts refusée : l''état des lieux d''entrée de ce bail est contesté par le locataire (aucune acceptation tacite possible sur un statut contesté)';
    else
      raise exception 'Imputation pour dégâts refusée : l''état des lieux d''entrée de ce bail n''est pas encore validé ni tacitement accepté (statut: %)', v_entry_effective;
    end if;
  end if;

  select keys_returned_at into v_keys_returned_at
  from public.leases
  where id = new.lease_id;

  if v_keys_returned_at is null then
    raise exception 'Imputation pour dégâts refusée : aucune date de restitution des clés (leases.keys_returned_at) enregistrée pour ce bail';
  end if;

  select exists (
    select 1 from public.property_inspections
    where lease_id = new.lease_id
      and inspection_type = 'sortie'
      and document_status = 'finalise'
      and inspection_date <= v_keys_returned_at + 7
  ) into v_exit_ok;

  if not v_exit_ok then
    raise exception 'Imputation pour dégâts refusée : aucun état des lieux de sortie finalisé dans les 7 jours suivant la restitution des clés (%)', v_keys_returned_at;
  end if;

  return new;
end;
$$;

create trigger trg_deposit_ledger_validate_damage_imputation
  before insert on public.deposit_ledger
  for each row execute function private.validate_deposit_ledger_damage_imputation_requires_inspections();

-- ----------------------------------------------------------------------------
-- 5. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('property_inspections', 'create', 'Créer un état des lieux'),
  ('property_inspections', 'read',   'Consulter les états des lieux'),
  ('property_inspections', 'update', 'Modifier / finaliser un état des lieux et ses items/photos'),
  ('property_inspections', 'delete', 'Supprimer un état des lieux (non finalisé)');

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
    (v_agent_id, 'property_inspections', 'delete');

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
    (v_comptable_id, 'property_inspections', 'read');

  return new;
end;
$$;

insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'property_inspections'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('property_inspections', 'create'), ('property_inspections', 'read'),
  ('property_inspections', 'update'), ('property_inspections', 'delete')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'property_inspections', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 6. ROW LEVEL SECURITY.
-- ----------------------------------------------------------------------------

alter table public.property_inspections enable row level security;
alter table public.inspection_items enable row level security;
alter table public.inspection_photos enable row level security;

-- SELECT --------------------------------------------------------------------

create policy property_inspections_select on public.property_inspections
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = property_inspections.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy inspection_items_select on public.inspection_items
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.property_inspections pi
      left join public.leases l on l.id = pi.lease_id
      left join public.reservations r on r.id = pi.reservation_id
      where pi.id = inspection_items.inspection_id
        and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
    )
  );

create policy inspection_photos_select on public.inspection_photos
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      left join public.leases l on l.id = pi.lease_id
      left join public.reservations r on r.id = pi.reservation_id
      where ii.id = inspection_photos.inspection_item_id
        and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
    )
  );

-- INSERT ----------------------------------------------------------------

-- Locataire : uniquement un brouillon, sur SON bail, sans conducted_by,
-- et seulement si la délégation est active (bail, sinon organisation).
create policy property_inspections_insert on public.property_inspections
  for insert
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'create'))
    or (
      document_status = 'brouillon'
      and created_by_tenant = true
      and conducted_by is null
      and lease_id is not null
      and exists (
        select 1 from public.leases l
        join public.organizations o on o.id = l.organization_id
        where l.id = property_inspections.lease_id
          and l.tenant_account_id = auth.uid()
          and coalesce(l.tenant_capture_enabled, o.tenant_capture_enabled)
      )
    )
  );

-- Locataire : items/photos uniquement sur une inspection QU'IL A LUI-MÊME
-- créée en brouillon sur son propre bail (pas sur un brouillon créé par
-- le staff).
create policy inspection_items_insert on public.inspection_items
  for insert
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.property_inspections pi
      join public.leases l on l.id = pi.lease_id
      where pi.id = inspection_items.inspection_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

create policy inspection_photos_insert on public.inspection_photos
  for insert
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      join public.leases l on l.id = pi.lease_id
      where ii.id = inspection_photos.inspection_item_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

-- UPDATE ------------------------------------------------------------------
-- Volontairement large ici : les vraies restrictions (ne jamais finaliser,
-- rien changer une fois finalisé sauf validation) sont portées par les
-- triggers ci-dessus, pas par cette policy (RLS ne peut pas comparer
-- OLD/NEW dans WITH CHECK).

create policy property_inspections_update on public.property_inspections
  for update
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = property_inspections.reservation_id and r.tenant_account_id = auth.uid())
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = property_inspections.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy inspection_items_update on public.inspection_items
  for update
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.property_inspections pi
      join public.leases l on l.id = pi.lease_id
      where pi.id = inspection_items.inspection_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.property_inspections pi
      join public.leases l on l.id = pi.lease_id
      where pi.id = inspection_items.inspection_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

create policy inspection_photos_update on public.inspection_photos
  for update
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      join public.leases l on l.id = pi.lease_id
      where ii.id = inspection_photos.inspection_item_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      join public.leases l on l.id = pi.lease_id
      where ii.id = inspection_photos.inspection_item_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

-- DELETE --------------------------------------------------------------------
-- Le trigger prevent_finalized_* bloque toute suppression une fois finalisé,
-- quelle que soit la policy ci-dessous.

create policy property_inspections_delete on public.property_inspections
  for delete
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'delete'))
    or (
      document_status = 'brouillon'
      and created_by_tenant = true
      and exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
    )
  );

create policy inspection_items_delete on public.inspection_items
  for delete
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'delete'))
    or exists (
      select 1 from public.property_inspections pi
      join public.leases l on l.id = pi.lease_id
      where pi.id = inspection_items.inspection_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

create policy inspection_photos_delete on public.inspection_photos
  for delete
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'delete'))
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      join public.leases l on l.id = pi.lease_id
      where ii.id = inspection_photos.inspection_item_id
        and pi.document_status = 'brouillon'
        and pi.created_by_tenant = true
        and l.tenant_account_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- 7. SUPABASE STORAGE — bucket privé + policies.
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('inspection-photos', 'inspection-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Chemin : {organization_id}/{inspection_id}/{inspection_item_id}/{uuid}.{ext}
-- storage.foldername(name) découpe le chemin : [1]=organization_id,
-- [2]=inspection_id, [3]=inspection_item_id (filename exclu).

create policy inspection_photos_storage_select on storage.objects
  for select
  using (
    bucket_id = 'inspection-photos'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text)
      or exists (
        select 1 from public.property_inspections pi
        left join public.leases l on l.id = pi.lease_id
        left join public.reservations r on r.id = pi.reservation_id
        where pi.id::text = (storage.foldername(name))[2]
          and (l.tenant_account_id = auth.uid() or r.tenant_account_id = auth.uid())
      )
    )
  );

create policy inspection_photos_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'inspection-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('property_inspections', 'update')
      )
      or exists (
        select 1 from public.property_inspections pi
        join public.leases l on l.id = pi.lease_id
        where pi.id::text = (storage.foldername(name))[2]
          and pi.document_status = 'brouillon'
          and pi.created_by_tenant = true
          and l.tenant_account_id = auth.uid()
          and (storage.foldername(name))[1] = pi.organization_id::text
      )
    )
  );

create policy inspection_photos_storage_delete on storage.objects
  for delete
  using (
    bucket_id = 'inspection-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('property_inspections', 'delete')
      )
      or exists (
        select 1 from public.property_inspections pi
        join public.leases l on l.id = pi.lease_id
        where pi.id::text = (storage.foldername(name))[2]
          and pi.document_status = 'brouillon'
          and pi.created_by_tenant = true
          and l.tenant_account_id = auth.uid()
      )
    )
  );

-- Pas de policy UPDATE sur storage.objects : un fichier envoyé n'est jamais
-- remplacé en place, une correction passe par suppression + nouvel upload
-- (cohérent avec l'immutabilité de uploaded_at et des photos en base).
