-- ============================================================================
-- MODULE 12q — public.create_property() : contourne le piège RETURNING/RLS
-- découvert empiriquement sur dev (Phase 3, correctif du sous-module 3).
--
-- Diagnostic : properties_insert n'a jamais été scopée par
-- agent_property_scope() (Module 12p, circularité assumée -- un bien qui
-- n'existe pas encore ne peut avoir d'assignation). Conséquence vérifiée
-- empiriquement : `insert ... returning *` échoue quand même pour un agent,
-- car Postgres filtre la clause RETURNING avec la policy SELECT de la
-- table -- et la ligne fraîchement créée n'a par construction aucune
-- assignation au moment où RETURNING est évalué. Un trigger AFTER INSERT
-- testé jetable sur dev ne corrige pas ça : les triggers AFTER ROW sont mis
-- en file et exécutés à la fin de la commande, APRÈS que RETURNING a déjà
-- été évalué -- confirmé empiriquement, pas une déduction théorique.
--
-- Solution retenue : une fonction SECURITY DEFINER qui pose l'assignation
-- AVANT de faire son propre `returning * into` (dans la même transaction,
-- avant que PostgREST n'ait besoin d'évaluer quoi que ce soit contre RLS
-- pour renvoyer la ligne au client -- la fonction elle-même n'est jamais
-- soumise au RETURNING/RLS de la table sous-jacente, seul son propre appel
-- RPC l'est, et une fonction SECURITY DEFINER n'est pas elle-même filtrée
-- par la RLS des tables qu'elle touche).
--
-- SECURITY DEFINER élève les privilèges pour ACCÉDER aux tables sans RLS --
-- ça ne dispense jamais l'appelant du droit métier lui-même. has_permission
-- et organization_id sont donc revérifiés explicitement ici, exactement ce
-- que la policy properties_insert fait déjà aujourd'hui (jamais contourné
-- silencieusement).
--
-- Auto-assignation réservée à un agent "pur" (a le rôle agent, ET n'a ni
-- admin ni comptable en plus) -- cohérent avec agent_property_scope() où le
-- rôle le plus large gagne déjà en cas de cumul : un admin/comptable qui
-- cumulerait aussi agent n'a de toute façon jamais besoin d'assignation
-- pour se voir lui-même.
-- ============================================================================

create or replace function public.create_property(
  p_organization_id   uuid,
  p_name               text,
  p_country_code       text,
  p_city               text,
  p_neighborhood       text,
  p_address_complement text,
  p_price              numeric,
  p_location_type      text
)
returns public.properties
language plpgsql
security definer
set search_path = public
as $$
declare
  v_property      public.properties;
  v_is_agent      boolean;
  v_is_broad_role boolean;
begin
  if not private.has_permission('properties', 'create') then
    raise exception 'Vous n''avez pas la permission de créer un bien'
      using detail = 'create_property.permission_denied', errcode = 'P0001';
  end if;

  if p_organization_id is distinct from private.current_org_id() then
    raise exception 'Organisation invalide'
      using detail = 'create_property.organization_mismatch', errcode = 'P0001';
  end if;

  insert into public.properties (
    organization_id, name, country_code, city, neighborhood,
    address_complement, price, location_type
  )
  values (
    p_organization_id, p_name, p_country_code, p_city, p_neighborhood,
    p_address_complement, p_price, p_location_type
  )
  returning * into v_property;

  select
    exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid() and r.code = 'agent'
    ),
    exists (
      select 1 from public.user_roles ur
      join public.roles r on r.id = ur.role_id
      where ur.user_id = auth.uid() and r.code in ('admin', 'comptable')
    )
  into v_is_agent, v_is_broad_role;

  if v_is_agent and not v_is_broad_role then
    insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
    values (p_organization_id, v_property.id, auth.uid(), auth.uid());
  end if;

  return v_property;
end;
$$;

-- Meme lecon que la brique has_permission abandonnee (Module 12o) : ce
-- projet porte un ALTER DEFAULT PRIVILEGES qui regrante EXECUTE a anon
-- DIRECTEMENT sur toute nouvelle fonction du schema public creee par
-- postgres -- un grant a authenticated seul ne suffit pas a l'exclure, il
-- faut explicitement revoquer public ET anon.
revoke execute on function public.create_property(uuid, text, text, text, text, text, numeric, text) from public;
revoke execute on function public.create_property(uuid, text, text, text, text, text, numeric, text) from anon;
grant execute on function public.create_property(uuid, text, text, text, text, text, numeric, text) to authenticated;
