-- ============================================================================
-- MODULE 12l — Correctif roles_select : ajoute is_internal() (Phase 3,
-- diagnostic préalable au module "gestion des agents").
--
-- Diagnostic initial (avant relecture complète) supposait une fuite réelle :
-- roles_select ne posant que organization_id = current_org_id(), un locataire
-- pourrait lire les rôles de l'organisation qui gère son bail. Vérification
-- empirique sur dev (compte locataire réel, PostgREST direct) : 0 ligne
-- retournée, AVANT même ce correctif -- pas une fuite active. Cause : la
-- définition de private.current_org_id() a été remplacée au Module 1b
-- (20260805030000_module1b_tenant_global_identity.sql:150-158), qui a retiré
-- le UNION sur tenant_accounts présent dans la version Module 1 -- la
-- fonction ne résout plus RIEN pour un locataire (retourne NULL), donc
-- organization_id = current_org_id() vaut déjà NULL/false pour lui, quelle
-- que soit la présence d'is_internal(). Le diagnostic initial avait relu la
-- version Module 1 de la fonction sans voir sa redéfinition ultérieure.
--
-- Ce correctif reste posé malgré tout, par cohérence défensive : toutes les
-- autres policies staff du schéma (properties_select, maintenance_tickets_
-- select, etc.) posent systématiquement is_internal() EN PLUS de
-- organization_id = current_org_id(), jamais l'un sans l'autre -- roles_select
-- était la seule exception. Sans is_internal() ici, un futur changement de
-- current_org_id() qui réintroduirait une résolution pour les locataires
-- (rien ne l'empêche structurellement) réexposerait silencieusement cette
-- policy. Durcissement, pas correctif d'une fuite active.
--
-- Aucun changement de comportement pour le staff : is_internal() est déjà
-- vrai pour tout compte profiles actif, cette policy continue de leur
-- montrer exactement les mêmes lignes qu'avant.
-- ============================================================================

alter policy roles_select on public.roles
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
  );
