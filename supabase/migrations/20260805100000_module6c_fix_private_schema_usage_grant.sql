-- ============================================================================
-- MODULE 6c — CORRECTIF : USAGE manquant sur le schéma private
-- Découvert en testant prevent_tenant_finalizing_inspection (Module 6),
-- premier trigger simple (non security definer) du schéma à appeler
-- explicitement une autre fonction private.* depuis son corps. Les policies
-- RLS n'ont jamais été affectées (leurs expressions sont résolues/liées à
-- la création de la policy, pas ré-évaluées à chaque appel), d'où l'absence
-- de symptôme jusqu'ici malgré l'octroi manquant depuis le Module 1.
-- N'affaiblit aucune isolation : USAGE permet la résolution de nom, RLS
-- reste seule responsable de l'accès aux données.
-- ============================================================================

grant usage on schema private to authenticated, service_role, anon;
