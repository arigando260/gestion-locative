-- ============================================================================
-- MODULE 6f — Généralise le contrôle anti-doublon du Module 6e (jusqu'ici
-- restreint à inspection_type = 'entree') à 'sortie' également, avec
-- EXACTEMENT la même logique : un nouvel état des lieux d'un type donné
-- (ou une requalification vers ce type) n'est autorisé que si le précédent
-- état des lieux du MÊME type pour ce bail/cette réservation est CONTESTÉ
-- par le locataire. La comparaison reste strictement intra-type — une
-- 'entree' n'est jamais comparée à une 'sortie', et réciproquement.
--
-- Comble un trou confirmé par diagnostic : rien n'empêchait de créer
-- plusieurs états des lieux de SORTIE finalisés et validés (aucun contesté)
-- sur le même bail — vérifié empiriquement (3 insertions réussies sans
-- exception avant cette migration).
--
-- Ne duplique pas le trigger du Module 6e : remplace la même fonction
-- (create or replace), retire la restriction "if new.inspection_type <>
-- 'entree' then return new" et compare désormais contre le dernier état
-- des lieux du MÊME inspection_type que la ligne traitée (new.inspection_
-- type), pas une valeur figée. Fonction et trigger renommés en conséquence
-- (sans "entree" dans le nom, plus rien ne restreint à ce seul type) —
-- l'ancien trigger/fonction Module 6e est explicitement supprimé plutôt que
-- laissé à côté du nouveau.
-- ============================================================================

drop trigger trg_property_inspections_validate_entree_not_duplicate on public.property_inspections;
drop function private.validate_property_inspection_entree_not_duplicate();

create function private.validate_property_inspection_not_duplicate()
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
  -- l'un contre l'autre) existant pour ce MÊME bail ou CETTE MÊME
  -- réservation (jamais les deux, property_inspections_exactly_one_link) —
  -- "is not distinct from" gère correctement le cas où l'autre colonne est
  -- NULL des deux côtés (bail XOR réservation).
  select document_status, tenant_validation_status, finalized_at
    into v_last_document_status, v_last_tenant_validation_status, v_last_finalized_at
  from public.property_inspections
  where inspection_type = new.inspection_type
    and lease_id is not distinct from new.lease_id
    and reservation_id is not distinct from new.reservation_id
    and id <> new.id
  order by created_at desc
  limit 1;

  -- Aucun état des lieux préexistant de ce type (hors la ligne elle-même) :
  -- premier pour ce bail/cette réservation, toujours autorisé.
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

create trigger trg_property_inspections_validate_not_duplicate
  before insert or update of inspection_type, lease_id, reservation_id
  on public.property_inspections
  for each row execute function private.validate_property_inspection_not_duplicate();
