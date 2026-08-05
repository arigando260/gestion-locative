-- ============================================================================
-- MODULE 1b — IDENTITÉ LOCATAIRE GLOBALE
-- tenant_accounts devient une identité globale à la plateforme (plus de
-- organization_id). L'appartenance à une ou plusieurs organisations est
-- portée par tenant_organization_memberships, avec un statut actif/inactif.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TENANT_ORGANIZATION_MEMBERSHIPS — d'abord, pour pouvoir backfiller avant
--    de toucher à tenant_accounts.
-- ----------------------------------------------------------------------------

create table public.tenant_organization_memberships (
  id                uuid primary key default gen_random_uuid(),
  tenant_account_id uuid not null references public.tenant_accounts (id) on delete cascade,
  organization_id   uuid not null references public.organizations (id) on delete cascade,
  status            text not null default 'actif' check (status in ('actif', 'inactif')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint tenant_organization_memberships_unique unique (tenant_account_id, organization_id)
);

comment on table public.tenant_organization_memberships is
  'Rattachement d''un locataire (identité globale) à une organisation. Un même tenant_account peut avoir plusieurs lignes, une par organisation.';

create index tenant_org_memberships_tenant_idx on public.tenant_organization_memberships (tenant_account_id);
create index tenant_org_memberships_org_idx on public.tenant_organization_memberships (organization_id);

create trigger trg_tenant_org_memberships_updated_at
  before update on public.tenant_organization_memberships
  for each row execute function private.set_updated_at();

-- tenant_account_id et organization_id immuables après création : seul
-- status est modifiable (on ne "reconvertit" pas une ligne en une autre
-- relation, on en crée une nouvelle).
create or replace function private.prevent_membership_identity_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.tenant_account_id <> old.tenant_account_id
     or new.organization_id <> old.organization_id then
    raise exception 'tenant_account_id et organization_id sont immuables sur une adhésion';
  end if;
  return new;
end;
$$;

create trigger trg_tenant_org_memberships_prevent_identity_change
  before update on public.tenant_organization_memberships
  for each row execute function private.prevent_membership_identity_change();

-- Empêche de désactiver (status -> inactif) ou de supprimer une adhésion
-- tant qu'un bail actif existe pour ce couple (tenant, organisation).
create or replace function private.prevent_membership_deactivation_with_active_lease()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'UPDATE' and not (old.status = 'actif' and new.status = 'inactif') then
    return new;
  end if;

  if exists (
    select 1 from public.leases l
    where l.tenant_account_id = old.tenant_account_id
      and l.organization_id = old.organization_id
      and l.status = 'actif'
  ) then
    raise exception
      'Impossible de désactiver/supprimer ce rattachement : un bail actif existe pour ce locataire dans cette organisation (tenant %, organisation %)',
      old.tenant_account_id, old.organization_id;
  end if;

  return coalesce(new, old);
end;
$$;

create trigger trg_tenant_org_memberships_prevent_deactivate_with_lease
  before update or delete on public.tenant_organization_memberships
  for each row execute function private.prevent_membership_deactivation_with_active_lease();

-- Backfill : migre les rattachements existants avant de retirer la colonne.
-- No-op tant que tenant_accounts est vide, mais nécessaire pour que cette
-- migration reste correcte si des données existaient.
insert into public.tenant_organization_memberships (tenant_account_id, organization_id, status)
select id, organization_id, case when is_active then 'actif' else 'inactif' end
from public.tenant_accounts;

-- ----------------------------------------------------------------------------
-- 2. DÉMONTAGE de tout ce qui dépend de tenant_accounts.organization_id.
-- ----------------------------------------------------------------------------

drop policy tenant_accounts_select on public.tenant_accounts;
drop policy tenant_accounts_update on public.tenant_accounts;
drop policy tenant_accounts_delete on public.tenant_accounts;

drop trigger trg_tenant_accounts_prevent_org_change on public.tenant_accounts;

alter table public.leases drop constraint leases_tenant_org_fk;

alter table public.tenant_accounts drop constraint tenant_accounts_org_id_key;

alter table public.tenant_accounts drop column organization_id;

-- ----------------------------------------------------------------------------
-- 3. LEASES — FK simple vers tenant_accounts + vérification d'adhésion active
--    (remplace la FK composite qui n'a plus de sens).
-- ----------------------------------------------------------------------------

alter table public.leases
  add constraint leases_tenant_account_id_fkey
  foreign key (tenant_account_id) references public.tenant_accounts (id)
  on delete restrict;

create or replace function private.validate_lease_tenant_membership()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.tenant_organization_memberships m
    where m.tenant_account_id = new.tenant_account_id
      and m.organization_id = new.organization_id
      and m.status = 'actif'
  ) then
    raise exception
      'Bail impossible : le locataire % n''a pas de rattachement actif à l''organisation %',
      new.tenant_account_id, new.organization_id;
  end if;
  return new;
end;
$$;

create trigger trg_leases_validate_tenant_membership
  before insert or update of tenant_account_id, organization_id on public.leases
  for each row execute function private.validate_lease_tenant_membership();

-- ----------------------------------------------------------------------------
-- 4. FONCTIONS HELPER RLS — current_org_id() ne résout plus rien pour un
--    tenant (il peut appartenir à plusieurs organisations, il n'y a plus
--    d'"organisation courante" unique). is_internal(), is_tenant(),
--    has_permission(), enforce_account_type_exclusivity() : aucun changement,
--    ne référencent pas organization_id sur tenant_accounts.
-- ----------------------------------------------------------------------------

create or replace function private.current_org_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select organization_id from public.profiles where id = auth.uid() and is_active
$$;

-- ----------------------------------------------------------------------------
-- 5. HANDLE_NEW_USER — organization_id optionnel pour un tenant (obligatoire
--    pour un compte interne) ; crée l'adhésion si fourni.
-- ----------------------------------------------------------------------------

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_type    text := new.raw_user_meta_data ->> 'account_type';
  v_organization_id uuid := (new.raw_user_meta_data ->> 'organization_id')::uuid;
begin
  if v_account_type is null then
    raise exception 'account_type requis dans les métadonnées utilisateur';
  end if;

  if v_account_type = 'internal' then
    if v_organization_id is null then
      raise exception 'organization_id requis pour un compte interne';
    end if;
    insert into public.profiles (id, organization_id, email, full_name)
    values (new.id, v_organization_id, new.email, new.raw_user_meta_data ->> 'full_name');
  elsif v_account_type = 'tenant' then
    insert into public.tenant_accounts (id, email, full_name)
    values (new.id, new.email, new.raw_user_meta_data ->> 'full_name');

    if v_organization_id is not null then
      insert into public.tenant_organization_memberships (tenant_account_id, organization_id, status)
      values (new.id, v_organization_id, 'actif');
    end if;
  else
    raise exception 'account_type invalide: %', v_account_type;
  end if;

  return new;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. RECRÉATION des policies tenant_accounts (adhésion active plutôt que
--    colonne organization_id) — visibilité limitée à l'organisation avec
--    laquelle le rattachement est actif, pas toute la plateforme.
-- ----------------------------------------------------------------------------

create policy tenant_accounts_select on public.tenant_accounts
  for select
  using (
    id = auth.uid()
    or (
      exists (
        select 1 from public.tenant_organization_memberships m
        where m.tenant_account_id = tenant_accounts.id
          and m.organization_id = private.current_org_id()
          and m.status = 'actif'
      )
      and private.has_permission('tenant_accounts', 'read')
    )
  );

create policy tenant_accounts_update on public.tenant_accounts
  for update
  using (
    id = auth.uid()
    or (
      exists (
        select 1 from public.tenant_organization_memberships m
        where m.tenant_account_id = tenant_accounts.id
          and m.organization_id = private.current_org_id()
          and m.status = 'actif'
      )
      and private.has_permission('tenant_accounts', 'update')
    )
  );

create policy tenant_accounts_delete on public.tenant_accounts
  for delete
  using (
    exists (
      select 1 from public.tenant_organization_memberships m
      where m.tenant_account_id = tenant_accounts.id
        and m.organization_id = private.current_org_id()
        and m.status = 'actif'
    )
    and private.has_permission('tenant_accounts', 'delete')
  );

-- ----------------------------------------------------------------------------
-- 7. RLS sur tenant_organization_memberships elle-même (pas explicitement
--    demandé, mais nécessaire : sans RLS la table serait lisible/écrivable
--    par tout compte authentifié). Réutilise les permissions 'tenant_accounts'
--    déjà existantes plutôt que d'en créer de nouvelles.
-- ----------------------------------------------------------------------------

alter table public.tenant_organization_memberships enable row level security;

create policy tenant_org_memberships_select on public.tenant_organization_memberships
  for select
  using (
    tenant_account_id = auth.uid()
    or (
      organization_id = private.current_org_id()
      and private.has_permission('tenant_accounts', 'read')
    )
  );

create policy tenant_org_memberships_insert on public.tenant_organization_memberships
  for insert
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('tenant_accounts', 'create')
  );

create policy tenant_org_memberships_update on public.tenant_organization_memberships
  for update
  using (
    organization_id = private.current_org_id()
    and private.has_permission('tenant_accounts', 'update')
  )
  with check (organization_id = private.current_org_id());

create policy tenant_org_memberships_delete on public.tenant_organization_memberships
  for delete
  using (
    organization_id = private.current_org_id()
    and private.has_permission('tenant_accounts', 'delete')
  );

-- ----------------------------------------------------------------------------
-- 8. ORGANIZATIONS_SELECT — redonne au tenant l'accès à ses organisations
--    (perdu par la simplification de current_org_id() ci-dessus), via une
--    adhésion active plutôt que via une "organisation courante" unique.
-- ----------------------------------------------------------------------------

alter policy organizations_select on public.organizations
  using (
    id = private.current_org_id()
    or exists (
      select 1 from public.tenant_organization_memberships m
      where m.organization_id = organizations.id
        and m.tenant_account_id = auth.uid()
        and m.status = 'actif'
    )
  );
