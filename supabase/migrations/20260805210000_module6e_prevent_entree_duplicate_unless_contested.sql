-- ============================================================================
-- MODULE 6e — Un nouvel état des lieux d'ENTRÉE ne peut être créé (ou
-- requalifié depuis un brouillon existant) pour un bail/réservation que si
-- le précédent (le plus récent) est CONTESTÉ par le locataire. Comble un
-- trou confirmé par diagnostic : rien n'empêchait jusqu'ici d'en créer un
-- deuxième pendant qu'un premier était déjà finalisé et en attente de
-- validation (ou même encore en brouillon) — ni de contourner ça en
-- requalifiant après coup un brouillon 'sortie' existant en 'entree'.
--
-- Réutilise private.inspection_effective_validation_status (Module 6) telle
-- quelle — fonction SQL scalaire, pas une requête sur la vue, appelable
-- directement depuis ce trigger BEFORE INSERT/UPDATE, exactement comme le
-- fait déjà private.validate_deposit_ledger_damage_imputation_requires_inspections
-- (Module 5/6) pour la même fonction.
--
-- Couvre INSERT et UPDATE OF inspection_type/lease_id/reservation_id avec la
-- même fonction : "id <> new.id" exclut la ligne elle-même de la recherche
-- du dernier état des lieux d'entrée (sans effet sur INSERT, où la ligne
-- n'existe pas encore en base ; nécessaire sur UPDATE pour ne pas se
-- retrouver à comparer la ligne à elle-même).
-- ============================================================================

create or replace function private.validate_property_inspection_entree_not_duplicate()
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
  if new.inspection_type <> 'entree' then
    return new;
  end if;

  -- Le plus récent état des lieux d'entrée existant pour ce MÊME bail ou
  -- CETTE MÊME réservation (jamais les deux, property_inspections_exactly_one_link) —
  -- "is not distinct from" gère correctement le cas où l'autre colonne est
  -- NULL des deux côtés (bail XOR réservation).
  select document_status, tenant_validation_status, finalized_at
    into v_last_document_status, v_last_tenant_validation_status, v_last_finalized_at
  from public.property_inspections
  where inspection_type = 'entree'
    and lease_id is not distinct from new.lease_id
    and reservation_id is not distinct from new.reservation_id
    and id <> new.id
  order by created_at desc
  limit 1;

  -- Aucun état des lieux d'entrée préexistant (hors la ligne elle-même) :
  -- premier pour ce bail/cette réservation, toujours autorisé.
  if v_last_document_status is null then
    return new;
  end if;

  v_last_effective := private.inspection_effective_validation_status(
    v_last_document_status, v_last_tenant_validation_status, v_last_finalized_at
  );

  if v_last_effective <> 'conteste' then
    raise exception 'Un nouvel état des lieux d''entrée ne peut être créé (ou requalifié) que pour remplacer un état des lieux d''entrée contesté par le locataire — le précédent n''est pas contesté (statut effectif: %)',
      v_last_effective
      using detail = 'property_inspection.entree.duplicate_not_contested', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_property_inspections_validate_entree_not_duplicate
  before insert or update of inspection_type, lease_id, reservation_id
  on public.property_inspections
  for each row execute function private.validate_property_inspection_entree_not_duplicate();
