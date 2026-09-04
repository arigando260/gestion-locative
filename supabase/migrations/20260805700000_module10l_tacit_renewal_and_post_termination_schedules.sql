-- ============================================================================
-- MODULE 10l — RECONDUCTION TACITE (générateur d'échéances) ET ANNULATION
-- DES ÉCHÉANCES AU-DELÀ DE LA DATE C (résiliation validée).
--
-- Deux correctifs ciblés, aucune nouvelle table/colonne/statut :
--
-- 1. generate_payment_schedules_for_lease (Module 5b) plafonnait
--    inconditionnellement sur leases.end_date dès qu'elle était renseignée.
--    Conséquence : un bail ACTIF dont l'échéance initiale est dépassée SANS
--    qu'aucune résiliation n'ait été validée (reconduction tacite) cessait
--    silencieusement d'être facturé. Correctif : un plafond effectif calculé
--    une seule fois par appel, qui ignore end_date UNIQUEMENT quand
--    status='actif' ET end_date déjà dépassée (= reconduction tacite par
--    construction, cf. point 3) — traité alors comme un bail à horizon
--    glissant, exactement comme end_date IS NULL. end_date n'est JAMAIS
--    réécrite par ce correctif. Comportement inchangé pour : bail actif
--    avant son échéance, bail résilié, bail terminé, jour de facturation
--    fixe, prépayé, idempotence (ON CONFLICT).
--
-- 2. private.apply_effective_lease_termination() (Module 8) écrit déjà
--    status='resilie' et end_date=date C lors d'une résiliation validée,
--    mais ne touchait jamais payment_schedules : toute échéance déjà
--    générée avant la résiliation, dont la période démarre à ou après C,
--    restait 'en_attente' comme si elle était toujours due. Correctif :
--    annulation explicite (status='annulee'), dans la même transaction que
--    le passage à 'resilie', strictement bornée aux échéances qui n'ont
--    encore aucun règlement réel attaché (aucun paiement confirmé, aucune
--    imputation de dépôt) — jamais une échéance payée, totalement ou
--    partiellement. Aucun mécanisme de remboursement/avoir créé. Aucune
--    proratisation d'une échéance chevauchant C.
--
-- Coexistence avec 'hors_periode' (Module 8, private.payment_schedule_
-- effective_status) : CE STATUT N'EST NI SUPPRIMÉ NI REMPLACÉ. Il reste la
-- seule protection pour tout consommateur qui lit la vue
-- payment_schedules_effective_status (dashboard, rent-collection...) —
-- fonction d'AFFICHAGE, calculée à la volée, jamais écrite en base.
-- L'annulation ci-dessous protège en plus les consommateurs qui lisent la
-- table brute payment_schedules directement, confirmé réel sur
-- src/data/building-invoicing.ts (facturation groupée par immeuble) et
-- src/data/schedule-invoices.ts, qui ne passent pas par cette vue. Les deux
-- mécanismes ont des rôles différents et non redondants ; les deux restent
-- en place.
--
-- Incohérence de borne PRÉEXISTANTE, non corrigée ici (hors périmètre de ce
-- lot) : private.payment_schedule_effective_status utilise une comparaison
-- STRICTE (period_start_date > lease.end_date) pour basculer en
-- 'hors_periode', alors que le générateur d'échéances (ci-dessous, comme
-- avant ce correctif) utilise systématiquement >= comme borne de "ne
-- devrait jamais exister". Une échéance dont period_start_date est
-- exactement égale à C n'est donc PAS reclassée 'hors_periode' par la vue,
-- mais EST bien annulée par ce correctif (cohérent avec le générateur,
-- borne >=). Signalé, pas corrigé : nécessiterait de toucher Module 8, hors
-- périmètre de ce lot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. GÉNÉRATEUR — plafond effectif (reconduction tacite).
-- Corps intégralement repris de la dernière définition (Module 5b), seule
-- addition : v_effective_ceiling, calculé une fois, puis substitué à
-- v_lease.end_date dans les 4 comparaisons de plafond (2 par branche). Tout
-- le reste (raccordement, jour de facturation, prépayé, idempotence) est
-- inchangé caractère pour caractère.
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
  v_effective_ceiling    date;
