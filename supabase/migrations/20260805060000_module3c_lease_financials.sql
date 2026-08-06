-- ============================================================================
-- MODULE 3c — COMPLÉMENTS FINANCIERS SUR LEASES
-- Distingue explicitement avance de garantie / loyer prépayé / caution
-- eau-électricité, et pose la structure d'autorisation de consommation de
-- l'avance de garantie (application au Module 5), avec historique dédié.
-- ============================================================================

comment on column public.leases.security_deposit_amount is
  'Avance de garantie (garantie de solvabilité / couverture dégâts), PAS un prépaiement de loyer. Non consommable pendant le contrat sauf autorisation explicite (voir advance_consumption_authorized). Consommable uniquement en fin de contrat, sur autorisation du propriétaire/agence.';

alter table public.leases
  -- a) Loyer prépayé : consommé automatiquement dès le début du contrat,
  -- sans autorisation, jusqu'à épuisement.
  add column prepaid_rent_months integer not null default 0
    check (prepaid_rent_months >= 0),
  add column prepaid_rent_amount numeric(12, 2) not null default 0
    check (prepaid_rent_amount >= 0),

  -- b) Clause contractuelle fixée à la création.
  add column payment_timing text
    check (payment_timing in ('prepaye', 'postpaye')),

  -- c) Autorisation de consommation de l'avance de garantie.
  add column advance_consumption_authorized boolean not null default false,
  add column advance_consumption_authorized_at timestamptz,
  add column advance_consumption_authorized_by uuid references public.profiles (id),

  -- d) Indicatif seulement ; security_deposit_amount fait foi en valeur.
  add column security_deposit_months integer
    check (security_deposit_months is null or security_deposit_months >= 0);

-- payment_timing devient obligatoire pour toute nouvelle ligne (table vide
-- actuellement, donc pas de NOT NULL cassé par des lignes existantes).
alter table public.leases
  alter column payment_timing set not null;

-- Cohérence du trio d'autorisation : soit tout est "non autorisé"
-- (false/null/null), soit tout est renseigné ensemble (true/horodatage/qui).
alter table public.leases
  add constraint leases_advance_authorization_consistency check (
    (advance_consumption_authorized = false
      and advance_consumption_authorized_at is null
      and advance_consumption_authorized_by is null)
    or
    (advance_consumption_authorized = true
      and advance_consumption_authorized_at is not null
      and advance_consumption_authorized_by is not null)
  );

-- La personne qui autorise doit appartenir à la même organisation que le
-- bail. profiles_org_id_key (unique (organization_id, id)) existe déjà
-- depuis le Module 1, vérifié en base avant cette migration.
alter table public.leases
  add constraint leases_advance_authorized_by_org_fk
  foreign key (organization_id, advance_consumption_authorized_by)
  references public.profiles (organization_id, id);

-- Nécessaire pour la FK composite de la table d'audit ci-dessous
-- (même situation que properties_org_id_key au Module 3 : leases n'avait
-- encore jamais été référencée par une autre table via organization_id).
alter table public.leases
  add constraint leases_org_id_key unique (organization_id, id);

-- ----------------------------------------------------------------------------
-- TABLE D'AUDIT — historique des autorisations/révocations de consommation
-- de l'avance de garantie. Append-only : aucune policy insert/update/delete,
-- seul le trigger (security definer) peut y écrire. Nécessaire car la
-- contrainte de cohérence ci-dessus efface authorized_at/authorized_by sur
-- leases à la révocation ; sans cette table, la preuve d'une autorisation
-- passée disparaîtrait (risque en cas de litige locataire).
-- ----------------------------------------------------------------------------

create table public.lease_advance_authorization_events (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  lease_id        uuid not null,
  action          text not null check (action in ('authorized', 'revoked')),
  -- Capturé via auth.uid() au moment de l'action, pas via
  -- advance_consumption_authorized_by (effacé à la révocation).
  -- Nullable : une opération via service_role (script, support) n'a pas de
  -- auth.uid() résolu.
  actor_id        uuid,
  occurred_at     timestamptz not null default now(),

  constraint lease_advance_events_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict,

  constraint lease_advance_events_actor_org_fk
    foreign key (organization_id, actor_id)
    references public.profiles (organization_id, id)
);

comment on table public.lease_advance_authorization_events is
  'Historique append-only des autorisations/révocations de consommation de l''avance de garantie. Alimenté uniquement par trigger, jamais directement par l''API.';

create index lease_advance_events_lease_id_idx on public.lease_advance_authorization_events (lease_id);
create index lease_advance_events_org_id_idx on public.lease_advance_authorization_events (organization_id);

create or replace function private.log_lease_advance_authorization_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.advance_consumption_authorized = true and old.advance_consumption_authorized = false then
    insert into public.lease_advance_authorization_events (organization_id, lease_id, action, actor_id, occurred_at)
    values (new.organization_id, new.id, 'authorized', auth.uid(), coalesce(new.advance_consumption_authorized_at, now()));
  elsif new.advance_consumption_authorized = false and old.advance_consumption_authorized = true then
    insert into public.lease_advance_authorization_events (organization_id, lease_id, action, actor_id, occurred_at)
    values (new.organization_id, new.id, 'revoked', auth.uid(), now());
  end if;
  return new;
end;
$$;

create trigger trg_leases_log_advance_authorization_change
  after update of advance_consumption_authorized on public.leases
  for each row execute function private.log_lease_advance_authorization_change();

alter table public.lease_advance_authorization_events enable row level security;

-- Interne de l'organisation : voit tous les événements de son organisation.
-- Locataire : voit uniquement les événements de SES propres baux (jointure
-- vers leases, même principe que leases_select).
create policy lease_advance_events_select on public.lease_advance_authorization_events
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.leases l
      where l.id = lease_advance_authorization_events.lease_id
        and l.tenant_account_id = auth.uid()
    )
  );
