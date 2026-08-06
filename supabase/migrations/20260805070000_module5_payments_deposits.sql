-- ============================================================================
-- MODULE 5 — STRUCTURE DE SUIVI DES PAIEMENTS ET DES CAUTIONS
-- Structure de données uniquement : aucune intégration externe, aucune
-- génération automatique d'échéances.
-- ============================================================================

-- Prérequis pour les FK composites ci-dessous (jamais référencée jusqu'ici).
alter table public.reservations
  add constraint reservations_org_id_key unique (organization_id, id);

-- ----------------------------------------------------------------------------
-- 1. PAYMENT_SCHEDULES — ce qui est dû.
-- ----------------------------------------------------------------------------

create table public.payment_schedules (
  id                uuid primary key default gen_random_uuid(),
  organization_id   uuid not null references public.organizations (id) on delete restrict,
  lease_id          uuid,
  reservation_id    uuid,
  period_start_date date not null,
  period_end_date   date not null,
  amount_due        numeric(12, 2) not null check (amount_due >= 0),
  due_date          date not null,
  status            text not null default 'en_attente'
                       check (status in ('en_attente', 'payee', 'partiellement_payee', 'en_retard', 'annulee')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  constraint payment_schedules_org_id_key unique (organization_id, id),

  constraint payment_schedules_period_valid
    check (period_end_date > period_start_date),

  -- Exactement un des deux : lease_id OU reservation_id, jamais les deux ni aucun.
  constraint payment_schedules_exactly_one_link check (
    (lease_id is not null and reservation_id is null)
    or (lease_id is null and reservation_id is not null)
  ),

  constraint payment_schedules_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint payment_schedules_reservation_org_fk
    foreign key (organization_id, reservation_id)
    references public.reservations (organization_id, id)
    on delete restrict
);

comment on table public.payment_schedules is
  'Échéances dues (loyer ou réservation). Pour un bail, la génération suivra payment_frequency/payment_timing du contrat — pas construite dans ce module (structure uniquement).';

create index payment_schedules_organization_id_idx on public.payment_schedules (organization_id);
create index payment_schedules_lease_id_idx on public.payment_schedules (lease_id);
create index payment_schedules_reservation_id_idx on public.payment_schedules (reservation_id);

create trigger trg_payment_schedules_updated_at
  before update on public.payment_schedules
  for each row execute function private.set_updated_at();

create trigger trg_payment_schedules_prevent_org_change
  before update on public.payment_schedules
  for each row execute function private.prevent_org_change();

-- ----------------------------------------------------------------------------
-- 2. PAYMENTS — mouvements de trésorerie réels.
-- ----------------------------------------------------------------------------

create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete restrict,
  lease_id            uuid,
  reservation_id      uuid,
  payment_schedule_id uuid,
  amount              numeric(12, 2) not null check (amount >= 0),
  payment_date        date not null default current_date,
  method              text not null check (method in ('mobile_money', 'carte', 'especes', 'virement')),
  external_reference  text,
  payment_type        text not null check (payment_type in (
                         'loyer', 'avance_garantie', 'loyer_prepaye',
                         'caution_utilities', 'remboursement_caution', 'imputation'
                       )),
  direction           text not null check (direction in ('entrant', 'sortant')),
  status              text not null default 'en_attente'
                         check (status in ('en_attente', 'confirme', 'echoue', 'rembourse')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),

  constraint payments_org_id_key unique (organization_id, id),

  constraint payments_exactly_one_link check (
    (lease_id is not null and reservation_id is null)
    or (lease_id is null and reservation_id is not null)
  ),

  -- Seul remboursement_caution est sortant ; tout le reste est entrant.
  constraint payments_direction_matches_type check (
    (payment_type = 'remboursement_caution' and direction = 'sortant')
    or (payment_type <> 'remboursement_caution' and direction = 'entrant')
  ),

  constraint payments_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint payments_reservation_org_fk
    foreign key (organization_id, reservation_id)
    references public.reservations (organization_id, id)
    on delete restrict,

  constraint payments_schedule_org_fk
    foreign key (organization_id, payment_schedule_id)
    references public.payment_schedules (organization_id, id)
    on delete restrict
);

comment on table public.payments is
  'Mouvements de trésorerie réels, quelle que soit l''origine. lease_id/reservation_id identifient toujours le contrat concerné (même sans payment_schedule_id, ex: dépôt de caution).';

create index payments_organization_id_idx on public.payments (organization_id);
create index payments_lease_id_idx on public.payments (lease_id);
create index payments_reservation_id_idx on public.payments (reservation_id);
create index payments_payment_schedule_id_idx on public.payments (payment_schedule_id);

create trigger trg_payments_updated_at
  before update on public.payments
  for each row execute function private.set_updated_at();

create trigger trg_payments_prevent_org_change
  before update on public.payments
  for each row execute function private.prevent_org_change();

-- Si payment_schedule_id est renseigné, il doit référencer le MÊME
-- bail/réservation que le paiement lui-même.
create or replace function private.validate_payment_schedule_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_schedule_lease_id       uuid;
  v_schedule_reservation_id uuid;
begin
  if new.payment_schedule_id is null then
    return new;
  end if;

  select lease_id, reservation_id into v_schedule_lease_id, v_schedule_reservation_id
  from public.payment_schedules
  where id = new.payment_schedule_id;

  if v_schedule_lease_id is distinct from new.lease_id
     or v_schedule_reservation_id is distinct from new.reservation_id then
    raise exception
      'Incohérence : le paiement % et son échéance % ne référencent pas le même bail/réservation',
      new.id, new.payment_schedule_id;
  end if;

  return new;
end;
$$;

create trigger trg_payments_validate_schedule_consistency
  before insert or update of lease_id, reservation_id, payment_schedule_id on public.payments
  for each row execute function private.validate_payment_schedule_consistency();

-- ----------------------------------------------------------------------------
-- 3. DEPOSIT_LEDGER — suivi des cautions, append-only (aucune policy
--    update/delete plus bas : les corrections se font par nouvelle écriture,
--    jamais par modification de l'historique).
-- ----------------------------------------------------------------------------

create table public.deposit_ledger (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     uuid not null references public.organizations (id) on delete restrict,
  lease_id            uuid,
  reservation_id      uuid,
  deposit_type        text not null check (deposit_type in ('avance_garantie', 'caution_utilities')),
  entry_type          text not null check (entry_type in ('depot_initial', 'imputation', 'remboursement')),
  -- Motif métier de l'imputation : source de vérité pour l'autorisation
  -- (avance_consumption_authorized) ET pour le reporting par motif.
  -- Obligatoire pour une imputation, null sinon.
  imputation_category text
                         check (imputation_category in ('loyer', 'degats', 'impayes_utilities')),
  amount              numeric(12, 2) not null check (amount >= 0),
  -- Motif libre obligatoire pour une imputation (traçabilité litige).
  reason              text,
  -- Lien fonctionnel vers l'échéance soldée. Sémantiquement requis pour une
  -- imputation de catégorie 'loyer' (voir contrainte plus bas) ; ne porte
  -- plus la décision d'autorisation (c'est imputation_category qui la porte).
  payment_schedule_id uuid,
  -- Lie le dépôt initial ou le remboursement au mouvement de trésorerie
  -- correspondant dans payments.
  payment_id          uuid,
  created_at          timestamptz not null default now(),

  constraint deposit_ledger_exactly_one_link check (
    (lease_id is not null and reservation_id is null)
    or (lease_id is null and reservation_id is not null)
  ),

  constraint deposit_ledger_reason_required_for_imputation
    check (entry_type <> 'imputation' or reason is not null),

  constraint deposit_ledger_category_required_for_imputation check (
    (entry_type = 'imputation' and imputation_category is not null)
    or (entry_type <> 'imputation' and imputation_category is null)
  ),

  -- Une imputation de loyer doit obligatoirement solder une échéance précise.
  constraint deposit_ledger_loyer_requires_schedule check (
    imputation_category is distinct from 'loyer' or payment_schedule_id is not null
  ),

  constraint deposit_ledger_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint deposit_ledger_reservation_org_fk
    foreign key (organization_id, reservation_id)
    references public.reservations (organization_id, id)
    on delete restrict,

  constraint deposit_ledger_schedule_org_fk
    foreign key (organization_id, payment_schedule_id)
    references public.payment_schedules (organization_id, id)
    on delete restrict,

  constraint deposit_ledger_payment_org_fk
    foreign key (organization_id, payment_id)
    references public.payments (organization_id, id)
    on delete restrict
);

comment on table public.deposit_ledger is
  'Historique append-only des mouvements de caution (avance de garantie, caution eau/électricité). Solde calculé à la volée via deposit_ledger_balances, jamais matérialisé.';

create index deposit_ledger_organization_id_idx on public.deposit_ledger (organization_id);
create index deposit_ledger_lease_id_idx on public.deposit_ledger (lease_id);
create index deposit_ledger_reservation_id_idx on public.deposit_ledger (reservation_id);

-- Le total imputations + remboursement ne doit jamais dépasser le montant
-- détenu. Sérialisé par verrou consultatif transactionnel pour éviter
-- qu'une lecture concurrente du solde ne permette un dépassement (deux
-- imputations simultanées liraient sinon le même solde disponible et
-- passeraient toutes les deux — race condition classique check-then-act
-- non protégée par le niveau d'isolation READ COMMITTED par défaut).
create or replace function private.validate_deposit_ledger_balance()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_held     numeric(12, 2);
  v_consumed numeric(12, 2);
begin
  if new.entry_type = 'depot_initial' then
    return new;
  end if;

  -- Verrou scopé à (lease_id ou reservation_id, deposit_type) : les
  -- imputations sur des baux différents restent totalement concurrentes.
  -- Espace de verrouillage séparé de leases/reservations (pas de
  -- SELECT ... FOR UPDATE sur ces tables) pour ne pas interférer avec
  -- leurs propres triggers et ne pas augmenter la surface de deadlock.
  perform pg_advisory_xact_lock(
    hashtextextended(
      coalesce(new.lease_id::text, '') || '|' || coalesce(new.reservation_id::text, '') || '|' || new.deposit_type,
      0
    )
  );

  select
    coalesce(sum(amount) filter (where entry_type = 'depot_initial'), 0),
    coalesce(sum(amount) filter (where entry_type in ('imputation', 'remboursement')), 0)
  into v_held, v_consumed
  from public.deposit_ledger
  where organization_id = new.organization_id
    and lease_id is not distinct from new.lease_id
    and reservation_id is not distinct from new.reservation_id
    and deposit_type = new.deposit_type;

  if v_consumed + new.amount > v_held then
    raise exception
      'Imputation/remboursement refusé : solde insuffisant (détenu %, déjà consommé %, tentative %)',
      v_held, v_consumed, new.amount;
  end if;

  return new;
end;
$$;

create trigger trg_deposit_ledger_validate_balance
  before insert on public.deposit_ledger
  for each row execute function private.validate_deposit_ledger_balance();

-- Une imputation de catégorie 'loyer' sur l'avance de garantie exige
-- leases.advance_consumption_authorized = true. 'degats' et
-- 'impayes_utilities' restent libres, sans autorisation.
create or replace function private.validate_deposit_ledger_rent_imputation_authorized()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_authorized boolean;
begin
  if new.entry_type <> 'imputation'
     or coalesce(new.imputation_category, '') <> 'loyer'
     or new.deposit_type <> 'avance_garantie' then
    return new;
  end if;

  if new.lease_id is null then
    raise exception 'Imputation de loyer sur avance de garantie impossible : uniquement applicable à un bail (lease_id requis)';
  end if;

  select advance_consumption_authorized into v_authorized
  from public.leases
  where id = new.lease_id;

  if not coalesce(v_authorized, false) then
    raise exception 'Imputation de loyer refusée : la consommation de l''avance de garantie n''est pas autorisée pour ce bail (leases.advance_consumption_authorized = false)';
  end if;

  return new;
end;
$$;

create trigger trg_deposit_ledger_validate_rent_imputation_authorized
  before insert on public.deposit_ledger
  for each row execute function private.validate_deposit_ledger_rent_imputation_authorized();

-- Solde calculé à la volée.
create view public.deposit_ledger_balances
with (security_invoker = true)
as
select
  organization_id,
  lease_id,
  reservation_id,
  deposit_type,
  coalesce(sum(amount) filter (where entry_type = 'depot_initial'), 0) as amount_held,
  coalesce(sum(amount) filter (where entry_type = 'imputation'), 0) as total_imputed,
  coalesce(sum(amount) filter (where entry_type = 'remboursement'), 0) as total_refunded,
  coalesce(sum(amount) filter (where entry_type = 'depot_initial'), 0)
    - coalesce(sum(amount) filter (where entry_type in ('imputation', 'remboursement')), 0) as balance
from public.deposit_ledger
group by organization_id, lease_id, reservation_id, deposit_type;

grant select on public.deposit_ledger_balances to authenticated;

-- ----------------------------------------------------------------------------
-- CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('payment_schedules', 'create', 'Créer une échéance de paiement'),
  ('payment_schedules', 'read',   'Consulter les échéances de paiement'),
  ('payment_schedules', 'update', 'Modifier une échéance de paiement'),
  ('payment_schedules', 'delete', 'Supprimer une échéance de paiement'),
  ('payments', 'create', 'Enregistrer un paiement'),
  ('payments', 'read',   'Consulter les paiements'),
  ('payments', 'update', 'Modifier un paiement'),
  ('payments', 'delete', 'Supprimer un paiement'),
  ('deposit_ledger', 'create', 'Enregistrer un mouvement de caution (dépôt, imputation, remboursement)'),
  ('deposit_ledger', 'read',   'Consulter l''historique et le solde des cautions');

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
    (v_agent_id, 'deposit_ledger', 'read');

  -- Comptable : lecture seule partout, SAUF payments où elle peut aussi
  -- enregistrer un paiement (nouveauté de ce module).
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
    (v_comptable_id, 'deposit_ledger', 'read');

  return new;
end;
$$;

-- Backfill pour les organisations déjà créées.
insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource in ('payment_schedules', 'payments', 'deposit_ledger')
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('payment_schedules', 'create'), ('payment_schedules', 'read'),
  ('payment_schedules', 'update'), ('payment_schedules', 'delete'),
  ('payments', 'create'), ('payments', 'read'),
  ('payments', 'update'), ('payments', 'delete'),
  ('deposit_ledger', 'create'), ('deposit_ledger', 'read')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('payment_schedules', 'read'),
  ('payments', 'read'), ('payments', 'create'),
  ('deposit_ledger', 'read')
) as v(resource, action)
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- ROW LEVEL SECURITY.
-- ----------------------------------------------------------------------------