begin
  if p_horizon_months <= 0 then
    raise exception 'p_horizon_months doit être positif, reçu: %', p_horizon_months;
  end if;

  select * into v_lease from public.leases where id = p_lease_id;
  if v_lease is null then
    raise exception 'Bail introuvable (ou non visible) : %', p_lease_id;
  end if;

  select * into v_org from public.organizations where id = v_lease.organization_id;

  -- Reconduction tacite (V3.1) : un bail ACTIF dont l'échéance initiale est
  -- dépassée SANS qu'aucune résiliation n'ait été validée doit continuer à
  -- produire des échéances, comme un bail à horizon glissant. status='actif'
  -- avec end_date dépassée ne peut signifier QUE ça : la seule transition
  -- qui fait sortir un bail de 'actif' (private.apply_effective_lease_
  -- termination, Module 8) réécrit end_date sur la date C dans la MÊME
  -- opération que le changement de statut -- donc un bail encore 'actif'
  -- n'a jamais pu voir sa end_date "figée" par une résiliation. Un bail
  -- dont la résiliation est seulement 'en_attente' (non validée) reste
  -- 'actif' et continue donc, à raison, d'être traité comme en reconduction
  -- tacite tant que rien n'est validé. end_date n'est jamais réécrite ici.
  v_effective_ceiling := v_lease.end_date;
  if v_lease.status = 'actif'
     and v_lease.end_date is not null
     and v_lease.end_date <= current_date
  then
    v_effective_ceiling := null;
  end if;

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
      if v_effective_ceiling is not null and v_cursor_start >= v_effective_ceiling then
        exit;
      end if;
      if v_effective_ceiling is null and v_cursor_start >= v_horizon_date then
        exit;
      end if;

      v_period_end := (v_cursor_start + (v_period_months || ' months')::interval)::date;
      if v_effective_ceiling is not null and v_period_end > v_effective_ceiling then
        v_period_end := v_effective_ceiling;
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
    if v_effective_ceiling is not null and v_cursor_start >= v_effective_ceiling then
      exit;
    end if;
    if v_effective_ceiling is null and v_cursor_start >= v_horizon_date then
      exit;
    end if;

    v_period_end := private.billing_date_for_month(
      (date_trunc('month', v_cursor_start) + (v_period_months || ' months')::interval)::date,
      v_billing_day
    );

    if v_effective_ceiling is not null and v_period_end > v_effective_ceiling then
      v_period_end := v_effective_ceiling;
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

-- ----------------------------------------------------------------------------
-- 2. RÉSILIATION — annulation des échéances au-delà de la date C.
-- Corps intégralement repris de la dernière définition (Module 8), seule
-- addition : l'UPDATE payment_schedules, exécuté uniquement après le succès
-- de la transition status='resilie' (donc uniquement au moment précis où
-- new.requested_end_date devient la date C réelle du bail).
-- ----------------------------------------------------------------------------

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

    -- Voir le commentaire d'en-tête de cette migration pour la coexistence
    -- avec 'hors_periode' et l'incohérence de borne connue (>= ici, > côté
    -- vue). Garde stricte : jamais une échéance déjà réglée, en tout ou
    -- partie (paiement confirmé) ou couverte par une imputation de dépôt --
    -- aucun mécanisme de remboursement/avoir créé, aucune proratisation
    -- d'une échéance chevauchant C.
    update public.payment_schedules
    set status = 'annulee'
    where lease_id = new.lease_id
      and status = 'en_attente'
      and period_start_date >= new.requested_end_date
      and not exists (
        select 1 from public.payments
        where payment_schedule_id = payment_schedules.id and status = 'confirme'
      )
      and not exists (
        select 1 from public.deposit_ledger
        where payment_schedule_id = payment_schedules.id and entry_type = 'imputation'
      );
  end if;
  return new;
end;
$$;
