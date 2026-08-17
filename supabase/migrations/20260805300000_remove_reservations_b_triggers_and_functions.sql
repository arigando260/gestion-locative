-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — PASSE B : TRIGGERS ET FONCTIONS.
--
-- Suite de la passe A (20260805290000_remove_reservations_a_rls_and_effective_status.sql).
-- Cette passe ne touche NI aux colonnes reservation_id (Migration C, plus
-- tard) NI à la table public.reservations elle-même (Migration E, plus
-- tard) — uniquement aux fonctions trigger qui comparaient encore
-- reservation_id en plus de lease_id. Elles doivent cesser de la
-- référencer avant que Migration C ne retire la colonne, sans quoi ces
-- fonctions échoueraient à la compilation dès le DROP COLUMN.
--
-- 7 fonctions simplifiées, toutes via CREATE OR REPLACE FUNCTION (signature
-- inchangée) :
--   1. private.validate_payment_schedule_consistency (Module 5, payments)
--   2. private.validate_deposit_ledger_balance (Module 5, deposit_ledger)
--   3. private.prevent_finalized_inspection_change (Module 6, property_inspections)
--   4. private.restrict_tenant_inspection_update_fields (Module 6, property_inspections)
--   5. private.validate_property_inspection_not_duplicate (Module 6f, property_inspections)
--   6. private.validate_invoice_schedule_item_consistency (Module 9, invoice_schedule_items)
--   7. private.validate_lease_property_location_type (Module 3, leases) —
--      retire 'meuble_simple' du IN, ne garde que 'longue_duree' (décision
--      produit : un seul type de bien reste possible).
--
-- Les messages d'erreur destinés à l'utilisateur (RAISE EXCEPTION) sont
-- réécrits pour ne plus mentionner "réservation". Les slugs DETAIL déjà
-- posés (convention ARCHITECTURE.md : stables, jamais renommés) sont
-- laissés tels quels — seul le texte affiché change, jamais l'identifiant
-- machine.
--
-- Deux triggers dont la liste de colonnes surveillées ("OF ...") citait
-- reservation_id sont recréés via CREATE OR REPLACE TRIGGER (PG14+, projet
-- en PG17) pour ne plus se déclencher inutilement sur cette colonne :
--   - trg_payments_validate_schedule_consistency
--   - trg_property_inspections_validate_not_duplicate
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PAYMENTS — cohérence paiement/échéance limitée au bail.
-- ----------------------------------------------------------------------------

create or replace function private.validate_payment_schedule_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_schedule_lease_id uuid;
begin
  if new.payment_schedule_id is null then
    return new;
  end if;

  select lease_id into v_schedule_lease_id
  from public.payment_schedules
  where id = new.payment_schedule_id;

  if v_schedule_lease_id is distinct from new.lease_id then
    raise exception
      'Incohérence : le paiement % et son échéance % ne référencent pas le même bail',
      new.id, new.payment_schedule_id;
  end if;

  return new;
end;
$$;

create or replace trigger trg_payments_validate_schedule_consistency
  before insert or update of lease_id, payment_schedule_id on public.payments
  for each row execute function private.validate_payment_schedule_consistency();

-- ----------------------------------------------------------------------------
-- 2. DEPOSIT_LEDGER — verrou et calcul de solde limités au bail.
-- ----------------------------------------------------------------------------

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

  -- Verrou scopé à (lease_id, deposit_type) : les imputations sur des baux
  -- différents restent totalement concurrentes. Espace de verrouillage
  -- séparé de leases (pas de SELECT ... FOR UPDATE sur cette table) pour ne
  -- pas interférer avec ses propres triggers et ne pas augmenter la surface
  -- de deadlock.
  perform pg_advisory_xact_lock(
    hashtextextended(
      coalesce(new.lease_id::text, '') || '|' || new.deposit_type,
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
    and deposit_type = new.deposit_type;

  if v_consumed + new.amount > v_held then
    raise exception
      'Imputation/remboursement refusé : solde insuffisant (détenu %, déjà consommé %, tentative %)',
      v_held, v_consumed, new.amount;
  end if;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. PROPERTY_INSPECTIONS — immuabilité post-finalisation, restriction des
--    champs modifiables par le locataire : reservation_id retiré des deux
--    listes de champs surveillés (il ne compte plus parmi les champs dont
--    un changement doit être bloqué/détecté).
-- ----------------------------------------------------------------------------

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

-- ----------------------------------------------------------------------------
-- 4. PROPERTY_INSPECTIONS — contrôle anti-doublon (Module 6f) limité au bail.
-- ----------------------------------------------------------------------------

create or replace function private.validate_property_inspection_not_duplicate()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_last_document_status         text;
  v_last_tenant_validation_status text;
  v_last_finalized_at            timestamptz;
  v_last_effective                text;
begin
  -- Le plus récent état des lieux du MÊME TYPE (entree ou sortie, jamais
  -- l'un contre l'autre) existant pour ce MÊME bail.
  select document_status, tenant_validation_status, finalized_at
    into v_last_document_status, v_last_tenant_validation_status, v_last_finalized_at
  from public.property_inspections
  where inspection_type = new.inspection_type
    and lease_id is not distinct from new.lease_id
    and id <> new.id
  order by created_at desc
  limit 1;

  -- Aucun état des lieux préexistant de ce type (hors la ligne elle-même) :
  -- premier pour ce bail, toujours autorisé.
  if v_last_document_status is null then
    return new;
  end if;

  v_last_effective := private.inspection_effective_validation_status(
    v_last_document_status, v_last_tenant_validation_status, v_last_finalized_at
  );

  if v_last_effective <> 'conteste' then
    raise exception 'Un nouvel état des lieux de type "%" ne peut être créé (ou requalifié) que pour remplacer un état des lieux du même type contesté par le locataire — le précédent n''est pas contesté (statut effectif: %)',
      new.inspection_type, v_last_effective
      using detail = 'property_inspection.duplicate_not_contested', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create or replace trigger trg_property_inspections_validate_not_duplicate
  before insert or update of inspection_type, lease_id
  on public.property_inspections
  for each row execute function private.validate_property_inspection_not_duplicate();

-- ----------------------------------------------------------------------------
-- 5. INVOICE_SCHEDULE_ITEMS — cohérence facture/échéance limitée au bail.
-- ----------------------------------------------------------------------------

create or replace function private.validate_invoice_schedule_item_consistency()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_invoice_lease_id  uuid;
  v_schedule_lease_id uuid;
begin
  select lease_id into v_invoice_lease_id
  from public.schedule_invoices where id = new.invoice_id;

  select lease_id into v_schedule_lease_id
  from public.payment_schedules where id = new.payment_schedule_id;

  if v_schedule_lease_id is distinct from v_invoice_lease_id
  then
    raise exception 'Incohérence : l''échéance % n''appartient pas au même bail que la facture %',
      new.payment_schedule_id, new.invoice_id
      using detail = 'invoice_schedule_item.mismatch.lease_or_reservation', errcode = 'P0001';
  end if;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. LEASES — un bail n'est plus autorisé que sur un bien longue_duree.
-- ----------------------------------------------------------------------------

create or replace function private.validate_lease_property_location_type()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_location_type text;
begin
  select location_type into v_location_type
  from public.properties
  where id = new.property_id;

  if v_location_type <> 'longue_duree' then
    raise exception
      'Lease impossible : le bien % a le type de location "%", incompatible (attendu longue_duree)',
      new.property_id, v_location_type;
  end if;
  return new;
end;
$$;
