-- ============================================================================
-- MODULE 11 — Modèle d'abonnement (Phase 2, premier volet).
--
-- Décisions actées (conversation de conception, pas codées en dur ici sauf
-- mention explicite) :
--   - Abonnement mensuel par palier de biens gérés, pas de commission sur
--     les loyers.
--   - Essai gratuit, durée variable par palier (14 à 30 jours selon le cas)
--     — jamais un nombre fixe en dur : trial_days vit sur le palier
--     (ajustable sans migration), trial_ends_at est figé sur l'abonnement
--     au moment de sa création et ne bouge plus si trial_days change après
--     coup sur le palier.
--   - Paliers stockés en table modifiable — Starter/Croissance/Pro
--     ci-dessous, quantités et prix à considérer comme des valeurs de
--     démarrage ajustables par simple UPDATE, pas des constantes de code.
--   - Facturation encore manuelle : aucune policy d'écriture sur
--     organization_subscriptions pour les organisations elles-mêmes (même
--     patron que organizations : gestion via un accès de confiance
--     jusqu'à ce qu'un flux self-service existe).
--
-- La limite de biens par palier est appliquée par un trigger BEFORE INSERT
-- sur properties (pas seulement côté écran) — même discipline que le reste
-- du schéma : RLS/triggers font autorité, l'écran ne fait que refléter.
-- Le trigger ne code aucun nombre en dur, il lit toujours
-- subscription_plans.max_properties via l'abonnement courant de
-- l'organisation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CATALOGUE DES PALIERS.
-- ----------------------------------------------------------------------------

