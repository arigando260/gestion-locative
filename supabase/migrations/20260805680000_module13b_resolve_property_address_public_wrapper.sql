-- ============================================================================
-- MODULE 13b — Wrapper public pour private.resolve_property_address()
-- (Phase 4, suite module buildings -- couche écran).
--
-- private.resolve_property_address() (Module 13) n'est pas appelable depuis
-- l'application : le schéma `private` est délibérément exclu de
-- l'exposition PostgREST dans ce projet (voir commentaires Module 12m). Un
-- wrapper est nécessaire pour la fiche bien, la liste des biens, et la
-- génération des PDF (contrat, facture).
--
-- PAS un simple pass-through SECURITY DEFINER : getLeaseContractRenderData()
-- (data/lease-contracts.ts) peut être déclenchée par un LOCATAIRE (première
-- génération du contrat côté locataire, voir actions/lease-contracts.tsx --
-- "Partagée staff/locataire"), pas seulement le staff. Si ce wrapper était
-- SECURITY DEFINER de bout en bout, n'importe quel utilisateur authentifié
-- pourrait lui passer un property_id ARBITRAIRE (pas seulement le sien) et
-- lire l'adresse d'un bien auquel il n'a par ailleurs aucun accès --
-- private.resolve_property_address() ne vérifie elle-même aucune
-- permission, par construction (elle suppose que l'appelant a déjà lu la
-- ligne properties via RLS avant de l'appeler -- vrai pour tout le code SQL
-- interne existant, plus vrai du tout pour un point d'entrée RPC exposé au
-- client).
--
-- Solution : ce wrapper est SECURITY INVOKER. La vérification de visibilité
-- (`exists (select 1 from public.properties where id = p_property_id)`)
-- s'exécute donc sous le VRAI contexte RLS de l'appelant -- exactement la
-- policy properties_select déjà en place (staff scopé par
-- agent_property_scope(), locataire scopé par son bail), jamais dupliquée
-- ici. Seulement si cette vérification passe, on délègue à
-- private.resolve_property_address() (SECURITY DEFINER, inchangée) pour
-- l'enrichissement via buildings -- un locataire n'a par ailleurs aucun
-- accès direct à la table buildings, mais peut légitimement voir l'adresse
-- de l'immeuble de SON bien une fois l'accès à la ligne properties
-- elle-même confirmé.
-- ============================================================================

create or replace function public.resolve_property_address(p_property_id uuid)
returns table (
  formatted_address  text,
  country_code       text,
  city               text,
  neighborhood       text,
  address_complement text,
  unit_complement    text,
  building_id        uuid,
  building_name      text
)
language plpgsql
stable
security invoker
set search_path = public
as $$
begin
  if not exists (select 1 from public.properties p where p.id = p_property_id) then
    return;
  end if;

  return query select * from private.resolve_property_address(p_property_id);
end;
$$;

comment on function public.resolve_property_address is
  'Wrapper public de private.resolve_property_address() (Module 13). SECURITY INVOKER : la vérification de visibilité sur properties s''exécute sous le RLS réel de l''appelant (properties_select) avant toute délégation vers la fonction SECURITY DEFINER -- jamais un point d''entrée pour lire l''adresse d''un bien arbitraire.';

revoke execute on function public.resolve_property_address(uuid) from public;
revoke execute on function public.resolve_property_address(uuid) from anon;
grant execute on function public.resolve_property_address(uuid) to authenticated;
