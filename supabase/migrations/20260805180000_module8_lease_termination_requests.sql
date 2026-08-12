-- ============================================================================
-- MODULE 8 — RÉSILIATION ANTICIPÉE D'UN BAIL, PAR CONSENSUS
-- Le locataire OU le staff peut initier une demande (date de fin souhaitée +
-- motif) ; seule la partie qui n'a PAS initié peut y répondre (accepter /
-- refuser). La résiliation ne devient EFFECTIVE (leases.status='resilie',
-- leases.end_date fixée) que sur acceptation — jamais sur la seule
-- initiative d'une partie, quel que soit qui a initié. N'affecte jamais
-- advance_consumption_authorized (Module 3c) ni le calcul du solde de
-- caution (Modules 5/6/7) : gestes séparés et postérieurs.
--
-- Corrige aussi un trou pré-existant (pas spécifique à la résiliation :
-- jamais traité depuis le Module 5b) : le statut effectif des échéances ne
-- tenait compte ni du statut ni de la date de fin du bail — une échéance
-- postérieure à la fin d'un bail 'resilie' ou 'termine' apparaissait comme
-- normalement active/en retard. Voir section 3.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. LEASE_TERMINATION_REQUESTS.
-- ----------------------------------------------------------------------------

create table public.lease_termination_requests (
  id                       uuid primary key default gen_random_uuid(),
  organization_id          uuid not null references public.organizations (id) on delete restrict,
  lease_id                 uuid not null,
  initiated_by_tenant_id   uuid,
  initiated_by_staff_id    uuid,
  requested_end_date       date not null,
  reason                   text not null,
  status                   text not null default 'en_attente'
                              check (status in ('en_attente', 'validee', 'refusee', 'annulee')),
  -- Renseignés uniquement au moment où la partie répondante tranche
  -- (validee/refusee) — jamais par l'initiateur, jamais avant. Posés par le
  -- trigger de transition ci-dessous, jamais directement par le client.
  responded_by_tenant_id   uuid,
  responded_by_staff_id    uuid,
  response_note            text,
  responded_at             timestamptz,
  -- Renseigné uniquement quand l'initiateur annule sa propre demande, avant
  -- toute réponse.
  cancelled_at             timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint lease_termination_requests_initiator_exactly_one check (
    (initiated_by_tenant_id is not null and initiated_by_staff_id is null)
    or (initiated_by_tenant_id is null and initiated_by_staff_id is not null)
  ),

  -- Tant que la demande n'a pas été tranchée (en_attente/annulee), aucun
  -- champ de réponse n'est renseigné. Dès qu'elle l'est (validee/refusee),
  -- le répondant est EXACTEMENT la partie opposée à l'initiateur — empêche
  -- structurellement qu'une partie réponde à sa propre demande.
  constraint lease_termination_requests_response_consistency check (
    (status in ('en_attente', 'annulee')
      and responded_at is null
      and responded_by_tenant_id is null
      and responded_by_staff_id is null)
    or
    (status in ('validee', 'refusee')
      and responded_at is not null
      and (
        (initiated_by_tenant_id is not null and responded_by_staff_id is not null and responded_by_tenant_id is null)
        or (initiated_by_staff_id is not null and responded_by_tenant_id is not null and responded_by_staff_id is null)
      ))
  ),

  constraint lease_termination_requests_response_note_requires_response check (
    response_note is null or status in ('validee', 'refusee')
  ),

  constraint lease_termination_requests_cancelled_consistency check (
    (status = 'annulee' and cancelled_at is not null)
    or (status <> 'annulee' and cancelled_at is null)
  ),

  constraint lease_termination_requests_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint lease_termination_requests_staff_org_fk
    foreign key (organization_id, initiated_by_staff_id)
    references public.profiles (organization_id, id),

  constraint lease_termination_requests_responded_staff_org_fk
    foreign key (organization_id, responded_by_staff_id)
    references public.profiles (organization_id, id),

  -- tenant_accounts n'a plus organization_id depuis le Module 1b : FK
  -- simple, comme leases.tenant_account_id et
  -- maintenance_tickets.reported_by_tenant_id.
  constraint lease_termination_requests_initiated_tenant_fkey
    foreign key (initiated_by_tenant_id) references public.tenant_accounts (id),

  constraint lease_termination_requests_responded_tenant_fkey
    foreign key (responded_by_tenant_id) references public.tenant_accounts (id)
);

