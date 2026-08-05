-- ============================================================================
-- MODULE 1 — FONDATIONS
-- Organisations (tenants), utilisateurs internes + rôles/permissions,
-- comptes locataires, intégration Supabase Auth, isolation RLS.
--
-- NE PAS EXÉCUTER avant validation. Rien d'autre que le Module 1 n'est
-- construit ici (pas de biens, contrats, réservations, paiements).
-- ============================================================================

create extension if not exists pgcrypto;

-- Schéma non exposé par l'API PostgREST : réservé aux fonctions helper RLS
-- (security definer) qui doivent pouvoir lire les tables sans redéclencher
-- les policies elles-mêmes.
create schema if not exists private;

-- ============================================================================
-- 1. ORGANIZATIONS — le tenant
-- ============================================================================

create table public.organizations (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

comment on table public.organizations is
  'Une agence immobilière ou un propriétaire individuel. Racine de l''isolation multi-tenant.';

-- ============================================================================
-- 2. PROFILES — utilisateurs internes (Admin / Gestionnaire / Comptable...)
--    1 ligne = 1 auth.users, id partagé.
-- ============================================================================

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email           text not null,
  full_name       text,
  phone           text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Nécessaire pour permettre aux futures tables "internes" de faire une
  -- double FK (organization_id, profile_id) comme pour les locataires.
  constraint profiles_org_id_key unique (organization_id, id)
);

comment on table public.profiles is
  'Utilisateurs internes d''une organisation (staff agence / propriétaire).';

create index profiles_organization_id_idx on public.profiles (organization_id);

-- ============================================================================
-- 3. TENANT_ACCOUNTS — comptes locataires, type de compte distinct.
--    1 ligne = 1 auth.users, id partagé. JAMAIS dans profiles en même temps.
-- ============================================================================

create table public.tenant_accounts (
  id              uuid primary key references auth.users (id) on delete cascade,
  organization_id uuid not null references public.organizations (id) on delete cascade,
  email           text not null,
  full_name       text,
  phone           text,
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Clé composite utilisée par les futures tables de données locataire
  -- (réservations, documents, paiements...) pour la "double contrainte" :
  --   organization_id uuid references organizations(id),
  --   tenant_account_id uuid references ...,
  --   foreign key (organization_id, tenant_account_id)
  --     references tenant_accounts(organization_id, id)
  -- => l'organization_id d'une ligne enfant est garanti cohérent avec
  --    celui du locataire au niveau base de données, pas seulement via RLS.
  constraint tenant_accounts_org_id_key unique (organization_id, id)
);

comment on table public.tenant_accounts is
  'Comptes locataires. Isolation stricte : un locataire ne voit jamais un autre locataire, même de la même organisation.';

create index tenant_accounts_organization_id_idx on public.tenant_accounts (organization_id);

-- ============================================================================
-- 4. PERMISSIONS — catalogue global (resource, action). Référence en lecture
--    seule, alimentée par migration. Extensible sans changement de schéma :
--    on ajoute des lignes au fil des modules (biens, contrats, paiements...).
-- ============================================================================

create table public.permissions (
  resource    text not null,
  action      text not null,
  description text,
  primary key (resource, action)
);

comment on table public.permissions is
  'Catalogue des permissions possibles (resource x action). Référentiel technique, pas de RLS par organisation.';

insert into public.permissions (resource, action, description) values
  ('organizations',    'read',   'Consulter les informations de l''organisation'),
  ('organizations',    'update', 'Modifier les paramètres de l''organisation'),
  ('users',            'create', 'Inviter un utilisateur interne'),
  ('users',            'read',   'Consulter les utilisateurs internes'),
  ('users',            'update', 'Modifier un utilisateur interne'),
  ('users',            'delete', 'Désactiver / supprimer un utilisateur interne'),
  ('roles',            'create', 'Créer un rôle'),
  ('roles',            'read',   'Consulter les rôles et permissions'),
  ('roles',            'update', 'Modifier un rôle ou ses permissions'),
  ('roles',            'delete', 'Supprimer un rôle'),
  ('tenant_accounts',  'create', 'Créer un compte locataire'),
  ('tenant_accounts',  'read',   'Consulter les comptes locataires'),
  ('tenant_accounts',  'update', 'Modifier un compte locataire'),
  ('tenant_accounts',  'delete', 'Supprimer un compte locataire');