create table public.subscription_plans (
  id             uuid primary key default gen_random_uuid(),
  code           text not null unique,
  name           text not null,
  -- NULL = illimité (palier le plus haut).
  max_properties integer check (max_properties is null or max_properties > 0),
  trial_days     integer not null default 14 check (trial_days > 0),
  monthly_price  numeric(12, 2) not null check (monthly_price >= 0),
  is_active      boolean not null default true,
  sort_order     integer not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create trigger trg_subscription_plans_updated_at
  before update on public.subscription_plans
  for each row execute function private.set_updated_at();

-- Valeurs de démarrage — quantités et prix à ajuster par UPDATE une fois les
-- chiffres réels arrêtés, pas par une nouvelle migration.
insert into public.subscription_plans (code, name, max_properties, trial_days, monthly_price, sort_order) values
  ('starter',    'Starter',    10,   14, 15000, 1),
  ('croissance', 'Croissance', 30,   14, 35000, 2),
  ('pro',        'Pro',        null, 14, 75000, 3);

alter table public.subscription_plans enable row level security;

-- Catalogue plateforme, pas par organisation : lecture ouverte à tout
-- utilisateur authentifié (affichage des paliers disponibles), aucune
-- écriture possible via RLS — même patron que public.permissions.
create policy subscription_plans_select on public.subscription_plans
  for select
  to authenticated
  using (true);

-- ----------------------------------------------------------------------------
-- 2. ABONNEMENT COURANT PAR ORGANISATION.
-- ----------------------------------------------------------------------------

create table public.organization_subscriptions (
  id                    uuid primary key default gen_random_uuid(),
  organization_id       uuid not null unique references public.organizations (id) on delete restrict,
  plan_id               uuid not null references public.subscription_plans (id) on delete restrict,
  status                text not null default 'essai'
                           check (status in ('essai', 'actif', 'impaye', 'suspendu', 'resilie')),
  -- Figé au moment de la création, jamais recalculé depuis plan.trial_days.
  trial_ends_at         timestamptz,
  current_period_start  date,
  current_period_end    date,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create trigger trg_organization_subscriptions_updated_at
  before update on public.organization_subscriptions
  for each row execute function private.set_updated_at();

-- Defense in depth au-delà des RLS, même patron que profiles/tenant_accounts/roles.
create trigger trg_organization_subscriptions_prevent_org_change
  before update on public.organization_subscriptions
  for each row execute function private.prevent_org_change();

alter table public.organization_subscriptions enable row level security;

-- Chaque organisation voit son propre abonnement : information consultable
-- par tout le staff, pas réservée à un rôle précis (pas de has_permission
-- supplémentaire, décision actée en conception).
create policy organization_subscriptions_select on public.organization_subscriptions
  for select
  using (organization_id = private.current_org_id() and private.is_internal());

-- Volontairement aucune policy INSERT/UPDATE/DELETE : facturation encore
-- manuelle, gestion exclusivement via un accès de confiance pour l'instant.

-- ----------------------------------------------------------------------------
-- 3. SEED AUTOMATIQUE À LA CRÉATION D'UNE ORGANISATION.
-- ----------------------------------------------------------------------------

create or replace function private.seed_default_subscription_for_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan_id     uuid;
  v_trial_days  integer;
begin
  select id, trial_days into v_plan_id, v_trial_days
  from public.subscription_plans
  where code = 'starter';

  if not found then
    raise exception 'Palier "starter" introuvable — impossible de créer l''abonnement par défaut'
      using detail = 'organization_subscription.seed.starter_plan_missing', errcode = 'P0001';
  end if;

  insert into public.organization_subscriptions (organization_id, plan_id, status, trial_ends_at)
  values (new.id, v_plan_id, 'essai', now() + (v_trial_days || ' days')::interval);

  return new;
end;
$$;

create trigger trg_seed_default_subscription
  after insert on public.organizations
  for each row execute function private.seed_default_subscription_for_org();

-- ----------------------------------------------------------------------------
-- 4. LIMITE DE BIENS PAR PALIER — trigger, pas un contrôle écran seul.
--
-- Verrouille la ligne organization_subscriptions de l'organisation
-- (FOR UPDATE) avant de compter : deux créations de biens concurrentes pour
-- la même organisation se sérialisent sur ce verrou, la deuxième recompte
-- après que la première a validé/échoué — élimine la condition de course
-- qu'un simple COUNT(*) sans verrou laisserait passer. Aucune limite en dur
-- ici : max_properties est toujours lu depuis le palier courant.
-- ----------------------------------------------------------------------------

create or replace function private.enforce_property_plan_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_properties integer;
  v_current_count  integer;
begin
  select sp.max_properties
  into v_max_properties
  from public.organization_subscriptions os
  join public.subscription_plans sp on sp.id = os.plan_id
  where os.organization_id = new.organization_id
  for update of os;

  if not found then
    raise exception 'Aucun abonnement actif pour cette organisation — impossible de créer un bien'
      using detail = 'property.create.no_subscription', errcode = 'P0001';
  end if;

  if v_max_properties is not null then
    select count(*) into v_current_count
    from public.properties
    where organization_id = new.organization_id;

    if v_current_count >= v_max_properties then
      raise exception 'Limite de biens atteinte pour votre palier d''abonnement (% biens maximum) — changez de palier pour en ajouter davantage', v_max_properties
        using detail = 'property.create.plan_limit_exceeded', errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_properties_enforce_plan_limit
  before insert on public.properties
  for each row execute function private.enforce_property_plan_limit();

-- ----------------------------------------------------------------------------
-- 5. RÉTRO-REMPLISSAGE DES ORGANISATIONS EXISTANTES (dev : Agence Demo,
--    Org Test 6d ; no-op sur un projet vierge comme prod à ce stade).
--
-- Statut 'actif' directement sur le palier le plus haut/illimité, pas de
-- simulation d'essai rétroactif — décision actée en conception.
-- trg_seed_default_subscription ne s'applique qu'aux futures INSERT, donc
-- aucun conflit avec ce rétro-remplissage ciblé sur les lignes déjà là.
-- ----------------------------------------------------------------------------

insert into public.organization_subscriptions (organization_id, plan_id, status, trial_ends_at)
select o.id, (select id from public.subscription_plans where code = 'pro'), 'actif', null
from public.organizations o
where not exists (
  select 1 from public.organization_subscriptions os where os.organization_id = o.id
);