comment on table public.lease_termination_requests is
  'Résiliation anticipée d''un bail par CONSENSUS obligatoire : la partie initiatrice propose une date de fin et un motif, seule l''autre partie peut accepter ou refuser. Effective (leases.status=''resilie'', leases.end_date fixée) uniquement sur acceptation, jamais sur la seule initiative d''une partie. N''affecte jamais advance_consumption_authorized (Module 3c) ni le calcul du solde de caution (dépend de l''état des lieux de sortie et de deposit_ledger, Modules 5/6/7) : gestes séparés et postérieurs.';

comment on column public.lease_termination_requests.status is
  'en_attente (défaut) -> validee | refusee | annulee, terminal dans les 3 cas. Un refus ne rouvre pas la même ligne (pas de retour vers en_attente) : une nouvelle demande peut être ouverte dès que celle-ci est tranchée/annulée (index partiel one_pending_per_lease).';

-- Une seule demande ouverte à la fois par bail : un refus ou une annulation
-- libère la voie pour une nouvelle demande.
create unique index lease_termination_requests_one_pending_per_lease
  on public.lease_termination_requests (lease_id)
  where status = 'en_attente';

create index lease_termination_requests_organization_id_idx on public.lease_termination_requests (organization_id);
create index lease_termination_requests_lease_id_idx on public.lease_termination_requests (lease_id);
create index lease_termination_requests_status_idx on public.lease_termination_requests (status);

create trigger trg_lease_termination_requests_updated_at
  before update on public.lease_termination_requests
  for each row execute function private.set_updated_at();

