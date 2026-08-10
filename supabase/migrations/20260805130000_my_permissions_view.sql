-- ============================================================================
-- VUE my_permissions — support applicatif (pas un "Module" métier).
-- Expose l'ensemble des permissions (resource, action) de l'utilisateur
-- courant, calculé UNE SEULE FOIS côté base. Le front se contente de lire
-- cette vue plutôt que de reconstruire la jointure user_roles/role_permissions
-- lui-même : si le modèle de permissions évolue, une seule définition à
-- ajuster, pas deux (schéma vérifié : user_roles.user_id existe bien,
-- références profiles(id)).
--
-- Vide pour un compte tenant (aucune ligne user_roles) — cohérent, l'accès
-- locataire ne passe jamais par has_permission().
-- ============================================================================

create view public.my_permissions
with (security_invoker = true)
as
select distinct rp.resource, rp.action
from public.user_roles ur
join public.role_permissions rp on rp.role_id = ur.role_id
where ur.user_id = auth.uid();

grant select on public.my_permissions to authenticated;
