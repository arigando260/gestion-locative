-- ============================================================================
-- MODULE 12f — Correctif : countries lisible par anon (Phase 2, volet 2,
-- écrans).
--
-- Découvert en construisant /signup : countries_select (Module 12a) est
-- `to authenticated`, mais /signup est justement une page SANS session --
-- un visiteur anonyme s'exécute en tant que rôle anon, jamais authenticated,
-- avant d'avoir un compte. Vérifié empiriquement : `set role anon; select
-- count(*) from countries` -> 0 ligne. Le catalogue des pays n'a aucune
-- raison d'être restreint à l'authentification (donnée de référence
-- publique, non sensible) -- retrait de la restriction de rôle plutôt
-- qu'ajout d'un contournement côté application.
-- ============================================================================

drop policy countries_select on public.countries;
create policy countries_select on public.countries
  for select
  using (true);