-- ============================================================================
-- 5. ROLES — définis par organisation (extensible), pas codés en dur.
--    3 rôles système créés automatiquement à la création d'une organisation.
-- ============================================================================

create table public.roles (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete cascade,
  code            text not null,
  name            text not null,
  description     text,
  is_system       boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint roles_org_id_key unique (organization_id, id),
  constraint roles_org_code_key unique (organization_id, code)
);

comment on table public.roles is
  'Rôles définis par organisation. Les 3 rôles système (admin, agent, comptable) sont créés automatiquement.';

create index roles_organization_id_idx on public.roles (organization_id);

-- ============================================================================
-- 6. ROLE_PERMISSIONS — la matrice rôle x resource x action.
-- ============================================================================

create table public.role_permissions (
  role_id     uuid not null references public.roles (id) on delete cascade,
  resource    text not null,
  action      text not null,
  created_at  timestamptz not null default now(),
  primary key (role_id, resource, action),
  foreign key (resource, action) references public.permissions (resource, action)
);

comment on table public.role_permissions is
  'Matrice de permissions : quelles actions un rôle peut effectuer sur quelle ressource.';

create index role_permissions_role_id_idx on public.role_permissions (role_id);

-- ============================================================================
-- 7. USER_ROLES — attribution des rôles aux utilisateurs internes (N:N,
--    un utilisateur peut cumuler plusieurs rôles).
-- ============================================================================

create table public.user_roles (
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role_id     uuid not null references public.roles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, role_id)
);

comment on table public.user_roles is
  'Attribution des rôles aux utilisateurs internes.';

create index user_roles_role_id_idx on public.user_roles (role_id);

-- ============================================================================
-- 8. FONCTIONS HELPER RLS (schéma private, security definer, search_path fixé)
-- ============================================================================

-- Organisation de l'utilisateur courant, qu'il soit interne ou locataire.
create or replace function private.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.profiles where id = auth.uid() and is_active
  union
  select organization_id from public.tenant_accounts where id = auth.uid() and is_active
  limit 1
$$;

create or replace function private.is_internal()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and is_active)
$$;

create or replace function private.is_tenant()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.tenant_accounts where id = auth.uid() and is_active)
$$;

-- Vérifie si l'utilisateur interne courant a la permission (resource, action)
-- via l'un de ses rôles. Toujours faux pour un locataire (absent de profiles).
create or replace function private.has_permission(p_resource text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    join public.user_roles ur on ur.user_id = p.id
    join public.role_permissions rp
      on rp.role_id = ur.role_id
     and rp.resource = p_resource
     and rp.action = p_action
    where p.id = auth.uid()
      and p.is_active
  )
$$;

-- ============================================================================
-- 9. TRIGGERS — updated_at, immutabilité organization_id, exclusivité
--    profiles/tenant_accounts, protection des rôles système, seed rôles par
--    défaut, création automatique profile/tenant_account à l'inscription.
-- ============================================================================

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_organizations_updated_at
  before update on public.organizations
  for each row execute function private.set_updated_at();

create trigger trg_profiles_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

create trigger trg_tenant_accounts_updated_at
  before update on public.tenant_accounts
  for each row execute function private.set_updated_at();

create trigger trg_roles_updated_at
  before update on public.roles
  for each row execute function private.set_updated_at();

-- organization_id immuable après création (defense in depth au-delà des RLS)
create or replace function private.prevent_org_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.organization_id <> old.organization_id then
    raise exception 'organization_id est immuable';
  end if;
  return new;
end;
$$;

create trigger trg_profiles_prevent_org_change
  before update on public.profiles
  for each row execute function private.prevent_org_change();

