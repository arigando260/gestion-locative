-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — PASSE A : LECTURE (RLS) ET STATUT EFFECTIF.
--
-- Décision produit : les réservations courte durée sortent entièrement du
-- produit (seuls les baux longue durée restent). Diagnostic complet mené
-- avant tout code — voir échange produit. 0 réservation en base au moment
-- de cette migration (la seule ligne existante a été traitée hors migration,
-- comme les 2 biens reclassés de courte_duree vers longue_duree).
--
-- Cette passe ne touche NI aux colonnes reservation_id (Migration C, plus
-- tard) NI à la table public.reservations elle-même (Migration E, plus
-- tard) — uniquement aux endroits qui LISENT au travers d'elles :
--   1. private.property_effective_status / public.properties_effective_status
--      (Module 2c) : une réservation confirmée en cours ne doit plus jamais
--      compter comme occupation d'un bien.
--   2. Les policies RLS d'accès locataire qui offraient une deuxième voie
--      d'accès "via une réservation qui lui appartient", en plus de la voie
--      "via un bail qui lui appartient" déjà en place.
--
-- Toutes les policies déjà existantes sont réécrites via ALTER POLICY (même
-- technique que tenant_portal_properties_read_access.sql) : seule la clause
-- reservations est retirée, le reste de chaque prédicat est inchangé.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. STATUT EFFECTIF D'UN BIEN (Module 2c) — calculé désormais uniquement à
--    partir d'un bail actif. Le nouvel overload à 2 paramètres est créé
--    avant que la vue ne soit basculée dessus, puis l'ancien overload à 3
--    paramètres (devenu orphelin) est supprimé.
-- ----------------------------------------------------------------------------

create function private.property_effective_status(
  p_status           text,
  p_has_active_lease boolean
)
returns text
language sql
stable
as $$
  select case
    when p_status = 'en_travaux' then 'en_travaux'
    when p_has_active_lease then 'occupe'
    else 'disponible'
  end
$$;

create or replace view public.properties_effective_status
with (security_invoker = true)
as
select
  p.*,
  private.property_effective_status(
    p.status,
    exists (
      select 1 from public.leases l
      where l.property_id = p.id and l.status = 'actif'
    )
  ) as effective_status
from public.properties p;

grant select on public.properties_effective_status to authenticated;

drop function private.property_effective_status(text, boolean, boolean);

-- ----------------------------------------------------------------------------
-- 2. RLS — POLICIES DE LECTURE (SELECT) PORTANT UNE CLAUSE D'ACCÈS LOCATAIRE
--    VIA reservations, RETIREE. Aucun autre changement de prédicat.
-- ----------------------------------------------------------------------------

alter policy properties_select on public.properties
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.leases l
      where l.property_id = properties.id
        and l.tenant_account_id = auth.uid()
    )
  );

alter policy payment_schedules_select on public.payment_schedules
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = payment_schedules.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy payments_select on public.payments
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = payments.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy deposit_ledger_select on public.deposit_ledger
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = deposit_ledger.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy property_inspections_select on public.property_inspections
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy property_inspections_update on public.property_inspections
  using (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
  )
  with check (
    (organization_id = private.current_org_id() and private.has_permission('property_inspections', 'update'))
    or exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy inspection_items_select on public.inspection_items
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.property_inspections pi
      join public.leases l on l.id = pi.lease_id
      where pi.id = inspection_items.inspection_id
        and l.tenant_account_id = auth.uid()
    )
  );

alter policy inspection_photos_select on public.inspection_photos
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.inspection_items ii
      join public.property_inspections pi on pi.id = ii.inspection_id
      join public.leases l on l.id = pi.lease_id
      where ii.id = inspection_photos.inspection_item_id
        and l.tenant_account_id = auth.uid()
    )
  );

alter policy schedule_invoices_select on public.schedule_invoices
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('schedule_invoices', 'read'))
    or exists (select 1 from public.leases l where l.id = schedule_invoices.lease_id and l.tenant_account_id = auth.uid())
  );

alter policy invoice_schedule_items_select on public.invoice_schedule_items
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('schedule_invoices', 'read'))
    or exists (
      select 1 from public.schedule_invoices si
      join public.leases l on l.id = si.lease_id
      where si.id = invoice_schedule_items.invoice_id
        and l.tenant_account_id = auth.uid()
    )
  );

alter policy payment_receipts_select on public.payment_receipts
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('payment_receipts', 'read'))
    or exists (
      select 1 from public.payments p
      join public.leases l on l.id = p.lease_id
      where p.id = payment_receipts.payment_id
        and l.tenant_account_id = auth.uid()
    )
  );

alter policy payment_receipts_storage_select on storage.objects
  using (
    bucket_id = 'payment-receipts'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('payment_receipts', 'read'))
      or exists (
        select 1 from public.payments p
        join public.leases l on l.id = p.lease_id
        where p.id::text = (storage.foldername(name))[2]
          and l.tenant_account_id = auth.uid()
      )
    )
  );

alter policy schedule_invoices_storage_select on storage.objects
  using (
    bucket_id = 'schedule-invoices'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('schedule_invoices', 'read'))
      or exists (
        select 1 from public.schedule_invoices si
        join public.leases l on l.id = si.lease_id
        where si.id::text = (storage.foldername(name))[2]
          and l.tenant_account_id = auth.uid()
      )
    )
  );
