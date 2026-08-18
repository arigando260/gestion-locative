-- ============================================================================
-- MODULE 6g — OBSERVATIONS OBLIGATOIRES À LA FINALISATION D'UN ÉTAT DES
-- LIEUX.
--
-- La colonne property_inspections.observations existe depuis le Module 6
-- mais n'a jamais eu de point de saisie ni de contrainte — un état des
-- lieux pouvait être finalisé sans aucune observation, avec zéro constat
-- (voir diagnostic). Cette migration ferme le second trou (observations),
-- le premier (formulaire de création qui n'exposait pas le champ) est
-- traité côté application dans le même chantier.
--
-- Même famille que private.fill_lease_contract_approved_at /
-- private.activate_lease_on_contract_approval (Module 10) : un trigger
-- BEFORE UPDATE dédié, pas un simple CHECK — nécessaire pour porter un
-- message français précis et un slug DETAIL stable (un CHECK constraint nu,
-- comme property_inspections_finalized_requires_conductor, ne peut porter
-- ni l'un ni l'autre ; voir diagnostic préalable).
--
-- Se déclenche uniquement sur la transition vers 'finalise' (comme
-- activate_lease_on_contract_approval compare new/old sur approved_at) —
-- un document déjà finalisé ne repasse jamais par ce trigger de toute
-- façon (private.prevent_finalized_inspection_change, Module 6, bloque
-- toute autre modification en amont).
-- ============================================================================

create or replace function private.validate_inspection_finalize_requires_observations()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.document_status = 'finalise' and old.document_status is distinct from new.document_status then
    if new.observations is null or trim(new.observations) = '' then
      raise exception 'Impossible de finaliser un état des lieux sans observations renseignées'
        using detail = 'property_inspection.finalize.observations_required', errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_property_inspections_validate_finalize_observations
  before update of document_status on public.property_inspections
  for each row execute function private.validate_inspection_finalize_requires_observations();