create trigger trg_tenant_accounts_prevent_org_change
  before update on public.tenant_accounts
  for each row execute function private.prevent_org_change();

create trigger trg_roles_prevent_org_change
  before update on public.roles
  for each row execute function private.prevent_org_change();

-- Un même auth.users ne doit jamais exister à la fois dans profiles et
-- dans tenant_accounts : exclusivité stricte interne / locataire.
create or replace function private.enforce_account_type_exclusivity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_TABLE_NAME = 'profiles' then
    if exists (select 1 from public.tenant_accounts where id = new.id) then
      raise exception 'Cet utilisateur est déjà un compte locataire';
    end if;
  elsif TG_TABLE_NAME = 'tenant_accounts' then
    if exists (select 1 from public.profiles where id = new.id) then
      raise exception 'Cet utilisateur est déjà un utilisateur interne';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_profiles_exclusivity
  before insert on public.profiles
  for each row execute function private.enforce_account_type_exclusivity();

create trigger trg_tenant_accounts_exclusivity
  before insert on public.tenant_accounts
  for each row execute function private.enforce_account_type_exclusivity();

-- Empêche la suppression / le renommage du code des rôles système.
create or replace function private.protect_system_role()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'DELETE' and old.is_system then
    raise exception 'Impossible de supprimer un rôle système';
  end if;
  if TG_OP = 'UPDATE' and old.is_system and new.code <> old.code then
    raise exception 'Impossible de renommer le code d''un rôle système';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trg_roles_protect_system
  before update or delete on public.roles
  for each row execute function private.protect_system_role();

-- À la création d'une organisation : seed des 3 rôles système + permissions
-- par défaut (proposition à valider, voir message d'accompagnement).
create or replace function private.seed_default_roles_for_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id     uuid;
  v_agent_id     uuid;
  v_comptable_id uuid;
begin
  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'admin', 'Administrateur', 'Accès complet à l''organisation', true)
  returning id into v_admin_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'agent', 'Gestionnaire / Agent', 'Gestion opérationnelle des locataires', true)
  returning id into v_agent_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'comptable', 'Comptable', 'Accès en lecture, périmètre financier à venir', true)
  returning id into v_comptable_id;

  -- Admin : toutes les permissions du catalogue.
  insert into public.role_permissions (role_id, resource, action)
  select v_admin_id, resource, action from public.permissions;

  -- Agent : gestion des locataires, lecture users/roles.
  insert into public.role_permissions (role_id, resource, action) values
    (v_agent_id, 'tenant_accounts', 'create'),
    (v_agent_id, 'tenant_accounts', 'read'),
    (v_agent_id, 'tenant_accounts', 'update'),
    (v_agent_id, 'users', 'read'),
    (v_agent_id, 'roles', 'read');

  -- Comptable : lecture seule.
  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read');

  return new;
end;
$$;

create trigger trg_seed_default_roles
  after insert on public.organizations
  for each row execute function private.seed_default_roles_for_org();

