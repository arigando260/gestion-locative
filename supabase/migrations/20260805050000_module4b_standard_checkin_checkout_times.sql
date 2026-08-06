-- ============================================================================
-- MODULE 4b — HEURES STANDARD D'ARRIVÉE/DÉPART (indicatif, non contractuel)
-- ============================================================================

-- Valeurs par défaut au niveau organisation, héritées par les biens qui ne
-- précisent rien. Purement informatif : n'intervient dans aucun calcul ni
-- dans la contrainte d'exclusion GiST des réservations.
alter table public.organizations
  add column default_standard_check_in_time  time,
  add column default_standard_check_out_time time;

-- Heures propres au bien. NULL = hérite du défaut organisation (résolution
-- à la volée via COALESCE, pas de figeage : si l'organisation change son
-- défaut, les biens qui en héritent suivent immédiatement).
alter table public.properties
  add column standard_check_in_time  time,
  add column standard_check_out_time time;

comment on column public.properties.standard_check_in_time is
  'Heure d''arrivée standard indicative, affichée au locataire. NULL = hérite de organizations.default_standard_check_in_time. Ne participe à aucun calcul de disponibilité.';

comment on column public.properties.standard_check_out_time is
  'Heure de départ standard indicative, affichée au locataire. NULL = hérite de organizations.default_standard_check_out_time. Ne participe à aucun calcul de disponibilité.';
