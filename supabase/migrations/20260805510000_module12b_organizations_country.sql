-- ============================================================================
-- MODULE 12b — Pays de l'organisation (Phase 2, volet 2).
--
-- "Le pays vit sur l'organisation, choisi une fois à l'inscription, pas
-- redemandé à chaque bien." Contrairement à properties.address (Module 12c,
-- format libre historique, non parsable), la valeur correcte pour les
-- organisations dev existantes est connue sans ambiguïté (toponymes déjà
-- observés : Akpakpa, Calavi, Cotonou — Bénin) : rétro-remplissage direct
-- et NOT NULL posé immédiatement, pas de période nullable transitoire ici.
-- ============================================================================

alter table public.organizations
  add column country_code text references public.countries (code) on delete restrict;

update public.organizations
set country_code = 'BJ'
where country_code is null;

alter table public.organizations
  alter column country_code set not null;
