-- ============================================================================
-- MODULE 12d — Invitation locataire par lien à usage unique (Phase 2,
-- volet 2).
--
-- token_hash stocke le SHA-256 du jeton en hexadécimal (encode(digest(...,
-- 'sha256'), 'hex')) — jamais le jeton en clair. Le jeton brut est généré
-- côté Server Action (crypto.randomBytes), envoyé uniquement dans le lien
-- email ; la base ne connaît que son empreinte. Toute vérification future
-- (côté app comme dans private.handle_new_user, Module 12e) doit hasher de
-- la même façon (SHA-256, hex) pour comparer.
--
-- Pas de policy SELECT pour l'invité : au moment où il ne tient qu'un
-- jeton, il n'a pas encore de session (l'inscription n'a pas eu lieu).
-- get_tenant_invitation_preview() ci-dessous est la seule porte d'entrée
-- pré-inscription, volontairement minimale (nom de l'organisation, email,
-- statut, expiration — jamais le hash ni les autres invitations).
--
-- RLS staff : réutilise les permissions tenant_accounts déjà existantes
-- (create/read/update) plutôt que d'en créer de nouvelles — inviter un
-- locataire est conceptuellement "créer un compte locataire", juste
-- différé.
-- ============================================================================

create table public.tenant_invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  email           text not null,
  token_hash      text not null unique,
  status          text not null default 'en_attente'
                     check (status in ('en_attente', 'acceptee', 'expiree', 'revoquee')),
  invited_by      uuid not null references public.profiles (id) on delete restrict,
  accepted_by     uuid references public.tenant_accounts (id) on delete restrict,
  expires_at      timestamptz not null,
  created_at      timestamptz not null default now(),
  accepted_at     timestamptz
);

create index tenant_invitations_organization_id_idx on public.tenant_invitations (organization_id);

alter table public.tenant_invitations enable row level security;

create policy tenant_invitations_select on public.tenant_invitations
  for select
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('tenant_accounts', 'read')
  );

create policy tenant_invitations_insert on public.tenant_invitations
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('tenant_accounts', 'create')
    and invited_by = auth.uid()
  );

-- UPDATE réservé à la révocation par le staff (status -> 'revoquee').
-- L'acceptation elle-même (status -> 'acceptee') passe par
-- private.handle_new_user() (SECURITY DEFINER, Module 12e), jamais par
-- cette policy — l'invité n'a pas de session au moment où il agit dessus.
create policy tenant_invitations_update on public.tenant_invitations
  for update
  using (
    organization_id = private.current_org_id()
    and private.is_internal()
    and private.has_permission('tenant_accounts', 'update')
  )
  with check (organization_id = private.current_org_id());

-- Pas de policy DELETE : historique conservé, même logique que le reste du
-- schéma (rien n'est effacé, tout est un statut).

-- ----------------------------------------------------------------------------
-- Aperçu pré-inscription — seule information consultable sans session,
-- strictement limitée à ce qu'il faut pour afficher "vous êtes invité chez
-- X" avant que l'invité ne crée son compte.
-- ----------------------------------------------------------------------------

create or replace function public.get_tenant_invitation_preview(p_token text)
returns table (organization_name text, email text, status text, expires_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  -- digest() qualifié extensions.digest() : pgcrypto vit dans le schéma
  -- extensions sur ce projet, exclu par le search_path restreint à public
  -- ci-dessus (choix volontaire pour une fonction SECURITY DEFINER).
  select o.name, ti.email, ti.status, ti.expires_at
  from public.tenant_invitations ti
  join public.organizations o on o.id = ti.organization_id
  where ti.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
  limit 1
$$;

grant execute on function public.get_tenant_invitation_preview(text) to anon, authenticated;
