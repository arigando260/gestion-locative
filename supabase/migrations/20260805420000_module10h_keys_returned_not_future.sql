-- ============================================================================
-- MODULE 10h — RESTITUTION DES CLÉS : DATE JAMAIS DANS LE FUTUR.
--
-- Complète leases_keys_returned_after_start (Module 6, borne basse ==
-- start_date) par une borne haute : keys_returned_at ne peut jamais être
-- postérieure à aujourd'hui. Défense en profondeur — le contrôle
-- applicatif (recordKeysReturnedAction, écran) porte déjà le message
-- précis "La date de restitution ne peut pas être dans le futur" ; cette
-- contrainte est le filet de sécurité qui tient même hors de cette action
-- (écriture directe, autre point d'entrée futur), avec le même patron que
-- la borne basse : violation -> 23514 générique côté toUserMessage, pas ce
-- message précis.
--
-- current_date (pas now()) : keys_returned_at est de type date. Un CHECK
-- peut référencer une fonction volatile (contrairement à une colonne
-- générée ou une expression d'index) — évalué à l'écriture, jamais
-- re-vérifié rétroactivement sur les lignes existantes.
-- ============================================================================

alter table public.leases
  add constraint leases_keys_returned_not_future
    check (keys_returned_at is null or keys_returned_at <= current_date);
