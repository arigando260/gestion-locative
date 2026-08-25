-- ============================================================================
-- MODULE 12i — Correctif : properties_effective_status ne reflétait plus le
-- schéma réel de properties depuis le Module 12c (adresse structurée).
--
-- Diagnostic : une vue créée avec p.* fige ses colonnes de sortie à ce qui
-- existait sur la table au moment de sa création (ou de son dernier
-- CREATE OR REPLACE) -- confirmé empiriquement : la vue exposait encore une
-- colonne "address" (Postgres suit bien la colonne physique renommée en
-- interne, seul le NOM DE SORTIE de la vue restait figé) et n'exposait pas
-- du tout country_code/city/neighborhood, ajoutées après coup.
--
-- CREATE OR REPLACE VIEW ne peut pas renommer une colonne de sortie
-- existante (seulement ajouter des colonnes en fin de liste, à noms/types
-- inchangés pour le reste) -- DROP + CREATE nécessaire ici, pas un simple
-- REPLACE.
--
-- Reprend la version ACTUELLE de la vue (pas celle du Module 2c d'origine) :
-- le module remove_reservations_a (20260805290000) l'a déjà recréée une
-- fois pour retirer la clause reservations et basculer sur l'overload à 2
-- paramètres de private.property_effective_status -- reprendre l'ancienne
-- version à 3 paramètres aurait réintroduit une dépendance vers la table
-- reservations, supprimée depuis. Aucun changement de logique de statut
-- effectif ici, seulement les colonnes exposées par p.*.
--
-- data/properties.ts n'a besoin d'aucun changement : Property/
-- PropertyWithEffectiveStatus déclarent déjà address_complement/
-- country_code/city/neighborhood (corrigés en amont, Module 12 régression
-- fix), et getPropertyWithEffectiveStatus()/getPropertiesWithEffectiveStatus()
-- utilisent select("*") sans nommer de colonne -- seule la vue elle-même
-- était en retard sur le schéma réel.
-- ============================================================================

drop view public.properties_effective_status;

create view public.properties_effective_status
with (security_invoker = true)
as
select
  p.*,
  private.property_effective_status(
    p.status,
    exists (
      select 1 from public.leases l
      where l.property_id = p.id and l.status = 'actif'
    )
  ) as effective_status
from public.properties p;

grant select on public.properties_effective_status to authenticated;
