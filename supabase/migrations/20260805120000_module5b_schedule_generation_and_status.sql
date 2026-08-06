-- ============================================================================
-- MODULE 5b — GÉNÉRATION DES ÉCHÉANCES ET STATUT EFFECTIF
-- Rend la chaîne financière du Module 5 opérationnelle : génération des
-- payment_schedules depuis un bail (avec jour de facturation fixe optionnel
-- et période de raccordement), statut calculé à la volée à partir
-- exclusivement de vraies lignes payments/deposit_ledger — une seule source
-- de vérité, y compris pour le loyer prépayé.
-- ============================================================================

-- Nécessaire pour l'idempotence de la génération : un même bail ne peut
-- jamais avoir deux échéances pour la même période de départ. Une contrainte
-- classique (pas partielle) : les lignes liées à une réservation ont
-- lease_id = NULL, donc jamais en conflit entre elles via cette contrainte.
alter table public.payment_schedules
  add constraint payment_schedules_lease_period_unique unique (lease_id, period_start_date);

-- payment_schedules.status ne porte plus que la décision manuelle
-- ('en_attente' à la création, 'annulee' si annulée) : les trois autres
-- valeurs (payee/partiellement_payee/en_retard) ne sont jamais écrites dans
-- cette colonne, elles n'existent que dans payment_schedules_effective_status
-- ci-dessous. Resserrer le CHECK maintenant (table encore vide) évite qu'un
-- futur développeur interrogeant cette colonne brute croie à un bug en n'y
-- voyant jamais 'payee' ni 'en_retard'.
alter table public.payment_schedules
  drop constraint payment_schedules_status_check;

alter table public.payment_schedules
  add constraint payment_schedules_status_check
  check (status in ('en_attente', 'annulee'));

comment on column public.payment_schedules.status is
  'Décision manuelle uniquement : ''en_attente'' (défaut) ou ''annulee''. Ne reflète jamais payee/partiellement_payee/en_retard — le statut réel se lit dans la vue payment_schedules_effective_status.effective_status, calculé à partir des paiements confirmés et imputations réels, jamais dans cette colonne.';

-- Signale la période de raccordement générée quand la date d'entrée ne
-- tombe pas sur le jour de facturation fixe (voir section 3). Permet au
-- staff de repérer facilement quelle échéance mérite une vérification du
-- montant proratisé, sans avoir à comparer les dates à la main.
alter table public.payment_schedules
  add column is_partial_period boolean not null default false;

-- amount_due reste librement modifiable AVANT tout règlement (c'est le cas
-- d'usage légitime de la négociation sur la période de raccordement), mais
-- se fige dès qu'un paiement confirmé ou une imputation de loyer est
-- rattaché : au-delà, une correction passe par une écriture explicite
-- (avoir, imputation), jamais par réécriture du montant dû — sinon le
-- statut effectif basculerait silencieusement de 'payee' à
-- 'partiellement_payee' sans aucune trace expliquant pourquoi.
create or replace function private.prevent_amount_due_change_once_settled()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_has_settlement boolean;
begin
  if new.amount_due is distinct from old.amount_due then
    select
      exists (select 1 from public.payments where payment_schedule_id = old.id and status = 'confirme')
      or exists (select 1 from public.deposit_ledger where payment_schedule_id = old.id and entry_type = 'imputation')
    into v_has_settlement;

    if v_has_settlement then
      raise exception 'amount_due est figé dès qu''un paiement confirmé ou une imputation de loyer est rattaché à cette échéance : corrigez par un avoir/une imputation, jamais en réécrivant le montant dû';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_payment_schedules_prevent_amount_due_change_once_settled
  before update of amount_due on public.payment_schedules
  for each row execute function private.prevent_amount_due_change_once_settled();

-- ----------------------------------------------------------------------------
-- 0. JOUR DE FACTURATION FIXE — organisation (défaut) + bail (surcharge).
--    NULL aux deux niveaux = comportement d'origine (périodes ancrées sur
--    start_date, pas de jour fixe, pas de période de raccordement).
-- ----------------------------------------------------------------------------

alter table public.organizations
  add column default_billing_day integer
    check (default_billing_day is null or default_billing_day between 1 and 31);