alter table public.payment_schedules enable row level security;
alter table public.payments enable row level security;
alter table public.deposit_ledger enable row level security;

create policy payment_schedules_select on public.payment_schedules
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = payment_schedules.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = payment_schedules.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy payment_schedules_insert on public.payment_schedules
  for insert
  with check (organization_id = private.current_org_id() and private.has_permission('payment_schedules', 'create'));

create policy payment_schedules_update on public.payment_schedules
  for update
  using (organization_id = private.current_org_id() and private.has_permission('payment_schedules', 'update'))
  with check (organization_id = private.current_org_id());

create policy payment_schedules_delete on public.payment_schedules
  for delete
  using (organization_id = private.current_org_id() and private.has_permission('payment_schedules', 'delete'));

create policy payments_select on public.payments
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = payments.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = payments.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy payments_insert on public.payments
  for insert
  with check (organization_id = private.current_org_id() and private.has_permission('payments', 'create'));

create policy payments_update on public.payments
  for update
  using (organization_id = private.current_org_id() and private.has_permission('payments', 'update'))
  with check (organization_id = private.current_org_id());

create policy payments_delete on public.payments
  for delete
  using (organization_id = private.current_org_id() and private.has_permission('payments', 'delete'));

create policy deposit_ledger_select on public.deposit_ledger
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = deposit_ledger.lease_id and l.tenant_account_id = auth.uid())
    or exists (select 1 from public.reservations r where r.id = deposit_ledger.reservation_id and r.tenant_account_id = auth.uid())
  );

create policy deposit_ledger_insert on public.deposit_ledger
  for insert
  with check (organization_id = private.current_org_id() and private.has_permission('deposit_ledger', 'create'));

-- Pas de policy update/delete : append-only, corrections par nouvelle écriture.
