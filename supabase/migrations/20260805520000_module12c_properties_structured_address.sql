-- ============================================================================
-- MODULE 12c — Adresse structurée des biens (Phase 2, volet 2).
--
-- Pays -> Ville -> Quartier -> Complément, du plus large au plus précis.
-- Diagnostic préalable (29 biens dev, échantillon : "0 rue G", "sekandji",
-- "Porto", "calavi", "Missèbo"...) : format libre hétérogène, aucun pattern
-- régulier permettant un découpage automatique fiable en ville/quartier.
--
-- Approche retenue :
--   - address (text not null, libre) devient address_complement (text,
--     nullable) — RENAME pur, aucune donnée perdue ni recopiée : le contenu
--     actuel EST déjà, sémantiquement, le niveau le plus précis/libre de la
--     nouvelle hiérarchie.
--   - country_code : automatisable proprement (hérité de l'organisation,
--     valeur connue, pas du parsing) -> backfillé dans cette migration.
--   - city / neighborhood : PAS automatisables (diagnostic) -> restent NULL
--     pour les 29 biens existants. Pas de NOT NULL posé ici : casserait
--     l'existant. L'écran les rend obligatoires pour toute NOUVELLE fiche ;
--     un NOT NULL en base viendra dans une migration séparée, plus tard,
--     une fois la donnée dev nettoyée manuellement (même logique en deux
--     temps que déjà pratiquée sur ce projet).
-- ============================================================================

alter table public.properties
  rename column address to address_complement;

alter table public.properties
  alter column address_complement drop not null;

alter table public.properties
  add column country_code text references public.countries (code) on delete restrict,
  add column city         text,
  add column neighborhood text;

-- Héritage depuis l'organisation : backfill sûr et déterministe, pas du
-- parsing de texte libre.
update public.properties p
set country_code = o.country_code
from public.organizations o
where o.id = p.organization_id
  and p.country_code is null;
