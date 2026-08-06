-- ============================================================================
-- MODULE 6d — CORRECTIFS ISSUS DE L'AUDIT TRANSVERSAL POST-6c
-- Trois trous confirmés empiriquement, corrigés par ordre de gravité.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. HORODATAGE D'AUDIT FABRICABLE (le plus grave).
-- ----------------------------------------------------------------------------

-- 1a. Le trigger d'audit ne doit plus jamais reprendre une valeur saisie par
-- le staff : now() sans condition, comme le cas 'revoked' le faisait déjà.
create or replace function private.log_lease_advance_authorization_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.advance_consumption_authorized = true and old.advance_consumption_authorized = false then
    insert into public.lease_advance_authorization_events (organization_id, lease_id, action, actor_id, occurred_at)
    values (new.organization_id, new.id, 'authorized', auth.uid(), now());
  elsif new.advance_consumption_authorized = false and old.advance_consumption_authorized = true then
    insert into public.lease_advance_authorization_events (organization_id, lease_id, action, actor_id, occurred_at)
    values (new.organization_id, new.id, 'revoked', auth.uid(), now());
  end if;
  return new;
end;
$$;

-- 1b. leases.advance_consumption_authorized_at posé par le serveur, jamais
-- saisi librement — même raisonnement que finalized_at/uploaded_at. Couvre
-- l'INSERT direct (leçon du bug 6b) et l'UPDATE (transition ou tentative de
-- modification directe).
create or replace function private.set_advance_consumption_authorized_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if new.advance_consumption_authorized = true then
      new.advance_consumption_authorized_at := now();
    end if;
    return new;
  end if;

  -- TG_OP = 'UPDATE'
  if new.advance_consumption_authorized = true and old.advance_consumption_authorized = false then
    new.advance_consumption_authorized_at := now();
    return new;
  end if;

  if new.advance_consumption_authorized = false and old.advance_consumption_authorized = true then
    -- La contrainte de cohérence (leases_advance_authorization_consistency)
    -- exige déjà NULL pour cette transition ; rien à forcer ici.
    return new;
  end if;

  if new.advance_consumption_authorized_at is distinct from old.advance_consumption_authorized_at then
    raise exception 'advance_consumption_authorized_at est posé par le serveur au moment de l''autorisation, jamais modifiable directement';
  end if;

  return new;
end;
$$;

create trigger trg_leases_set_advance_consumption_authorized_at
  before insert or update on public.leases
  for each row execute function private.set_advance_consumption_authorized_at();

-- ----------------------------------------------------------------------------
-- 2. inspection_photos.file_hash / storage_path modifiables après insertion.
-- Interdiction totale de modification, indépendamment du statut de
-- finalisation (contrairement à prevent_finalized_inspection_photo_change,
-- qui ne s'applique qu'une fois l'état des lieux parent finalisé) — cohérent
-- avec le principe déjà en place : une correction passe par un nouvel
-- enregistrement (suppression + nouvel envoi), jamais par une modification
-- du contenu d'une photo existante.
-- ----------------------------------------------------------------------------

create or replace function private.prevent_inspection_photo_content_change()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.file_hash is distinct from old.file_hash
     or new.storage_path is distinct from old.storage_path then
    raise exception 'file_hash et storage_path sont immuables après insertion : pour corriger une photo, supprimez-la et envoyez-en une nouvelle';
  end if;
  return new;
end;
$$;

create trigger trg_inspection_photos_prevent_content_change
  before update on public.inspection_photos
  for each row execute function private.prevent_inspection_photo_content_change();

-- ----------------------------------------------------------------------------
-- 3. roles.is_system auto-attribuable en dehors du seed automatique.
-- pg_trigger_depth() distingue structurellement un appel imbriqué (depuis
-- seed_default_roles_for_org, lui-même déclenché par un trigger AFTER INSERT
-- sur organizations, donc profondeur >= 2 au moment où ce trigger-ci
-- s'exécute) d'un appel direct par un client (profondeur = 1). Bloque tout
-- changement de is_system hors du seed, dans les deux sens : false -> true
-- (auto-attribution) ET true -> false, ce dernier étant le contournement en
-- deux temps de protect_system_role (Module 1) — dégrader un vrai rôle
-- système le fait sortir du champ d'application de cette protection
-- (basée sur old.is_system), après quoi renommage/suppression deviennent
-- libres.
-- ----------------------------------------------------------------------------

create or replace function private.prevent_direct_system_role_creation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if TG_OP = 'INSERT' and new.is_system = true then
    raise exception 'is_system ne peut être posé à true que par le seed automatique de l''organisation, jamais directement';
  end if;

  if TG_OP = 'UPDATE' and new.is_system is distinct from old.is_system then
    raise exception 'is_system ne peut être modifié (dans un sens ou l''autre) en dehors du seed automatique de l''organisation — dégrader un rôle système le sortirait de la protection contre le renommage/la suppression';
  end if;

  return new;
end;
$$;

create trigger trg_roles_prevent_direct_system_creation
  before insert or update on public.roles
  for each row execute function private.prevent_direct_system_role_creation();
