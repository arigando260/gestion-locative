-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — PASSE D : CATALOGUE DE PERMISSIONS.
--
-- Suite des passes A (RLS, statut effectif), B (triggers/fonctions) et C
-- (colonnes/contraintes XOR). Retire le resource 'reservations'
-- (create/read/update/delete) du catalogue public.permissions et les
-- octrois correspondants dans public.role_permissions — 4 lignes dans
-- permissions, 18 dans role_permissions au moment de cette migration
-- (accumulées à travers les rôles système de chaque organisation existante,
-- re-seedées par chaque module depuis le Module 4).
--
-- Ordre obligatoire : role_permissions AVANT permissions. La FK
-- role_permissions (resource, action) -> permissions (resource, action)
-- n'a pas de ON DELETE CASCADE (voir Module 1) — supprimer permissions en
-- premier échouerait sur une violation de contrainte tant que des lignes
-- role_permissions y pointent encore.
--
-- Effet de bord correct et voulu, sans action supplémentaire requise :
-- handle_new_organization (Module 1) seed le rôle admin d'une nouvelle
-- organisation via "select v_admin_id, resource, action from
-- public.permissions" — une fois 'reservations' absent du catalogue,
-- toute organisation créée après cette migration n'en hérite simplement
-- plus, sans erreur ni cas particulier à gérer.
--
-- Ne touche PAS encore à la table public.reservations elle-même
-- (Migration E, qui suit).
-- ============================================================================

delete from public.role_permissions where resource = 'reservations';
delete from public.permissions where resource = 'reservations';
