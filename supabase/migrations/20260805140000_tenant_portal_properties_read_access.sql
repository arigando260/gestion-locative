-- ============================================================================
-- PORTAIL LOCATAIRE — LECTURE DU BIEN PAR SON PROPRE LOCATAIRE
-- properties_select (Module 2) exigeait private.is_internal() sans exception,
-- écrite avant l'existence d'un portail locataire : un locataire ne pouvait
-- pas lire le nom/l'adresse du bien concerné par son propre bail ou sa
-- propre réservation, même via une jointure PostgREST (RLS s'applique aussi
-- aux embeds, silencieusement null si refusé — pas d'erreur, juste une
-- valeur manquante, découvert empiriquement via le portail locataire).
-- Même principe déjà en place pour payment_schedules/payments/deposit_ledger
-- (Module 5) et property_inspections (Module 6) : lecture ouverte au
-- locataire concerné, sans toucher à l'écriture (properties_insert/update/
-- delete restent réservées au staff interne, inchangées).
-- ============================================================================

alter policy properties_select on public.properties
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or exists (
      select 1 from public.leases l
      where l.property_id = properties.id
        and l.tenant_account_id = auth.uid()
    )
    or exists (
      select 1 from public.reservations r
      where r.property_id = properties.id
        and r.tenant_account_id = auth.uid()
    )
  );