alter table public.leases
  add column billing_day integer
    check (billing_day is null or billing_day between 1 and 31);

-- Jour de facturation réel pour un mois donné, avec report au dernier jour
-- du mois quand le jour visé n'existe pas (31 en février, etc.) plutôt
-- qu'une restriction 1-28 — beaucoup de baux réels spécifient explicitement
-- "le 30" ou "le dernier du mois". p_month_ref doit être normalisé au 1er du
-- mois par l'appelant (voir section 3) : ajouter des mois à un 1er est
-- toujours sûr, contrairement à ajouter des mois à un jour 29-31 qui peut
-- déborder sur le mois suivant avant même d'atteindre cette fonction.
-- immutable : fonction pure de ses arguments.
create or replace function private.billing_date_for_month(
  p_month_ref date,
  p_billing_day integer
)
returns date
language sql
immutable
as $$
  select least(
    (date_trunc('month', p_month_ref) + ((p_billing_day - 1) || ' days')::interval)::date,
    (date_trunc('month', p_month_ref) + interval '1 month' - interval '1 day')::date
  )
$$;

-- ----------------------------------------------------------------------------
-- 1. STATUT EFFECTIF — source unique de vérité.
-- ----------------------------------------------------------------------------

-- 'annulee' est la seule décision manuelle qui prime sur tout calcul. Sinon,
-- dérivé du montant couvert (paiements confirmés + imputations de loyer,
-- sommés par l'appelant — le loyer prépayé y contribue nativement puisqu'il
-- est représenté par de vraies lignes payments) comparé à amount_due, et de
-- due_date vs aujourd'hui pour le retard. stable (pas immutable) : dépend de
-- current_date, calculé à la volée — même raisonnement qu'au Module 6 pour
-- l'acceptation tacite : 'en_retard' change sans qu'aucune écriture ne se
-- produise, le matérialiser exigerait une tâche planifiée pour le
-- recalculer, chose qu'on a déjà écartée.
create or replace function private.payment_schedule_effective_status(
  p_status         text,
  p_amount_due     numeric,
  p_due_date       date,
  p_covered_amount numeric
)
returns text
language sql
stable
as $$
  select case
    when p_status = 'annulee' then 'annulee'
    when p_covered_amount >= p_amount_due then 'payee'
    when p_covered_amount > 0 then 'partiellement_payee'
    when p_due_date < current_date then 'en_retard'
    else 'en_attente'
  end
$$;

