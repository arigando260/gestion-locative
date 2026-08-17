-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — PASSE F : CATALOGUE DE TYPES DE BIEN.
--
-- Dernière passe. Retire les 2 types globaux 'meuble_simple' et
-- 'courte_duree' du catalogue public.property_types — seul 'longue_duree'
-- reste (décision produit : un seul type de bien possible).
--
-- Vérifié juste avant d'écrire cette migration (diagnostic ponctuel sur le
-- distant) : 0 bien avec location_type IN ('meuble_simple', 'courte_duree')
-- — les 2 seuls biens concernés ont été reclassés en longue_duree avant
-- Migration A. Aucune contrainte ni trigger sur property_types n'empêche
-- ce DELETE (PK + FK sortante vers organizations seulement ; aucune FK
-- externe ne référence property_types — location_type est validé par
-- trigger, pas par FK déclarée, voir Module 2).
--
-- Pur changement de données de référence, aucun changement de code
-- applicatif : PropertyTypeSelect (composants/properties/property-type-
-- select.tsx) lit dynamiquement le catalogue via getPropertyTypes()
-- (data/property-types.ts, SELECT sans filtre de code), aucune liste des
-- 3 codes codée en dur ailleurs dans le chemin de sélection.
-- organization_id is null cible précisément les 2 types globaux (jamais un
-- type personnalisé d'organisation, dont aucun n'existe aujourd'hui mais
-- que ce filtre protège structurellement dans tous les cas).
-- ============================================================================

delete from public.property_types
where code in ('meuble_simple', 'courte_duree')
  and organization_id is null;