-- Création automatique de la ligne profiles/tenant_accounts au moment de
-- l'inscription Supabase Auth, à partir des métadonnées utilisateur.
-- Suppose un flux d'inscription "sur invitation" : organization_id et
-- account_type sont fournis via l'API Admin au moment de la création du
-- auth.users (pas d'auto-inscription publique sans contexte organisation).
create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_type   text := new.raw_user_meta_data ->> 'account_type';
  v_organization_id uuid := (new.raw_user_meta_data ->> 'organization_id')::uuid;
begin
  if v_account_type is null or v_organization_id is null then
    raise exception 'account_type et organization_id requis dans les métadonnées utilisateur';
  end if;

  if v_account_type = 'internal' then
    insert into public.profiles (id, organization_id, email, full_name)
    values (new.id, v_organization_id, new.email, new.raw_user_meta_data ->> 'full_name');
  elsif v_account_type = 'tenant' then
    insert into public.tenant_accounts (id, organization_id, email, full_name)
    values (new.id, v_organization_id, new.email, new.raw_user_meta_data ->> 'full_name');
  else
    raise exception 'account_type invalide: %', v_account_type;
  end if;

  return new;
end;
$$;

create trigger trg_handle_new_user
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ============================================================================
-- 10. ROW LEVEL SECURITY
-- ============================================================================

alter table public.organizations   enable row level security;
alter table public.profiles        enable row level security;
alter table public.tenant_accounts enable row level security;
alter table public.permissions     enable row level security;
alter table public.roles           enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles      enable row level security;

-- organizations --------------------------------------------------------------

create policy organizations_select on public.organizations
  for select
  using (id = private.current_org_id());

create policy organizations_update on public.organizations
  for update
  using (id = private.current_org_id() and private.has_permission('organizations', 'update'))
  with check (id = private.current_org_id());

-- profiles ---------------------------------------------------------------

create policy profiles_select on public.profiles
  for select
  using (
    organization_id = private.current_org_id()
    and (id = auth.uid() or private.has_permission('users', 'read'))
  );

create policy profiles_update on public.profiles
  for update
  using (
    organization_id = private.current_org_id()
    and (id = auth.uid() or private.has_permission('users', 'update'))
  )
  with check (organization_id = private.current_org_id());

create policy profiles_delete on public.profiles
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('users', 'delete')
    and id <> auth.uid()
  );

-- tenant_accounts ----------------------------------------------------------

create policy tenant_accounts_select on public.tenant_accounts
  for select
  using (
    id = auth.uid()
    or (organization_id = private.current_org_id() and private.has_permission('tenant_accounts', 'read'))
  );

create policy tenant_accounts_update on public.tenant_accounts
  for update
  using (
    id = auth.uid()
    or (organization_id = private.current_org_id() and private.has_permission('tenant_accounts', 'update'))
  )
  with check (organization_id = private.current_org_id());

create policy tenant_accounts_delete on public.tenant_accounts
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('tenant_accounts', 'delete')
  );

-- permissions (catalogue, lecture seule) ------------------------------------

create policy permissions_select on public.permissions
  for select
  to authenticated
  using (true);

-- roles ----------------------------------------------------------------------

create policy roles_select on public.roles
  for select
  using (organization_id = private.current_org_id());

create policy roles_insert on public.roles
  for insert
  with check (organization_id = private.current_org_id() and private.has_permission('roles', 'create'));

create policy roles_update on public.roles
  for update
  using (organization_id = private.current_org_id() and private.has_permission('roles', 'update'))
  with check (organization_id = private.current_org_id());

create policy roles_delete on public.roles
  for delete
  using (organization_id = private.current_org_id() and private.has_permission('roles', 'delete'));

-- role_permissions -------------------------------------------------------

create policy role_permissions_select on public.role_permissions
  for select
  using (
    exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and r.organization_id = private.current_org_id()
    )
  );

create policy role_permissions_insert on public.role_permissions
  for insert
  with check (
    private.has_permission('roles', 'update')
    and exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and r.organization_id = private.current_org_id()
    )
  );

create policy role_permissions_delete on public.role_permissions
  for delete
  using (
    private.has_permission('roles', 'update')
    and exists (
      select 1 from public.roles r
      where r.id = role_permissions.role_id
        and r.organization_id = private.current_org_id()
    )
  );

-- user_roles ---------------------------------------------------------------

create policy user_roles_select on public.user_roles
  for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = user_roles.user_id
        and p.organization_id = private.current_org_id()
    )
    and (user_id = auth.uid() or private.has_permission('users', 'read'))
  );

create policy user_roles_insert on public.user_roles
  for insert
  with check (
    private.has_permission('users', 'update')
    and exists (
      select 1 from public.profiles p
      where p.id = user_roles.user_id
        and p.organization_id = private.current_org_id()
    )
  );

create policy user_roles_delete on public.user_roles
  for delete
  using (
    private.has_permission('users', 'update')
    and exists (
      select 1 from public.profiles p
      where p.id = user_roles.user_id
        and p.organization_id = private.current_org_id()
    )
  );
