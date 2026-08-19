-- ============================================================================
-- MODULE 10k — leases_closure_status.entry_inspection_done : PREND EN
-- COMPTE LA CONTESTATION (symétrique de la sortie, Module 10j).
--
-- Diagnostic préalable : entry_inspection_done ne vérifiait que
-- document_status = 'finalise', comme exit_inspection_done avant sa
-- correction 10j — un état des lieux d'entrée finalisé PUIS contesté par
-- le locataire comptait à tort comme "fait".
--
-- Contrairement à la sortie, l'entrée n'est jamais une condition de
-- blocage dans private.validate_lease_status_transition() (le bail
-- s'active dès l'approbation du contrat, indépendamment de l'état des
-- lieux d'entrée — voir Module 10) : aucune modification de ce trigger
-- ici. Seul le bandeau écran EntryInspectionDueBanner (piloté par
-- entry_inspection_done) doit refléter la contestation.
--
-- Même patron exact que exit_inspection_done (10j) : réutilise
-- private.inspection_effective_validation_status() sur le dernier état
-- des lieux d'entrée finalisé (finalized_at desc limit 1). Seule la
-- lecture ei change (colonnes supplémentaires + condition) ; le reste de
-- la vue est repris à l'identique.
-- ============================================================================

create or replace view public.leases_closure_status
with (security_invoker = true)
as
select
  l.id as lease_id,
  l.organization_id,
  l.status,
  l.end_date as lease_end_date,
  l.property_id,
  p.name as property_name,
  l.tenant_account_id,
  ta.full_name as tenant_full_name,
  l.keys_returned_at,
  (l.keys_returned_at + 7) as exit_inspection_due_date,
  si.id as latest_finalized_exit_inspection_id,
  si.inspection_date as latest_finalized_exit_inspection_date,
  (
    si.id is not null
    and private.inspection_effective_validation_status(
      si.document_status, si.tenant_validation_status, si.finalized_at
    ) <> 'conteste'
  ) as exit_inspection_done,
  ei.id as latest_finalized_entry_inspection_id,
  ei.inspection_date as latest_finalized_entry_inspection_date,
  (
    ei.id is not null
    and private.inspection_effective_validation_status(
      ei.document_status, ei.tenant_validation_status, ei.finalized_at
    ) <> 'conteste'
  ) as entry_inspection_done,
  case
    when l.status = 'resilie' then ltr.responded_at::date
    when l.status = 'actif' then l.end_date
    else null
  end as closure_reference_date
from public.leases l
join public.properties p on p.id = l.property_id
join public.tenant_accounts ta on ta.id = l.tenant_account_id
left join lateral (
  select pi.id, pi.inspection_date, pi.document_status, pi.tenant_validation_status, pi.finalized_at
  from public.property_inspections pi
  where pi.lease_id = l.id
    and pi.inspection_type = 'sortie'
    and pi.document_status = 'finalise'
  order by pi.finalized_at desc
  limit 1
) si on true
left join lateral (
  select pi.id, pi.inspection_date, pi.document_status, pi.tenant_validation_status, pi.finalized_at
  from public.property_inspections pi
  where pi.lease_id = l.id
    and pi.inspection_type = 'entree'
    and pi.document_status = 'finalise'
  order by pi.finalized_at desc
  limit 1
) ei on true
left join lateral (
  select ltr2.responded_at
  from public.lease_termination_requests ltr2
  where ltr2.lease_id = l.id
    and ltr2.status = 'validee'
  order by ltr2.responded_at desc
  limit 1
) ltr on true
where l.status in ('actif', 'resilie');

grant select on public.leases_closure_status to authenticated;
