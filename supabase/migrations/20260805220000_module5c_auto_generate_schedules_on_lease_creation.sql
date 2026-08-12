-- ============================================================================
-- MODULE 5c — Génération automatique des échéances à la création d'un bail,
-- et vue de couverture réutilisable pour repérer les baux à échéances
-- insuffisantes (fiche bail + tableau de bord staff).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TRIGGER — appelle generate_payment_schedules_for_lease(NEW.id) dans la
-- MÊME transaction que l'INSERT du bail (comportement par défaut d'un
-- trigger Postgres, rien à faire de spécial) : un échec de génération fait
-- échouer la création du bail dans son ensemble, jamais un état à moitié
-- fait.
--
-- Volontairement PAS security definer : generate_payment_schedules_for_lease
-- (Module 5b) est elle-même délibérément non-definer, ses INSERT dans
-- payment_schedules/payments passent par les policies RLS normales sous
-- l'identité de qui crée le bail — rendre CE trigger security definer
-- élèverait silencieusement ces INSERT vers le propriétaire de la table et
-- contournerait cette garantie. Repose sur l'invariant vérifié par
-- diagnostic : tout rôle avec leases:create a aussi payment_schedules:create
-- dans les organisations existantes (pas structurellement garanti pour un
-- futur rôle personnalisé — dans ce cas, la création de bail échouera
-- entièrement pour ce rôle, ce qui est le comportement voulu, pas un bug).
-- ----------------------------------------------------------------------------

create or replace function private.trigger_generate_payment_schedules_for_new_lease()
returns trigger
language plpgsql
as $$
begin
  perform public.generate_payment_schedules_for_lease(new.id);
  return new;
end;
$$;

create trigger trg_leases_generate_schedules_after_insert
  after insert on public.leases
  for each row execute function private.trigger_generate_payment_schedules_for_new_lease();

-- ----------------------------------------------------------------------------
-- 2. VUE — couverture d'échéances par bail, computed-at-the-fly (même
-- principe que payment_schedules_effective_status, Module 5b) : security_
-- invoker = true, aucune logique de permission dupliquée, RLS des tables
-- sous-jacentes (leases, payment_schedules, properties, tenant_accounts)
-- appliquée normalement à l'appelant.
--
-- coverage_end_date = dernière period_end_date déjà générée pour ce bail
-- (NULL si aucune échéance n'existe encore). lease_end_date exposée à côté
-- pour permettre à l'appelant de distinguer "couverture faible mais le bail
-- continue" de "couverture qui s'arrête à end_date, rien de plus à
-- générer" — pas la responsabilité de cette vue de trancher un seuil.
-- ----------------------------------------------------------------------------

create view public.leases_schedule_coverage
with (security_invoker = true)
as
select
  l.id                as lease_id,
  l.organization_id,
  l.status,
  l.end_date          as lease_end_date,
  l.property_id,
  p.name              as property_name,
  l.tenant_account_id,
  ta.full_name        as tenant_full_name,
  max(ps.period_end_date) as coverage_end_date
from public.leases l
join public.properties p on p.id = l.property_id
join public.tenant_accounts ta on ta.id = l.tenant_account_id
left join public.payment_schedules ps on ps.lease_id = l.id
group by l.id, p.name, ta.full_name;

grant select on public.leases_schedule_coverage to authenticated;
