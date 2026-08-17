-- ============================================================================
-- MODULE 10b — UN SEUL BAIL "EN COURS" PAR BIEN (actif OU brouillon), PAS
-- SEULEMENT ACTIF.
--
-- Trou diagnostiqué : leases_one_active_per_property (Module 3) ne portait
-- que sur status='actif' — rien n'empêchait plusieurs baux 'brouillon'
-- simultanés sur le même bien (statut introduit par le Module 10), ni un
-- brouillon en parallèle d'un bail déjà actif. Côté écran, la fiche du bien
-- ne le signalait nulle part non plus : getActiveLeaseForProperty ne
-- filtrait que sur 'actif', donc un brouillon existant restait invisible et
-- "Créer un bail" continuait d'être proposé sans avertissement (corrigé
-- séparément côté application, cette migration ne porte que la garantie
-- base).
--
-- resilie/termine restent hors contrainte, sans changement : un bien libéré
-- (résiliation ou clôture définitive, Module 10) doit pouvoir recevoir un
-- nouveau brouillon immédiatement.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. INDEX ÉLARGI + RENOMMÉ — "one_active" devenait trompeur une fois
--    'brouillon' couvert aussi. Reste la garantie ATOMIQUE réelle en dernier
--    recours (voir section 2) : le trigger ne protège pas contre deux
--    créations strictement simultanées sur le même bien, seul un index
--    unique le peut.
-- ----------------------------------------------------------------------------

drop index public.leases_one_active_per_property;

create unique index leases_one_pending_or_active_per_property
  on public.leases (property_id)
  where status in ('actif', 'brouillon');

comment on index public.leases_one_pending_or_active_per_property is
  'Un seul bail "en cours" par bien à la fois (actif OU brouillon) — resilie/termine libèrent le bien immédiatement, hors contrainte. Garantie atomique en dernier recours (cas de course concurrente) ; le message métier normal passe par trg_leases_validate_one_pending_or_active_per_property, pas par la violation 23505 de cet index.';

-- ----------------------------------------------------------------------------
-- 2. TRIGGER — message métier propre en amont de l'index. Pas de verrou
--    explicite (pg_advisory_xact_lock, comme deposit_ledger) : geste staff
--    rare, pas un chemin chaud — décision actée, l'index ci-dessus reste la
--    garantie atomique réelle si deux créations concurrentes se
--    chevauchaient malgré tout (elles obtiendraient alors un 23505 brut,
--    traduit génériquement par lib/errors.ts, pas ce message).
--
-- Se déclenche sur INSERT et sur UPDATE OF status/property_id (un bail
-- pourrait en théorie changer de bien ou de statut vers 'actif'/'brouillon'
-- — aucun chemin applicatif ne le fait aujourd'hui, mais le trigger reste
-- correct si un tel chemin apparaissait). l.id <> new.id exclut la ligne
-- elle-même (nécessaire pour l'UPDATE : un bail qui reste sur le même bien
-- ne doit jamais se bloquer lui-même).
-- ----------------------------------------------------------------------------

create or replace function private.validate_lease_one_pending_or_active_per_property()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status not in ('actif', 'brouillon') then
    return new;
  end if;

  if exists (
    select 1 from public.leases l
    where l.property_id = new.property_id
      and l.status in ('actif', 'brouillon')
      and l.id <> new.id
  ) then
    raise exception 'Ce bien a déjà un bail en cours (actif ou brouillon) : un seul bail en cours à la fois par bien'
      using detail = 'lease.property.already_has_pending_or_active_lease', errcode = 'P0001';
  end if;

  return new;
end;
$$;

create trigger trg_leases_validate_one_pending_or_active_per_property
  before insert or update of status, property_id on public.leases
  for each row execute function private.validate_lease_one_pending_or_active_per_property();