-- organization_id, lease_id, identité de l'initiateur, date de fin
-- souhaitée et motif : immuables après création. Pas de révision d'une
-- demande en cours — pour changer les termes, l'initiateur annule et en
-- crée une nouvelle (même principe que prevent_maintenance_ticket_identity_change,
-- étendu ici à requested_end_date/reason pour qu'aucune des deux parties ne
-- puisse changer les termes d'une demande que l'autre est en train
-- d'examiner).
create or replace function private.prevent_lease_termination_request_identity_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.lease_id is distinct from old.lease_id
     or new.initiated_by_tenant_id is distinct from old.initiated_by_tenant_id
     or new.initiated_by_staff_id is distinct from old.initiated_by_staff_id
     or new.requested_end_date is distinct from old.requested_end_date
     or new.reason is distinct from old.reason
  then
    raise exception 'organization_id, lease_id, l''identité de l''initiateur, la date de fin souhaitée et le motif sont immuables après création : pour changer ces termes, annulez cette demande et créez-en une nouvelle'
      using detail = 'lease_termination_request.identity.immutable', errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_lease_termination_requests_prevent_identity_change
  before update on public.lease_termination_requests
  for each row execute function private.prevent_lease_termination_request_identity_change();

-- À l'insertion : le bail doit être actif, la date de fin souhaitée ne peut
-- être ni antérieure au début du bail ni rétroactive (< aujourd'hui), et un
-- locataire initiateur doit être le locataire de CE bail.
create or replace function private.validate_lease_termination_request_state()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_lease record;
begin
  select status, start_date, tenant_account_id, organization_id
    into v_lease
  from public.leases
  where id = new.lease_id;

  if v_lease is null or v_lease.organization_id is distinct from new.organization_id then
    raise exception 'Bail introuvable dans cette organisation'
      using detail = 'lease_termination_request.lease.not_found', errcode = 'P0001';
  end if;

  if v_lease.status <> 'actif' then
    raise exception 'Résiliation impossible : ce bail n''est pas actif (statut actuel: %)', v_lease.status
      using detail = 'lease_termination_request.lease.not_active', errcode = 'P0001';
  end if;

  if new.requested_end_date < v_lease.start_date then
    raise exception 'La date de fin souhaitée ne peut pas être antérieure à la date de début du bail (%)', v_lease.start_date
      using detail = 'lease_termination_request.requested_end_date.before_lease_start', errcode = 'P0001';
  end if;

  if new.requested_end_date < current_date then
    raise exception 'La date de fin souhaitée ne peut pas être antérieure à aujourd''hui : aucune résiliation rétroactive'
      using detail = 'lease_termination_request.requested_end_date.retroactive', errcode = 'P0001';
  end if;

  if new.initiated_by_tenant_id is not null and new.initiated_by_tenant_id is distinct from v_lease.tenant_account_id then
    raise exception 'Le locataire initiateur doit être le locataire de ce bail'
      using detail = 'lease_termination_request.initiator.tenant_mismatch', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_lease_termination_requests_validate_lease_state
  before insert on public.lease_termination_requests
  for each row execute function private.validate_lease_termination_request_state();

-- Cœur du state machine. Seules 3 transitions existent, toutes depuis
-- en_attente : -> annulee (par l'auteur uniquement), -> validee / refusee
-- (par la partie qui n'a PAS initié, uniquement). Rejette toute autre
-- tentative de transition et toute modification directe des champs de
-- réponse (posés ici, jamais par le client).
create or replace function private.validate_lease_termination_request_transition()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_tenant_initiated boolean;
  v_lease_tenant_id  uuid;
begin
  if new.status is distinct from old.status then
    if old.status <> 'en_attente' then
      raise exception 'Cette demande de résiliation est déjà tranchée (statut: %) : aucune transition supplémentaire n''est possible', old.status
        using detail = 'lease_termination_request.transition.already_settled', errcode = 'P0001';
    end if;

    v_tenant_initiated := old.initiated_by_tenant_id is not null;

    if new.status = 'annulee' then
      if (v_tenant_initiated and auth.uid() is distinct from old.initiated_by_tenant_id)
         or (not v_tenant_initiated and auth.uid() is distinct from old.initiated_by_staff_id)
      then
        raise exception 'Seul l''auteur de la demande peut l''annuler'
          using detail = 'lease_termination_request.cancel.not_initiator', errcode = 'P0001';
      end if;

      new.cancelled_at := now();
      return new;
    end if;

    if new.status in ('validee', 'refusee') then
      select tenant_account_id into v_lease_tenant_id
      from public.leases where id = old.lease_id;

      if v_tenant_initiated then
        -- Initié par le locataire : seul un profil interne autorisé
        -- (has_permission) peut répondre. Structurellement jamais vrai pour
        -- un locataire (aucune ligne profiles/user_roles).
        if not private.has_permission('lease_termination_requests', 'update') then
          raise exception 'Seul un profil interne autorisé peut répondre à cette demande'
            using detail = 'lease_termination_request.respond.not_authorized_staff', errcode = 'P0001';
        end if;
        new.responded_by_staff_id := auth.uid();
        new.responded_by_tenant_id := null;
      else
        -- Initié par le staff : seul le locataire de CE bail peut répondre.
        if auth.uid() is distinct from v_lease_tenant_id then
          raise exception 'Seul le locataire de ce bail peut répondre à cette demande'
            using detail = 'lease_termination_request.respond.not_tenant', errcode = 'P0001';
        end if;
        new.responded_by_tenant_id := auth.uid();
        new.responded_by_staff_id := null;
      end if;

      new.responded_at := now();
      return new;
    end if;

    raise exception 'Transition de statut invalide : % -> %', old.status, new.status
      using detail = 'lease_termination_request.transition.invalid', errcode = 'P0001';
  end if;

  -- status inchangé : les champs de réponse/annulation ne sont jamais
  -- modifiables autrement que par une transition (ci-dessus).
  if new.responded_at is distinct from old.responded_at
     or new.responded_by_tenant_id is distinct from old.responded_by_tenant_id
     or new.responded_by_staff_id is distinct from old.responded_by_staff_id
     or new.cancelled_at is distinct from old.cancelled_at
     or new.response_note is distinct from old.response_note
  then
    raise exception 'responded_at, responded_by_*, cancelled_at et response_note sont posés uniquement au moment d''une transition de statut, jamais modifiables directement'
      using detail = 'lease_termination_request.response_fields.server_only', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_lease_termination_requests_validate_transition
  before update on public.lease_termination_requests
  for each row execute function private.validate_lease_termination_request_transition();

-- Applique l'effet réel de la résiliation UNIQUEMENT au passage à 'validee'.
-- security definer nécessaire : c'est parfois le LOCATAIRE qui déclenche ce
-- passage (cas où le staff avait initié), sans avoir la permission
-- leases.update. Même principe que log_lease_advance_authorization_change
-- (Module 3c). Revérifie server-side que le bail est toujours actif
-- (défense en profondeur ; en pratique déjà garanti par
-- one_pending_per_lease, qui empêche toute demande concurrente).
create or replace function private.apply_effective_lease_termination()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'validee' and old.status is distinct from 'validee' then
    update public.leases
    set status = 'resilie', end_date = new.requested_end_date
    where id = new.lease_id and status = 'actif';

    if not found then
      raise exception 'Résiliation refusée : le bail % n''est plus actif (déjà résilié ou terminé entre-temps)', new.lease_id
        using detail = 'lease_termination_request.apply.lease_no_longer_active', errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_lease_termination_requests_apply_effective_termination
  after update on public.lease_termination_requests
  for each row execute function private.apply_effective_lease_termination();

-- ----------------------------------------------------------------------------
-- 2. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('lease_termination_requests', 'create', 'Initier une demande de résiliation anticipée de bail'),
  ('lease_termination_requests', 'read',   'Consulter les demandes de résiliation anticipée'),
  ('lease_termination_requests', 'update', 'Répondre à une demande de résiliation anticipée (accepter/refuser)');

-- Pas d'action 'delete' : aucune suppression, seulement des transitions de
-- statut — valeur de preuve en cas de litige, même logique que les tables
-- d'audit des Modules 3c/6d.

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
    (v_agent_id, 'lease_termination_requests', 'update');

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
    (v_comptable_id, 'lease_termination_requests', 'read');

  return new;
end;
$$;

insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'lease_termination_requests'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('lease_termination_requests', 'create'), ('lease_termination_requests', 'read'), ('lease_termination_requests', 'update')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'lease_termination_requests', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 3. ROW LEVEL SECURITY.
-- ----------------------------------------------------------------------------

alter table public.lease_termination_requests enable row level security;

create policy lease_termination_requests_select on public.lease_termination_requests
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id
        and l.tenant_account_id = auth.uid()
    )
  );

create policy lease_termination_requests_insert on public.lease_termination_requests
  for insert
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('lease_termination_requests', 'create')
      and initiated_by_staff_id = auth.uid()
      and initiated_by_tenant_id is null
      and status = 'en_attente'
    )
    or (
      initiated_by_tenant_id = auth.uid()
      and initiated_by_staff_id is null
      and status = 'en_attente'
      and exists (
        select 1 from public.leases l
        where l.id = lease_termination_requests.lease_id
          and l.tenant_account_id = auth.uid()
      )
    )
  );

