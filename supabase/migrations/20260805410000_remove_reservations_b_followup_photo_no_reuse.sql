-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — SUITE DE LA PASSE B : ANTI-RÉUTILISATION DE
-- PHOTO D'ÉTAT DES LIEUX.
--
-- Trouvé en diagnostiquant un échec systématique de confirmation d'upload
-- de photo (tout INSERT dans inspection_photos échouait avec
-- "42703: column pi.reservation_id does not exist") : private.validate_
-- inspection_photo_no_reuse() (Module 6, trigger trg_inspection_photos_
-- validate_no_reuse, BEFORE INSERT on inspection_photos) référence encore
-- pi.reservation_id / pi2.reservation_id dans son SELECT — colonne retirée
-- de property_inspections par la Migration C (20260805310000). Cette
-- fonction ne figurait pas dans la liste des 7 fonctions revues par la
-- Migration B (20260805300000) : oubliée à cette passe, comme
-- inspection_photos_storage_select l'avait été à la passe A (déjà
-- rattrapée dans la Migration C elle-même). Le SELECT fautif s'exécute
-- inconditionnellement en tête de fonction, avant même le test
-- "if v_inspection_type = 'sortie'" : l'échec touchait donc aussi bien les
-- photos d'entrée que de sortie, pas seulement le cas anti-réutilisation.
--
-- CREATE OR REPLACE FUNCTION à l'identique, recentrée sur lease_id seul
-- (retrait de v_reservation_id et des deux références à reservation_id),
-- même patron que les 7 fonctions déjà corrigées à la Migration B
-- (is not distinct from conservé par cohérence avec elles, même si
-- lease_id est désormais NOT NULL — aucun changement de logique non
-- demandé). Signature et corps inchangés pour le reste : même message
-- d'erreur, même trigger (pas de liste de colonnes "OF" à ajuster ici,
-- contrairement aux 2 triggers touchés en Migration B).
-- ============================================================================

create or replace function private.validate_inspection_photo_no_reuse()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_inspection_type text;
  v_lease_id        uuid;
  v_conflict_count  integer;
begin
  select pi.inspection_type, pi.lease_id
    into v_inspection_type, v_lease_id
  from public.inspection_items ii
  join public.property_inspections pi on pi.id = ii.inspection_id
  where ii.id = new.inspection_item_id;

  if v_inspection_type = 'sortie' then
    select count(*) into v_conflict_count
    from public.inspection_photos ip
    join public.inspection_items ii2 on ii2.id = ip.inspection_item_id
    join public.property_inspections pi2 on pi2.id = ii2.inspection_id
    where ip.file_hash = new.file_hash
      and pi2.inspection_type = 'entree'
      and pi2.lease_id is not distinct from v_lease_id;

    if v_conflict_count > 0 then
      raise exception 'Photo refusée : cette empreinte de fichier a déjà été utilisée dans l''état des lieux d''entrée de ce contrat (réutilisation interdite)';
    end if;
  end if;

  return new;
end;
$$;
