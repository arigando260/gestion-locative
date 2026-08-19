-- ============================================================================
-- MODULE 10j — CLÔTURE DÉFINITIVE : L'ÉTAT DES LIEUX DE SORTIE CONTESTÉ NE
-- COMPTE PAS COMME FAIT.
--
-- Diagnostic préalable : ni private.validate_lease_status_transition()
-- (branche actif/resilie -> termine) ni leases_closure_status.
-- exit_inspection_done (Module 10g) ne tenaient compte du statut de
-- contestation locataire — seul document_status = 'finalise' comptait. Un
-- état des lieux de sortie finalisé PUIS contesté satisfaisait donc à tort
-- les deux : clôture définitive autorisée en base, bandeau écran passant à
-- "prêt à clôturer" (ReadyToCloseBanner) au lieu de redemander un état des
-- lieux (Module 10g ExitInspectionDueBanner).
--
-- Réutilise private.inspection_effective_validation_status() (Module 6,
-- seule source de vérité pour ce calcul ailleurs dans le projet — jamais
-- recalculée autrement) sur le DERNIER état des lieux de sortie finalisé
-- (même sélection finalized_at desc limit 1 des deux côtés).
-- ============================================================================

create or replace function private.validate_lease_status_transition()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_exit_document_status          text;
  v_exit_tenant_validation_status text;
  v_exit_finalized_at             timestamptz;
begin
  if TG_OP = 'INSERT' then
    if new.status <> 'brouillon' then
      raise exception 'Un bail est toujours créé au statut brouillon (valeur reçue : %)', new.status
        using detail = 'lease.status.invalid_initial_value', errcode = 'P0001';
    end if;
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if old.status = 'brouillon' and new.status = 'actif' then
    if pg_trigger_depth() < 2 then
      raise exception 'Passage brouillon -> actif impossible en écriture directe : requiert l''approbation du contrat par le locataire'
        using detail = 'lease.status.invalid_transition', errcode = 'P0001';
    end if;
    return new;
  end if;

  if old.status = 'actif' and new.status = 'resilie' then
    if pg_trigger_depth() < 2 then
      raise exception 'Passage actif -> resilie impossible en écriture directe : requiert le consensus de résiliation (Module 8)'
        using detail = 'lease.status.invalid_transition', errcode = 'P0001';
    end if;
    return new;
  end if;

  if old.status in ('actif', 'resilie') and new.status = 'termine' then
    if new.keys_returned_at is null then
      raise exception 'Clôture définitive impossible : la restitution des clés (keys_returned_at) n''est pas encore enregistrée pour ce bail'
        using detail = 'lease.closure.keys_not_returned', errcode = 'P0001';
    end if;

    select document_status, tenant_validation_status, finalized_at
      into v_exit_document_status, v_exit_tenant_validation_status, v_exit_finalized_at
    from public.property_inspections
    where lease_id = new.id
      and inspection_type = 'sortie'
      and document_status = 'finalise'
    order by finalized_at desc
    limit 1;

    if v_exit_document_status is null then
      raise exception 'Clôture définitive impossible : aucun état des lieux de sortie finalisé n''existe pour ce bail'
        using detail = 'lease.closure.missing_exit_inspection', errcode = 'P0001';
    end if;

    if private.inspection_effective_validation_status(
      v_exit_document_status, v_exit_tenant_validation_status, v_exit_finalized_at
    ) = 'conteste' then
      raise exception 'Clôture définitive impossible : le dernier état des lieux de sortie a été contesté par le locataire'
        using detail = 'lease.closure.exit_inspection_contested', errcode = 'P0001';
    end if;

    return new;
  end if;

  raise exception 'Transition de statut de bail invalide : % -> %', old.status, new.status
    using detail = 'lease.status.invalid_transition', errcode = 'P0001';
end;
$$;

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
  select pi.id, pi.inspection_date, pi.document_status, pi.tenant_validation_status, pi.finalized_at
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