-- Volontairement large : la légitimité précise de chaque transition (qui
-- peut faire quoi) est portée par les triggers ci-dessus, pas par cette
-- policy (RLS ne peut pas comparer OLD/NEW dans WITH CHECK) — même principe
-- que property_inspections_update (Module 6).
create policy lease_termination_requests_update on public.lease_termination_requests
  for update
  using (
    (organization_id = private.current_org_id() and private.has_permission('lease_termination_requests', 'update'))
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id
        and l.tenant_account_id = auth.uid()
    )
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('lease_termination_requests', 'update'))
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id
        and l.tenant_account_id = auth.uid()
    )
  );

-- Pas de policy DELETE : aucune suppression possible (voir plus haut).

-- ----------------------------------------------------------------------------
-- 4. MODULE 5b — STATUT EFFECTIF DES ÉCHÉANCES : tenir compte du bail.
-- Une échéance dont la période démarre après la fin d'un bail non-actif
-- (resilie ou termine) n'est plus une dette réelle : nouveau statut calculé
-- 'hors_periode', sans jamais écrire sur payment_schedules (toujours calculé
-- à la volée, comme le reste de ce statut). Ne s'applique pas si l'échéance
-- est déjà couverte (payee prime toujours) : on ne réétiquette jamais un
-- règlement réellement encaissé.
-- ----------------------------------------------------------------------------

