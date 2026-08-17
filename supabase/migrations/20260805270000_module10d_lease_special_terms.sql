-- ============================================================================
-- MODULE 10d — CLAUSES PARTICULIÈRES DU CONTRAT : deux colonnes texte
-- libre, nullable, aucune logique métier.
--
-- organizations.special_terms : règlement intérieur / clauses par défaut,
-- éditable depuis l'écran Paramètres.
-- leases.special_terms : override optionnel par bail, éditable sur la
-- fiche bail. NULL = hérite du réglage organisation — même principe de
-- résolution que tenant_capture_enabled (Module 6), mais résolue en
-- TypeScript au moment du rendu PDF (lib/pdf/lease-contract-document.tsx),
-- jamais en base : pas de vue ni de fonction SQL, rien à calculer côté
-- serveur, un simple texte affiché tel quel une fois résolu.
--
-- Aucune RLS nouvelle : ces colonnes sont couvertes par les policies
-- organizations_update / leases_update déjà existantes (Module 1/3),
-- aucune restriction supplémentaire n'a de sens pour un simple champ texte.
-- ============================================================================

alter table public.organizations
  add column special_terms text;

alter table public.leases
  add column special_terms text;

comment on column public.organizations.special_terms is
  'Clauses particulières / règlement intérieur par défaut, texte libre. Résolu avec leases.special_terms (le bail prime si renseigné) uniquement côté application (rendu PDF du contrat, Module 10) — jamais en base.';

comment on column public.leases.special_terms is
  'Override optionnel des clauses particulières par défaut de l''organisation (organizations.special_terms). NULL = hérite du réglage organisation.';
