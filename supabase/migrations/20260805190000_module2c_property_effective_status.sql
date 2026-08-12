-- ============================================================================
-- MODULE 2c — STATUT EFFECTIF DE properties.status, CALCULÉ À LA VOLÉE.
-- Même principe que payment_schedule_effective_status (Module 5b) :
-- properties.status ne porte plus que la décision manuelle ('disponible' =
-- pas d'override, 'en_travaux' = override explicite du staff), 'occupe' est
-- désormais calculé (bail actif OU réservation courte durée en cours),
-- exposé par la vue properties_effective_status.
--
-- Hors périmètre de cette migration (dette connue, documentée) : aucun
-- chemin d'écriture n'existe pour poser 'en_travaux' depuis l'écran — déjà
-- vrai avant cette migration (aucune action ne l'exposait), ça reste donc
-- une lacune préexistante, pas une régression introduite ici.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. RESSERREMENT DU CHECK — 'occupe' n'est plus une valeur insérable
--    directement, seulement une valeur calculée (voir la fonction plus bas).
--    Aucune ligne existante ne porte 'occupe' (jamais écrit par l'app, voir
--    diagnostic), donc rien à backfill avant de resserrer.
-- ----------------------------------------------------------------------------

alter table public.properties
  drop constraint properties_status_check;

alter table public.properties
  add constraint properties_status_check
  check (status in ('disponible', 'en_travaux'));

comment on column public.properties.status is
  'Décision manuelle uniquement : ''disponible'' (défaut, pas d''override) ou ''en_travaux'' (override explicite du staff). Ne reflète jamais ''occupe'' — le statut réel se lit dans properties_effective_status.effective_status, calculé à partir des baux actifs et réservations courte durée en cours, jamais dans cette colonne.';

-- ----------------------------------------------------------------------------
-- 2. STATUT EFFECTIF — source unique de vérité.
-- ----------------------------------------------------------------------------

-- 'en_travaux' est la seule décision manuelle et prime toujours sur le
-- calcul (même raisonnement que 'annulee' pour les échéances) : un bail ou
-- une réservation encore actif en base ne doit jamais masquer un override
-- explicite du staff. stable (pas immutable) : dépend de current_date via
-- l'appelant (occupation par réservation), calculé à la volée.
create or replace function private.property_effective_status(
  p_status                 text,
  p_has_active_lease       boolean,
  p_has_active_reservation boolean
)
returns text
language sql
stable
as $$
  select case
    when p_status = 'en_travaux' then 'en_travaux'
    when p_has_active_lease or p_has_active_reservation then 'occupe'
    else 'disponible'
  end
$$;

-- ----------------------------------------------------------------------------
-- 3. VUE — statut effectif exposé pour l'affichage. RLS héritée via
--    security_invoker (même principe qu'aux Modules 5/6/8) : les deux
--    sous-requêtes EXISTS ci-dessous s'exécutent avec les droits de
--    l'appelant, donc filtrées par les policies leases_select /
--    reservations_select comme n'importe quelle requête directe.
--
--    Bail actif ET réservation courte durée en cours sont vérifiés tous les
--    deux, sans brancher sur location_type : structurellement exclusifs en
--    pratique (un bien longue_duree/meuble_simple ne peut pas avoir de
--    réservation, un bien courte_duree ne peut pas avoir de bail — triggers
--    validate_lease_property_location_type / validate_reservation_property_
--    location_type), mais rester agnostique du type évite toute dépendance
--    cachée supplémentaire à cette colonne.
--
--    Fenêtre d'occupation par réservation : [check_in_date, check_out_date)
--    strictement — turnover_buffer_days EXCLU (confirmé) : le buffer est un
--    concept de disponibilité à la réservation (délai de ménage avant la
--    prochaine réservation), pas un signal que l'occupant précédent est
--    encore présent.
-- ----------------------------------------------------------------------------

create view public.properties_effective_status
with (security_invoker = true)
as
select
  p.*,
  private.property_effective_status(
    p.status,
    exists (
      select 1 from public.leases l
      where l.property_id = p.id and l.status = 'actif'
    ),
    exists (
      select 1 from public.reservations r
      where r.property_id = p.id
        and r.status = 'confirmee'
        and current_date >= r.check_in_date
        and current_date <  r.check_out_date
    )
  ) as effective_status
from public.properties p;

grant select on public.properties_effective_status to authenticated;