-- La vue dépend de l'ancienne signature (4 arguments) : il faut la
-- supprimer avant de pouvoir supprimer la fonction, sinon Postgres refuse
-- (objet dépendant). Recréée juste en dessous.
drop view if exists public.payment_schedules_effective_status;

drop function if exists private.payment_schedule_effective_status(text, numeric, date, numeric);

create or replace function private.payment_schedule_effective_status(
  p_status            text,
  p_amount_due        numeric,
  p_due_date          date,
  p_covered_amount    numeric,
  p_period_start_date date,
  p_lease_status      text,
  p_lease_end_date    date
)
returns text
language sql
stable
as $$
  select case
    when p_status = 'annulee' then 'annulee'
    when p_covered_amount >= p_amount_due then 'payee'
    when p_lease_status is not null
         and p_lease_status <> 'actif'
         and p_lease_end_date is not null
         and p_period_start_date > p_lease_end_date
      then 'hors_periode'
    when p_covered_amount > 0 then 'partiellement_payee'
    when p_due_date < current_date then 'en_retard'
    else 'en_attente'
  end
$$;

comment on function private.payment_schedule_effective_status is
  'Source unique de vérité du statut effectif d''une échéance, calculé à la volée. ''hors_periode'' (Module 8) : la période de cette échéance démarre après la fin d''un bail non-actif (resilie/termine) — ne prime que sur payee/partiellement_payee/en_retard/en_attente, jamais sur une échéance déjà couverte (payee prime toujours, aucun règlement réellement encaissé n''est réétiqueté).';

create view public.payment_schedules_effective_status
with (security_invoker = true)
as
select
  ps.*,
  coalesce(pay.total_confirmed, 0) + coalesce(imp.total_imputed, 0) as covered_amount,
  private.payment_schedule_effective_status(
    ps.status, ps.amount_due, ps.due_date,
    coalesce(pay.total_confirmed, 0) + coalesce(imp.total_imputed, 0),
    ps.period_start_date, l.status, l.end_date
  ) as effective_status
from public.payment_schedules ps
-- lease_id est NULL pour les échéances liées à une réservation : LEFT JOIN,
-- l.status/l.end_date valent alors NULL et le nouveau court-circuit
-- 'hors_periode' ne s'applique jamais à ces lignes.
left join public.leases l on l.id = ps.lease_id
left join (
  select payment_schedule_id, sum(amount) as total_confirmed
  from public.payments
  where status = 'confirme' and payment_schedule_id is not null
  group by payment_schedule_id
) pay on pay.payment_schedule_id = ps.id
left join (
  select payment_schedule_id, sum(amount) as total_imputed
  from public.deposit_ledger
  where entry_type = 'imputation' and payment_schedule_id is not null
  group by payment_schedule_id
) imp on imp.payment_schedule_id = ps.id;

grant select on public.payment_schedules_effective_status to authenticated;
