-- ============================================================================
-- MODULE 10i — leases_closure_status : closure_reference_date.
--
-- Diagnostic préalable : un bail 'resilie' n'est pas structurellement
-- garanti d'avoir une lease_termination_requests 'validee' associée (le
-- garde-fou de transition actif->resilie, Module 10, ne protège que les
-- écritures futures — un bail déjà resilie avant son déploiement, ou une
-- ligne lease_termination_requests supprimée après coup via une connexion
-- qui bypasse RLS, resterait orphelin). closure_reference_date encode donc
-- explicitement le cas NULL plutôt que de supposer la jointure toujours
-- résolue.
--
-- Colonne ajoutée en fin de liste du SELECT (CREATE OR REPLACE VIEW reste
-- valide, même motif que les 3 colonnes du Module 10g) :
--   - status = 'resilie' : date de responded_at de la demande validee la
--     plus récente pour ce bail (LEFT JOIN LATERAL, même patron que
--     si/ei déjà en place) ; NULL si aucune trouvée.
--   - status = 'actif' (clôture Volet B, fin de bail normale) : end_date.
--   - sinon : NULL.
--
-- Consommée par RecordKeysReturnedBanner (écran, à suivre) : borne min du
-- sélecteur de date + contrôle applicatif équivalent, uniquement si non
-- NULL. La contrainte leases_keys_returned_after_start (Module 6, jamais
-- retirée) continue de protéger a minima contre une date antérieure au
-- début du bail, y compris dans le cas NULL.
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
  (ei.id is not null) as entry_inspection_done,
  case
    when l.status = 'resilie' then ltr.responded_at::date
    when l.status = 'actif' then l.end_date
    else null
  end as closure_reference_date
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
