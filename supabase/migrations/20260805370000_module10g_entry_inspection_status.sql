-- ============================================================================
-- MODULE 10g — leases_closure_status : lecture symétrique pour l'entrée.
--
-- La vue (Module 10) n'exposait jusqu'ici que l'état des lieux de SORTIE
-- (exit_inspection_done, latest_finalized_exit_inspection_id/_date), pour
-- guider le staff vers la clôture (Volet C). Rien d'équivalent n'existait
-- pour l'ENTRÉE, alors que son absence bloque plus tard toute imputation
-- dégâts (private.validate_deposit_ledger_damage_imputation_requires_
-- inspections, Module 6, exige un état des lieux d'entrée finalisé).
--
-- 3 colonnes ajoutées en fin de liste du SELECT (CREATE OR REPLACE VIEW
-- reste valide) : latest_finalized_entry_inspection_id,
-- latest_finalized_entry_inspection_date, entry_inspection_done — même
-- motif LEFT JOIN LATERAL que la partie sortie déjà en place, filtré
-- inspection_type = 'entree' AND document_status = 'finalise', trié par
-- finalized_at DESC LIMIT 1. Aucun changement de portée (toujours
-- status IN ('actif', 'resilie')) ni de logique métier nouvelle — une
-- lecture de plus, rien d'autre.
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
  (si.id is not null) as exit_inspection_done,
  ei.id as latest_finalized_entry_inspection_id,
  ei.inspection_date as latest_finalized_entry_inspection_date,
  (ei.id is not null) as entry_inspection_done
from public.leases l
join public.properties p on p.id = l.property_id
join public.tenant_accounts ta on ta.id = l.tenant_account_id
left join lateral (
  select pi.id, pi.inspection_date
  from public.property_inspections pi
  where pi.lease_id = l.id
    and pi.inspection_type = 'sortie'
    and pi.document_status = 'finalise'
  order by pi.finalized_at desc
  limit 1
) si on true
left join lateral (
  select pi.id, pi.inspection_date
  from public.property_inspections pi
  where pi.lease_id = l.id
    and pi.inspection_type = 'entree'
    and pi.document_status = 'finalise'
  order by pi.finalized_at desc
  limit 1
) ei on true
where l.status in ('actif', 'resilie');

grant select on public.leases_closure_status to authenticated;
