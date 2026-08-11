-- ============================================================================
-- PORTAIL LOCATAIRE — LECTURE DES TYPES DE LOCATION PAR UN LOCATAIRE
-- Même trou que properties_select (voir migration précédente) :
-- property_types_select (Module 2) exigeait private.is_internal() sans
-- exception. Un locataire doit voir les types "système" (organization_id
-- null, globaux) et ceux propres à chaque organisation où il a une
-- adhésion active — même clause d'adhésion que organizations_select
-- (Module 1b), pour rester cohérent avec la seule autre policy qui gère
-- déjà "plusieurs organisations" pour un locataire.
-- ============================================================================

alter policy property_types_select on public.property_types
  using (
    (
      (organization_id is null or organization_id = private.current_org_id())
      and private.is_internal()
    )
    or (organization_id is null and private.is_tenant())
    or exists (
      select 1 from public.tenant_organization_memberships m
      where m.organization_id = property_types.organization_id
        and m.tenant_account_id = auth.uid()
        and m.status = 'actif'
    )
  );
