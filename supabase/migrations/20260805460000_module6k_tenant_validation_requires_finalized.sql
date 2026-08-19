-- ============================================================================
-- MODULE 6k — VALIDATION LOCATAIRE : JAMAIS AVANT FINALISATION, JAMAIS DE
-- VISIBILITÉ SUR UN BROUILLON.
--
-- Diagnostic préalable : ni la policy SELECT locataire sur
-- property_inspections, ni private.restrict_tenant_inspection_update_
-- fields() (trigger), ni l'action serveur, ne vérifiaient document_status
-- avant d'exposer/accepter tenant_validation_status — un brouillon (créé
-- par le staff ou le locataire) était visible dans le portail locataire et
-- validable/contestable avant même finalisation.
--
-- private.inspection_effective_validation_status() n'est PAS modifiée :
-- vérifié que 6e/6f (duplicate check, s'appuie sur le comportement actuel
-- pour un brouillon) et 10j/10k (n'appellent jamais la fonction avec un
-- document_status hors 'finalise') n'en dépendent pas différemment. Nos
-- correctifs rendent simplement impossible qu'un brouillon ait un jour
-- tenant_validation_status='conteste' — n'affecte pas leur logique.
-- ============================================================================

-- 1. VISIBILITÉ — un brouillon reste invisible au locataire.
alter policy property_inspections_select on public.property_inspections
  using (
    (organization_id = private.current_org_id() and private.is_internal())
    or (
      document_status = 'finalise'
      and exists (select 1 from public.leases l where l.id = property_inspections.lease_id and l.tenant_account_id = auth.uid())
    )
  );

-- 2. ÉCRITURE — champs de validation interdits avant finalisation, quelle
--    que soit l'origine de l'inspection (vérification universelle, avant
--    la branche "propre brouillon" qui autorise le reste).
create or replace function private.restrict_tenant_inspection_update_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if private.is_internal() then
    return new;
  end if;

  if old.document_status <> 'finalise'
     and (
       new.tenant_validation_status is distinct from old.tenant_validation_status
       or new.tenant_validation_at is distinct from old.tenant_validation_at
       or new.tenant_comments is distinct from old.tenant_comments
     )
  then
    raise exception 'Un locataire ne peut pas valider ou contester un état des lieux tant qu''il n''est pas finalisé'
      using detail = 'property_inspection.tenant_validation.requires_finalized', errcode = 'P0001';
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
