-- ============================================================================
-- MODULE 10e — SUPPRESSION ATOMIQUE D'UN BAIL AVEC CONTRAT NON APPROUVÉ
-- (data/leases.ts::deleteLease).
--
-- Deux trous liés, découverts en corrigeant deleteLease pour qu'elle
-- supprime aussi le lease_contracts associé avant le bail (sinon
-- lease_contracts_lease_org_fk, ON DELETE RESTRICT, bloque toujours la
-- suppression du bail) :
--
-- 1. lease_contracts n'avait AUCUNE policy RLS DELETE (Module 10) — un rôle
--    'authenticated' ordinaire ne pouvait donc JAMAIS supprimer une ligne
--    ici, même non approuvée (Module 10c n'a ajusté que le trigger, pas
--    RLS). Corrigé par une policy DELETE gouvernée par la même permission
--    (leases:delete) que la suppression du bail elle-même — la légitimité
--    précise (contrat non approuvé) reste portée par le trigger, pas par
--    cette policy, même principe que lease_contracts_update.
--
-- 2. Deux appels PostgREST séparés (delete contrat, puis delete bail) ne
--    sont pas atomiques : si le second échoue pour une autre raison
--    (deposit_ledger non vide, trg_leases_prevent_delete_with_deposit_
--    history), le contrat resterait supprimé alors que le bail survit.
--    Une fonction RPC unique (un seul appel, une seule transaction
--    implicite) : les deux suppressions réussissent ou échouent ensemble,
--    par construction.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. RLS — lease_contracts, nouvelle policy DELETE.
-- ----------------------------------------------------------------------------

create policy lease_contracts_delete on public.lease_contracts
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'delete')
  );

-- ----------------------------------------------------------------------------
-- 2. FONCTION RPC — supprime le contrat (s'il existe) puis le bail, dans la
--    même transaction implicite. PAS security definer : les deux DELETE
--    passent par les policies RLS normales sous l'identité de l'appelant —
--    un appelant sans la permission sur l'une des deux tables voit
--    l'ensemble échouer (ou, côté RLS, silencieusement ne rien affecter),
--    jamais un bypass. Le trigger de protection (Module 10/10c) reste seul
--    juge de la légitimité de chaque suppression, rien n'est revérifié ici.
-- ----------------------------------------------------------------------------

create or replace function public.delete_lease_with_contract(p_lease_id uuid)
returns void
language plpgsql
set search_path = public
as $$
begin
  delete from public.lease_contracts where lease_id = p_lease_id;
  delete from public.leases where id = p_lease_id;
end;
$$;

grant execute on function public.delete_lease_with_contract(uuid) to authenticated;