-- ----------------------------------------------------------------------------
-- 2. VUE — statut effectif exposé pour l'affichage/le reporting. RLS héritée
--    via security_invoker (même principe qu'aux Modules 5/6).
-- ----------------------------------------------------------------------------

create view public.payment_schedules_effective_status
with (security_invoker = true)
as
select
  ps.*,
  coalesce(pay.total_confirmed, 0) + coalesce(imp.total_imputed, 0) as covered_amount,
  private.payment_schedule_effective_status(
    ps.status, ps.amount_due, ps.due_date,
    coalesce(pay.total_confirmed, 0) + coalesce(imp.total_imputed, 0)
  ) as effective_status
from public.payment_schedules ps
-- Seuls les paiements confirmés comptent (ni en_attente, ni echoue, ni
-- rembourse) — inclut nativement le loyer prépayé, représenté par de vraies
-- lignes payment_type = 'loyer_prepaye', status = 'confirme'.
left join (
  select payment_schedule_id, sum(amount) as total_confirmed
  from public.payments
  where status = 'confirme' and payment_schedule_id is not null
  group by payment_schedule_id
) pay on pay.payment_schedule_id = ps.id
-- deposit_ledger_loyer_requires_schedule garantit déjà que seules les
-- imputations de catégorie 'loyer' portent un payment_schedule_id ; pas
-- besoin de filtrer imputation_category explicitement.
left join (
  select payment_schedule_id, sum(amount) as total_imputed
  from public.deposit_ledger
  where entry_type = 'imputation' and payment_schedule_id is not null
  group by payment_schedule_id
) imp on imp.payment_schedule_id = ps.id;

grant select on public.payment_schedules_effective_status to authenticated;

-- ----------------------------------------------------------------------------
-- 3. GÉNÉRATION DES ÉCHÉANCES DEPUIS UN BAIL.
-- Fonction PUBLIQUE (appelable en RPC), volontairement NON security definer :
-- ses INSERT passent par les policies RLS normales (payment_schedules_insert,
-- payments_insert), pas de logique de permission dupliquée.
--
-- Jour de facturation fixe (billing_day, hérité de l'organisation si non
-- précisé sur le bail) : si absent aux deux niveaux, mode d'origine (période
-- ancrée sur start_date, longueur = payment_frequency, pas de raccordement).
-- Si présent : la borne de chaque période est calculée via
-- private.billing_date_for_month appliquée au 1er du mois ciblé — jamais en
-- ajoutant des mois à la date de la période précédente (qui peut avoir été
-- écrêtée à un jour < billing_day et introduirait une dérive cumulative),
-- toujours en repartant du 1er du mois de la période courante. C'est cette
-- discipline (tronquer au 1er avant d'ajouter des mois) qui permet à un jour
-- 31 de "se rattraper" correctement en mars après avoir été écrêté à 28 en
-- février, sans dérive.
--
-- Période de raccordement : si start_date ne tombe pas exactement sur le
-- jour de facturation, une première échéance courte (ou longue) couvre
-- [start_date, prochaine_date_facturation), marquée is_partial_period,
-- proratisée sur une base neutre de 30 jours par mois de fréquence (ex: 90
-- jours pour trimestriel) — pas le nombre réel de jours du mois calendaire,
-- ambigu quand la période chevauche deux mois. Montant volontairement
-- corrigible après coup par simple UPDATE : aucun mécanisme dédié, l'
-- idempotence (ON CONFLICT DO NOTHING, jamais DO UPDATE) garantit qu'un
-- rappel ultérieur n'écrase jamais une correction manuelle.
--
-- Idempotence des échéances : ON CONFLICT sur (lease_id, period_start_date).
-- Horizon glissant pour un bail à durée indéterminée (end_date NULL) : ne
-- génère jamais de période dont le DÉBUT dépasse aujourd'hui +
-- p_horizon_months. Un bail à terme fixe génère jusqu'à end_date, avec la
-- dernière période bornée exactement à cette date (mais pas proratisée :
-- même famille de problème que la période de raccordement, pas traité ici).
--
-- Loyer prépayé : alloué période par période (plein tarif de LA période
-- concernée — donc le montant proratisé pour la période de raccordement,
-- pas rent_amount — puis le reliquat sur la période suivante) sous forme de
-- vraies lignes payments (payment_type = 'loyer_prepaye', status =
-- 'confirme'), uniquement pour les échéances nouvellement créées dans cet
-- appel. Idempotence de l'allocation : le reliquat restant est recalculé à
-- chaque appel en resommant les paiements loyer_prepaye déjà créés pour ce
-- bail.
--
-- Concurrence : pas de verrou consultatif ici (contrairement au solde de
-- caution du Module 5). L'allocation d'un paiement est strictement
-- subordonnée au succès de l'INSERT de l'échéance correspondante dans LA
-- MÊME itération (vérifié via le nombre de lignes affectées) : deux appels
-- concurrents se disputent chaque échéance individuellement via la
-- contrainte d'unicité, et celui qui perd un conflit sur une échéance
-- donnée n'alloue rien pour elle. La déduplication est structurelle, pas
-- une lecture-puis-décision sur un agrégat comme pour le solde de caution.
-- ----------------------------------------------------------------------------

create or replace function public.generate_payment_schedules_for_lease(
  p_lease_id uuid,
  p_horizon_months integer default 12,
  p_prepaid_payment_method text default 'virement'
)
returns integer
language plpgsql
as $$
declare
  v_lease               record;
  v_org                 record;
  v_period_months       integer;
  v_billing_day         integer;
  v_horizon_date        date;
  v_cursor_start        date;
  v_period_end          date;
  v_due_date            date;
  v_this_amount_due     numeric;
  v_is_partial          boolean;
  v_inserted            integer := 0;
  v_row_count           integer;
  v_new_schedule_id     uuid;
  v_already_allocated   numeric;
  v_remaining_prepaid    numeric;
  v_allocation          numeric;
  v_aligned_start        date;
  v_reconciliation_days  integer;
  v_nominal_days         integer;
begin
  if p_horizon_months <= 0 then
    raise exception 'p_horizon_months doit être positif, reçu: %', p_horizon_months;
  end if;

  select * into v_lease from public.leases where id = p_lease_id;
  if v_lease is null then
    raise exception 'Bail introuvable (ou non visible) : %', p_lease_id;
  end if;

  select * into v_org from public.organizations where id = v_lease.organization_id;

  v_period_months := case v_lease.payment_frequency
    when 'mensuel' then 1
    when 'trimestriel' then 3
    when 'semestriel' then 6
    when 'annuel' then 12
    else null
  end;
  if v_period_months is null then
    raise exception 'payment_frequency inattendu sur le bail %: %', p_lease_id, v_lease.payment_frequency;
  end if;

  v_billing_day := coalesce(v_lease.billing_day, v_org.default_billing_day);

  v_horizon_date := (current_date + (p_horizon_months || ' months')::interval)::date;

  select coalesce(sum(amount), 0) into v_already_allocated
  from public.payments
  where lease_id = p_lease_id and payment_type = 'loyer_prepaye';
  v_remaining_prepaid := v_lease.prepaid_rent_amount - v_already_allocated;

  select max(period_end_date) into v_cursor_start
  from public.payment_schedules
  where lease_id = p_lease_id;

  -- ---- Mode sans jour de facturation fixe : comportement d'origine. ----
  if v_billing_day is null then
    if v_cursor_start is null then
      v_cursor_start := v_lease.start_date;
    end if;

    loop
      if v_lease.end_date is not null and v_cursor_start >= v_lease.end_date then
        exit;
      end if;
      if v_lease.end_date is null and v_cursor_start >= v_horizon_date then
        exit;
      end if;

      v_period_end := (v_cursor_start + (v_period_months || ' months')::interval)::date;
      if v_lease.end_date is not null and v_period_end > v_lease.end_date then
        v_period_end := v_lease.end_date;
      end if;

      v_due_date := case v_lease.payment_timing when 'prepaye' then v_cursor_start else v_period_end end;
      v_this_amount_due := v_lease.rent_amount;

      v_new_schedule_id := null;
      insert into public.payment_schedules (
        organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status, is_partial_period
      )
      values (
        v_lease.organization_id, v_lease.id, v_cursor_start, v_period_end, v_this_amount_due, v_due_date, 'en_attente', false
      )
      on conflict (lease_id, period_start_date) do nothing
      returning id into v_new_schedule_id;

      get diagnostics v_row_count = row_count;

      if v_row_count > 0 then
        v_inserted := v_inserted + 1;
        if v_remaining_prepaid > 0 then
          v_allocation := least(v_remaining_prepaid, v_this_amount_due);
          insert into public.payments (
            organization_id, lease_id, payment_schedule_id, amount, payment_date,
            method, payment_type, direction, status
          )
          values (
            v_lease.organization_id, v_lease.id, v_new_schedule_id, v_allocation, v_lease.start_date,
            p_prepaid_payment_method, 'loyer_prepaye', 'entrant', 'confirme'
          );
          v_remaining_prepaid := v_remaining_prepaid - v_allocation;
        end if;
      end if;

      v_cursor_start := v_period_end;
    end loop;

    return v_inserted;
  end if;

  -- ---- Mode jour de facturation fixe. ----

  v_aligned_start := private.billing_date_for_month(date_trunc('month', v_lease.start_date)::date, v_billing_day);
  if v_aligned_start < v_lease.start_date then
    v_aligned_start := private.billing_date_for_month(
      (date_trunc('month', v_lease.start_date) + interval '1 month')::date, v_billing_day
    );
  end if;

  if v_cursor_start is null then
    -- Rien encore généré : traite la période de raccordement si start_date
    -- ne tombe pas exactement sur le jour de facturation.
    if v_aligned_start > v_lease.start_date then
      v_reconciliation_days := v_aligned_start - v_lease.start_date;
      -- Convention volontaire de 30 jours par mois (ex: 90 jours pour
      -- trimestriel), PAS le nombre réel de jours du/des mois calendaires
      -- concernés : la période de raccordement peut chevaucher deux mois de
      -- longueurs différentes (ex: 20 jours en janvier + 5 en février), donc
      -- "le nombre réel de jours de ce mois" serait ambigu. Ce n'est pas un
      -- bug si ce calcul ne correspond pas exactement au décompte calendaire
      -- réel — c'est une base neutre choisie délibérément, cohérente quel
      -- que soit le mois où tombe le raccordement.
      v_nominal_days := 30 * v_period_months;
      v_this_amount_due := round(v_lease.rent_amount * v_reconciliation_days::numeric / v_nominal_days, 2);
      v_due_date := case v_lease.payment_timing when 'prepaye' then v_lease.start_date else v_aligned_start end;

      v_new_schedule_id := null;
      insert into public.payment_schedules (
        organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status, is_partial_period
      )
      values (
        v_lease.organization_id, v_lease.id, v_lease.start_date, v_aligned_start,
        v_this_amount_due, v_due_date, 'en_attente', true
      )
      on conflict (lease_id, period_start_date) do nothing
      returning id into v_new_schedule_id;

      get diagnostics v_row_count = row_count;

      if v_row_count > 0 then
        v_inserted := v_inserted + 1;
        if v_remaining_prepaid > 0 then
          v_allocation := least(v_remaining_prepaid, v_this_amount_due);
          insert into public.payments (
            organization_id, lease_id, payment_schedule_id, amount, payment_date,
            method, payment_type, direction, status
          )
          values (
            v_lease.organization_id, v_lease.id, v_new_schedule_id, v_allocation, v_lease.start_date,
            p_prepaid_payment_method, 'loyer_prepaye', 'entrant', 'confirme'
          );
          v_remaining_prepaid := v_remaining_prepaid - v_allocation;
        end if;
      end if;
    end if;

    v_cursor_start := v_aligned_start;
  end if;

  loop
    if v_lease.end_date is not null and v_cursor_start >= v_lease.end_date then
      exit;
    end if;
    if v_lease.end_date is null and v_cursor_start >= v_horizon_date then
      exit;
    end if;

    -- Toujours repartir du 1er du mois de v_cursor_start avant d'ajouter des
    -- mois : évite toute dérive si v_cursor_start a été écrêté à un jour
    -- inférieur à billing_day le mois précédent (voir commentaire en tête
    -- de fonction).
    v_period_end := private.billing_date_for_month(
      (date_trunc('month', v_cursor_start) + (v_period_months || ' months')::interval)::date,
      v_billing_day
    );

    if v_lease.end_date is not null and v_period_end > v_lease.end_date then
      v_period_end := v_lease.end_date;
    end if;

    v_due_date := case v_lease.payment_timing when 'prepaye' then v_cursor_start else v_period_end end;
    v_this_amount_due := v_lease.rent_amount;

    v_new_schedule_id := null;
    insert into public.payment_schedules (
      organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status, is_partial_period
    )
    values (
      v_lease.organization_id, v_lease.id, v_cursor_start, v_period_end, v_this_amount_due, v_due_date, 'en_attente', false
    )
    on conflict (lease_id, period_start_date) do nothing
    returning id into v_new_schedule_id;

    get diagnostics v_row_count = row_count;

    if v_row_count > 0 then
      v_inserted := v_inserted + 1;
      if v_remaining_prepaid > 0 then
        v_allocation := least(v_remaining_prepaid, v_this_amount_due);
        insert into public.payments (
          organization_id, lease_id, payment_schedule_id, amount, payment_date,
          method, payment_type, direction, status
        )
        values (
          v_lease.organization_id, v_lease.id, v_new_schedule_id, v_allocation, v_lease.start_date,
          p_prepaid_payment_method, 'loyer_prepaye', 'entrant', 'confirme'
        );
        v_remaining_prepaid := v_remaining_prepaid - v_allocation;
      end if;
    end if;

    v_cursor_start := v_period_end;
  end loop;

  return v_inserted;
end;
$$;

grant execute on function public.generate_payment_schedules_for_lease(uuid, integer, text) to authenticated;
