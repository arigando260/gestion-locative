-- ============================================================================
-- MODULE 12j — organizations.organization_type (Phase 2, volet 3).
--
-- Distinction propriétaire individuel / agence, affichée sur la nouvelle
-- page d'accueil publique (3 choix) et transmise à la création de compte.
-- Nullable, sans backfill : les organisations existantes n'ont jamais
-- exprimé cette information et aucune ne peut être déduite sans risque
-- d'erreur (même logique que city/neighborhood sur properties, Module 12c)
-- — contrairement à organizations.country_code (Module 12b) qui, lui, était
-- rétro-remplissable sans ambiguïté depuis les toponymes déjà observés.
-- L'interface ne module rien selon cette valeur pour l'instant (pas de
-- fonctionnalité différente par type) : simple champ de classification posé
-- en amont d'un besoin futur, cohérent avec la façon dont
-- tenant_capture_enabled avait été posé avant d'être exploité.
-- ============================================================================

alter table public.organizations
  add column organization_type text
    check (organization_type in ('proprietaire', 'agence'));

comment on column public.organizations.organization_type is
  'Nature de l''organisation : propriétaire individuel ou agence. Nullable (organisations existantes, ou inscription sans passer par la page d''accueil) — non exploité par l''interface pour l''instant.';
