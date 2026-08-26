-- ============================================================================
-- MODULE 12m — Fondation invitation staff (Phase 3, sous-module 2, brique 1).
--
-- Même patron que tenant_invitations (Module 12d) : jeton à usage unique
-- (SHA-256, jamais stocké en clair), expiration, statut. organization_id
-- n'est JAMAIS fourni par le client à l'insertion -- toujours celle de
-- l'admin qui invite (organization_id = private.current_org_id(), posé par
-- la policy INSERT, pas par l'appelant), même garde-fou que
-- tenant_invitations_insert.
--
-- role_code (admin/agent/comptable) : le rôle système que l'invité recevra
-- dans l'organisation invitante. Les 3 rôles existent déjà par construction
-- dans toute organisation (seed_default_roles_for_org, Module 1) -- cette
-- brique ne crée aucun rôle, ne fait qu'enregistrer l'intention.
--
-- RLS : réutilise les permissions users:create/read/update déjà au
-- catalogue depuis le Module 1 (jamais accordées qu'à admin aujourd'hui,
-- vérifié : agent et comptable n'ont que users:read) -- même raisonnement
-- que tenant_invitations réutilisant tenant_accounts:* plutôt que d'inventer
-- un jeu de permissions dédié : "inviter un collaborateur" EST
-- conceptuellement users:create, juste différé.
--
-- N'écrit PAS encore private.handle_new_user() (pas de branche
-- "rattachement à une organisation existante" pour un compte interne) ni
-- l'écran -- fondation seule. accepted_by référence profiles (pas
-- tenant_accounts comme tenant_invitations.accepted_by), cohérent avec le
-- type de compte que cette invitation produira une fois la branche
-- handle_new_user() écrite.
-- ============================================================================

create table public.staff_invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  email           text not null,
  role_code       text not null check (role_code in ('admin', 'agent', 'comptable')),
  token_hash      text not null unique,
  status          text not null default 'en_attente'
                     check (status in ('en_attente', 'acceptee', 'expiree', 'revoquee')),
  invited_by      uuid not null references public.profiles (id) on delete restrict,
  accepted_by     uuid references public.profiles (id) on delete restrict,
  expires_at      timestamptz not null,
  created_at      timestamptz not null default now(),
  accepted_at     timestamptz
);

create index staff_invitations_organization_id_idx on public.staff_invitations (organization_id);

alter table public.staff_invitations enable row level security;

create policy staff_invitations_select on public.staff_invitations
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('users', 'read')
  );

create policy staff_invitations_insert on public.staff_invitations
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('users', 'create')
    and invited_by = auth.uid()
  );

-- UPDATE réservé à la révocation par le staff (status -> 'revoquee') --
-- l'acceptation elle-même (status -> 'acceptee') passera, une fois écrite,
-- par private.handle_new_user() (SECURITY DEFINER), jamais par cette policy
-- -- même principe que tenant_invitations_update.
create policy staff_invitations_update on public.staff_invitations
  for update
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('users', 'update')
  )
  with check (organization_id = private.current_org_id());

-- Pas de policy DELETE : historique conservé, même logique que
-- tenant_invitations et le reste du schéma.

-- ----------------------------------------------------------------------------
-- Aperçu pré-inscription — miroir exact de get_tenant_invitation_preview
-- (Module 12d). En public (pas private) : appelable via .rpc() depuis le
-- client, private est exclu de l'exposition PostgREST.
-- ----------------------------------------------------------------------------

create or replace function public.get_staff_invitation_preview(p_token text)
returns table (organization_name text, email text, role_code text, status text, expires_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select o.name, si.email, si.role_code, si.status, si.expires_at
  from public.staff_invitations si
  join public.organizations o on o.id = si.organization_id
  where si.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  limit 1
$$;

grant execute on function public.get_staff_invitation_preview(text) to anon, authenticated;

-- ----------------------------------------------------------------------------
-- Détection amont "email déjà existant" -- contrairement à
-- check_tenant_invitation_existing_account (Module 12g, qui vérifie
-- spécifiquement tenant_accounts pour permettre ensuite un rattachement,
-- Module 12h), il n'existe structurellement AUCUN chemin de rattachement
-- possible côté staff : public.profiles est 1 ligne = 1 auth.users, avec
-- organization_id NOT NULL et non modifiable après création
-- (trg_profiles_prevent_org_change) -- une identité auth.users ne peut
-- appartenir qu'à UNE SEULE organisation, à vie, côté staff (pas d'équivalent
-- de tenant_organization_memberships). Un email déjà présent dans
-- auth.users -- qu'il s'agisse d'un compte staff d'une autre organisation
-- OU d'un compte locataire -- fera silencieusement échouer signUp()
-- (comportement anti-énumération GoTrue, déjà rencontré et documenté au
-- Module 12g). Cette fonction sert donc uniquement à détecter le cas EN
-- AMONT pour afficher un refus explicite côté écran, jamais à proposer un
-- rattachement -- d'où une vérification large sur auth.users.email
-- directement, pas restreinte à profiles comme le serait l'équivalent
-- naïf de la version tenant.
-- ----------------------------------------------------------------------------

create or replace function public.check_staff_invitation_existing_account(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select si.email into v_email
  from public.staff_invitations si
  where si.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and si.status = 'en_attente'
    and si.expires_at > now();

  if not found then
    return false;
  end if;

  return exists (
    select 1 from auth.users where lower(email) = lower(v_email)
  );
end;
$$;

grant execute on function public.check_staff_invitation_existing_account(text) to anon, authenticated;
