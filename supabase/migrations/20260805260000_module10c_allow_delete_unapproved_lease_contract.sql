-- ============================================================================
-- MODULE 10c — LEASE_CONTRACTS NON APPROUVÉ : SUPPRESSION AUTORISÉE.
--
-- Trou découvert en nettoyant des données réelles (baux 'brouillon' de
-- test, Agence Demo, créés pendant la vérification du Volet A) :
-- trg_lease_contracts_prevent_delete (Module 10) interdisait TOUTE
-- suppression d'un lease_contracts, y compris pour service_role — ce qui
-- bloquait par ricochet la suppression du bail brouillon associé
-- (lease_contracts_lease_org_fk, ON DELETE RESTRICT, empêche de supprimer
-- un bail tant que sa ligne lease_contracts existe), alors même que le
-- mécanisme de refus de contrat (Module 10, "suppression d'un brouillon
-- sans deposit_ledger") ne tenait compte que de deposit_ledger, pas de
-- lease_contracts.
--
-- Un contrat jamais approuvé (approved_at IS NULL) ne représente aucun
-- engagement réel — devient supprimable. Un contrat approuvé reste
-- immuable, SANS changement : c'est la preuve de l'engagement contractuel
-- effectif une fois le bail activé. payment_receipts/schedule_invoices
-- (Module 9) restent totalement inchangés — aucune notion d'approbation
-- chez eux, donc non concernés par ce changement.
-- ============================================================================

create or replace function private.prevent_lease_contract_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.approved_at is not null then
    raise exception 'Un contrat de bail déjà approuvé est immuable : suppression impossible'
      using detail = 'lease_contract.delete.immutable', errcode = 'P0001';
  end if;
  return old;
end;
$$;
