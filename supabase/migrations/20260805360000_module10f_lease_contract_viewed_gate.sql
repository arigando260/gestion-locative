-- ============================================================================
-- MODULE 10f — CONTRAT DE BAIL : GARDE-FOU "CONSULTÉ AVANT APPROBATION".
--
-- Diagnostic préalable (voir échange) : rien ne garantissait que le
-- locataire ait réellement ouvert le PDF de son contrat avant de
-- l'approuver — les boutons "Consulter" et "Approuver" étaient affichés en
-- même temps dès le départ, sans dépendance l'un envers l'autre, et aucun
-- trigger ne vérifiait une consultation effective (seuls les dépôts
-- complets et le statut brouillon du bail étaient revérifiés).
--
-- 1. lease_contracts.first_viewed_at (timestamptz, nullable) : posé une
--    seule fois côté application (getOrGenerateLeaseContractUrlAction) via
--    une mise à jour conditionnelle "WHERE first_viewed_at IS NULL",
--    déclenchée UNIQUEMENT quand l'appelant est le locataire — jamais le
--    staff. Aucun trigger d'immuabilité dédié n'est nécessaire : une
--    reconsultation est un événement normal (contrairement à approved_at,
--    qui ne doit jamais changer une fois posé), et la clause WHERE rend
--    déjà l'écriture idempotente et sûre en cas de concurrence (MVCC
--    standard — la seconde tentative concurrente ne matche plus la ligne
--    une fois la première commitée). La policy lease_contracts_update
--    (Module 10) n'autorise de toute façon QUE le locataire du bail à
--    faire un UPDATE sur cette table — le staff n'a aucune policy UPDATE,
--    donc une tentative côté staff est bloquée par la RLS elle-même, pas
--    seulement par le choix du code applicatif de ne pas l'appeler.
--
-- 2. leases_activation_readiness étendue avec contract_first_viewed_at
--    (colonne ajoutée en fin de liste du SELECT, CREATE OR REPLACE VIEW
--    reste valide) — nécessaire pour que l'écran initialise correctement
--    son état "déjà consulté" à partir d'une session précédente, plutôt
--    que de reposer uniquement sur un état local remis à zéro à chaque
--    rendu de page.
--
-- 3. private.activate_lease_on_contract_approval refuse désormais
--    l'approbation si first_viewed_at est NULL, vérifié EN PREMIER (avant
--    les dépôts) : un préalable procédural plus fondamental que l'état
--    financier. Nouveau slug DETAIL lease_contract.approve.not_viewed,
--    distinct de lease_contract.approve.deposits_incomplete (dépôts
--    incomplets, déjà existant) et du message TypeScript "Consultez
--    d'abord votre contrat avant de l'approuver" (absence totale de ligne
--    lease_contracts, vérifiée en amont côté application, avant même
--    d'atteindre la base — cas différent : ici le contrat existe bel et
--    bien, mais n'a jamais été ouvert).
-- ============================================================================

alter table public.lease_contracts
  add column first_viewed_at timestamptz;

create or replace view public.leases_activation_readiness
with (security_invoker = true)
as
select
  l.id as lease_id,
  l.organization_id,
  l.status,
  private.lease_deposits_complete(l.id) as deposits_complete,
  lc.id as contract_id,
  lc.storage_path as contract_storage_path,
  lc.generated_at as contract_generated_at,
  lc.approved_at as contract_approved_at,
  lc.first_viewed_at as contract_first_viewed_at
from public.leases l
left join public.lease_contracts lc on lc.lease_id = l.id
where l.status = 'brouillon';

grant select on public.leases_activation_readiness to authenticated;

create or replace function private.activate_lease_on_contract_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.approved_at is not null and old.approved_at is null then
    if new.first_viewed_at is null then
      raise exception 'Approbation refusée : ce contrat existe mais n''a encore jamais été consulté — ouvrez-le avant de l''approuver'
        using detail = 'lease_contract.approve.not_viewed', errcode = 'P0001';
    end if;

    if not coalesce(private.lease_deposits_complete(new.lease_id), false) then
      raise exception 'Approbation refusée : les dépôts initiaux requis (avance de garantie / caution eau-électricité) ne sont pas encore intégralement versés pour ce bail'
        using detail = 'lease_contract.approve.deposits_incomplete', errcode = 'P0001';
    end if;

    update public.leases
    set status = 'actif'
    where id = new.lease_id and status = 'brouillon';

    if not found then
      raise exception 'Approbation refusée : ce bail n''est plus au statut brouillon (déjà activé, ou dans un autre état)'
        using detail = 'lease_contract.approve.lease_not_draft', errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;
