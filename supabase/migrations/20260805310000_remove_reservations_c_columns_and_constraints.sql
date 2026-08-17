-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — PASSE C : COLONNES ET CONTRAINTES XOR.
--
-- Suite des passes A (RLS, statut effectif) et B (triggers/fonctions).
-- Sur chacune des 5 tables partagées bail/réservation
-- (payment_schedules, payments, deposit_ledger, property_inspections,
-- schedule_invoices) :
--   - DROP CONSTRAINT ..._exactly_one_link (le XOR lease_id/reservation_id
--     n'a plus de sens à une seule branche)
--   - DROP CONSTRAINT ..._reservation_org_fk
--   - DROP COLUMN reservation_id
--   - ADD CONSTRAINT ..._lease_required CHECK (lease_id is not null)
--     (remplace le XOR : lease_id redevient obligatoire, seul lien
--     possible désormais)
--
-- Revérifié juste avant d'écrire cette migration (script ponctuel,
-- SUPABASE_DB_URL) : 0 ligne avec reservation_id renseigné sur les 5
-- tables, 0 ligne dans reservations elle-même — déjà confirmé au
-- diagnostic initial, toujours vrai. Le DROP COLUMN ne perd donc aucune
-- donnée réelle.
--
-- Trois vues dépendent d'un SELECT ...* incluant reservation_id
-- (dépendance dure Postgres, bloquerait le DROP COLUMN) : DROP VIEW puis
-- recréation à l'identique (moins la colonne, retirée automatiquement du
-- SELECT *) juste avant/après le ALTER TABLE correspondant, même
-- technique que module8_lease_termination_requests.sql pour
-- payment_schedules_effective_status (« la vue dépend de l'ancienne
-- signature... il faut la supprimer avant... Recréée juste en dessous »).
--   - public.payment_schedules_effective_status
--   - public.deposit_ledger_balances
--   - public.property_inspections_effective_status
-- payments et schedule_invoices n'ont aucune vue dépendante (vérifié :
-- aucun "create view" ne sélectionne p.*/si.* dans tout le projet).
--
-- Trouvé en tentant d'appliquer cette migration (pg_depend le confirme,
-- 1ère tentative rejetée avant tout COMMIT, rien perdu) : la Migration A
-- avait couvert les policies storage.objects des buckets payment-receipts
-- et schedule-invoices (Module 9) mais pas inspection-photos (Module 6) —
-- inspection_photos_storage_select portait la même clause
-- "left join public.reservations r on r.id = pi.reservation_id" qu'elle
-- aussi, jamais retirée. Corrigée ici via ALTER POLICY (même technique
-- que Migration A) avant le ALTER TABLE property_inspections concerné —
-- rattrapage d'un point manqué à la passe A, pas un nouveau périmètre.
--
-- Ne touche PAS encore aux permissions 'reservations' (Migration D) ni à
-- la table public.reservations elle-même (Migration E).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PAYMENT_SCHEDULES.
-- ----------------------------------------------------------------------------

drop view if exists public.payment_schedules_effective_status;

alter table public.payment_schedules
  drop constraint payment_schedules_exactly_one_link,
  drop constraint payment_schedules_reservation_org_fk,
  drop column reservation_id,
  add constraint payment_schedules_lease_required check (lease_id is not null);

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
-- lease_id est désormais toujours renseigné (payment_schedules_lease_
-- required ci-dessus) : LEFT JOIN conservé tel quel malgré tout (aucune
-- ligne ne peut plus produire l/status NULL par ce chemin), pour ne pas
-- mêler un changement de logique de jointure non demandé à ce retrait de
-- colonne.
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

-- ----------------------------------------------------------------------------
-- 2. PAYMENTS — aucune vue dépendante.
-- ----------------------------------------------------------------------------

alter table public.payments
  drop constraint payments_exactly_one_link,
  drop constraint payments_reservation_org_fk,
  drop column reservation_id,
  add constraint payments_lease_required check (lease_id is not null);

-- ----------------------------------------------------------------------------
-- 3. DEPOSIT_LEDGER.
-- ----------------------------------------------------------------------------

drop view if exists public.deposit_ledger_balances;

alter table public.deposit_ledger
  drop constraint deposit_ledger_exactly_one_link,
  drop constraint deposit_ledger_reservation_org_fk,
  drop column reservation_id,
  add constraint deposit_ledger_lease_required check (lease_id is not null);

create view public.deposit_ledger_balances
with (security_invoker = true)
as
select
  organization_id,
  lease_id,
  deposit_type,
  coalesce(sum(amount) filter (where entry_type = 'depot_initial'), 0) as amount_held,
  coalesce(sum(amount) filter (where entry_type = 'imputation'), 0) as total_imputed,
  coalesce(sum(amount) filter (where entry_type = 'remboursement'), 0) as total_refunded,
  coalesce(sum(amount) filter (where entry_type = 'depot_initial'), 0)
    - coalesce(sum(amount) filter (where entry_type in ('imputation', 'remboursement')), 0) as balance
from public.deposit_ledger
group by organization_id, lease_id, deposit_type;

grant select on public.deposit_ledger_balances to authenticated;

-- ----------------------------------------------------------------------------
-- 4. PROPERTY_INSPECTIONS.
-- ----------------------------------------------------------------------------

-- Rattrapage Migration A (voir en-tête) : policy storage manquée.
alter policy inspection_photos_storage_select on storage.objects
  using (
    bucket_id = 'inspection-photos'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text)
      or exists (
        select 1 from public.property_inspections pi
        join public.leases l on l.id = pi.lease_id
        where pi.id::text = (storage.foldername(name))[2]
          and l.tenant_account_id = auth.uid()
      )
    )
  );

drop view if exists public.property_inspections_effective_status;

alter table public.property_inspections
  drop constraint property_inspections_exactly_one_link,
  drop constraint property_inspections_reservation_org_fk,
  drop column reservation_id,
  add constraint property_inspections_lease_required check (lease_id is not null);

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

-- ----------------------------------------------------------------------------
-- 5. SCHEDULE_INVOICES — aucune vue dépendante.
-- ----------------------------------------------------------------------------

alter table public.schedule_invoices
  drop constraint schedule_invoices_exactly_one_link,
  drop constraint schedule_invoices_reservation_org_fk,
  drop column reservation_id,
  add constraint schedule_invoices_lease_required check (lease_id is not null);
