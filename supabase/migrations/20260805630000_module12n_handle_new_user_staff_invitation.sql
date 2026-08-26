-- ============================================================================
-- MODULE 12n — private.handle_new_user() : rattachement à une organisation
-- EXISTANTE via staff_invitations (Phase 3, sous-module 2, brique 2).
--
-- Dispatch précoce dans la branche account_type='internal', selon la
-- présence de staff_invitation_token dans les métadonnées :
--   - absent -> chemin inchangé depuis toujours (création d'une nouvelle
--     organisation, l'appelant en devient admin) ;
--   - présent -> nouveau chemin (rattachement à l'organisation de
--     l'invitation, avec le rôle qu'elle spécifie -- jamais de nouvelle
--     organisation créée dans ce cas).
--
-- Les deux chemins sont extraits en fonctions private séparées
-- (create_organization_for_new_user / join_organization_via_staff_invitation),
-- appelées depuis handle_new_user() -- pure lisibilité/testabilité interne,
-- le trigger AFTER INSERT ON auth.users reste un point de dispatch unique
-- (Postgres n'offre pas de mécanisme propre pour scinder un même événement
-- de trigger en plusieurs fonctions sans complexifier l'ordre d'exécution).
-- Comportement externe strictement inchangé pour les deux chemins déjà
-- existants (création d'organisation, acceptation locataire) : chacun est
-- un copier-coller caractère pour caractère de son code précédent,
-- seulement déplacé dans sa propre fonction / son propre embranchement.
--
-- join_organization_via_staff_invitation reprend le patron exact de la
-- branche tenant existante (FOR UPDATE, verrou anti-réutilisation
-- concurrente ; vérification status='en_attente' et expires_at ; email
-- correspondant) -- même défense, même slug DETAIL (staff_invitation.accept.*
-- au lieu de tenant_invitation.accept.*). Contrairement à la branche
-- tenant, pas de vérification "jeton manquant" à l'intérieur de cette
-- fonction : le dispatch dans handle_new_user() ne l'appelle QUE si un
-- jeton non vide est déjà présent, l'absence de jeton route simplement
-- vers create_organization_for_new_user() (comportement par défaut,
-- jamais une erreur).
-- ============================================================================

create or replace function private.create_organization_for_new_user(
  p_user_id   uuid,
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_meta      jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_name      text := p_meta ->> 'organization_name';
  v_org_country   text := p_meta ->> 'organization_country';
  v_org_phone     text := p_meta ->> 'organization_phone';
  v_org_type      text := p_meta ->> 'organization_type';
  v_org_id        uuid;
  v_admin_role_id uuid;
  v_slug          text;
begin
  if v_org_name is null or btrim(v_org_name) = '' then
    raise exception 'Nom de l''organisation requis pour l''inscription'
      using detail = 'handle_new_user.internal.organization_name_missing', errcode = 'P0001';
  end if;
  if v_org_country is null or btrim(v_org_country) = '' then
    raise exception 'Pays de l''organisation requis pour l''inscription'
      using detail = 'handle_new_user.internal.organization_country_missing', errcode = 'P0001';
  end if;
  if v_org_phone is null or btrim(v_org_phone) = '' then
    raise exception 'Téléphone de l''organisation requis pour l''inscription'
      using detail = 'handle_new_user.internal.organization_phone_missing', errcode = 'P0001';
  end if;

  v_slug := lower(regexp_replace(v_org_name, '[^a-zA-Z0-9]+', '-', 'g'));
  v_slug := trim(both '-' from v_slug) || '-' || substr(gen_random_uuid()::text, 1, 8);

  insert into public.organizations (name, slug, country_code, phone, organization_type)
  values (v_org_name, v_slug, v_org_country, v_org_phone, v_org_type)
  returning id into v_org_id;
  -- Declenche en cascade, dans la meme transaction :
  -- trg_seed_default_roles (admin/agent/comptable + permissions) et
  -- trg_seed_default_subscription (palier starter, statut essai).

  insert into public.profiles (id, organization_id, email, full_name, phone)
  values (p_user_id, v_org_id, p_email, p_full_name, p_phone);

  select id into v_admin_role_id
  from public.roles
  where organization_id = v_org_id and code = 'admin';

  insert into public.user_roles (user_id, role_id)
  values (p_user_id, v_admin_role_id);
end;
$$;

create or replace function private.join_organization_via_staff_invitation(
  p_user_id   uuid,
  p_email     text,
  p_full_name text,
  p_phone     text,
  p_token     text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token_hash text;
  v_invitation record;
  v_role_id    uuid;
begin
  v_token_hash := encode(extensions.digest(p_token, 'sha256'), 'hex');

  -- FOR UPDATE : meme verrou anti-reutilisation concurrente que la branche
  -- tenant (et la limite de biens, Module 11).
  select * into v_invitation
  from public.staff_invitations
  where token_hash = v_token_hash
    and status = 'en_attente'
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Invitation invalide ou expirée'
      using detail = 'staff_invitation.accept.invalid_or_expired', errcode = 'P0001';
  end if;

  if lower(p_email) <> lower(v_invitation.email) then
    raise exception 'Cette invitation a été émise pour une autre adresse email'
      using detail = 'staff_invitation.accept.email_mismatch', errcode = 'P0001';
  end if;

  select id into v_role_id
  from public.roles
  where organization_id = v_invitation.organization_id and code = v_invitation.role_code;

  -- Ne peut normalement jamais se produire (role_code contraint aux 3 codes
  -- systeme, seedes pour toute organisation par trg_seed_default_roles) --
  -- garde defensive plutot qu'un INSERT user_roles avec role_id NULL en
  -- silence.
  if v_role_id is null then
    raise exception 'Rôle "%" introuvable dans l''organisation invitante', v_invitation.role_code
      using detail = 'staff_invitation.accept.role_not_found', errcode = 'P0001';
  end if;

  insert into public.profiles (id, organization_id, email, full_name, phone)
  values (p_user_id, v_invitation.organization_id, p_email, p_full_name, p_phone);

  insert into public.user_roles (user_id, role_id)
  values (p_user_id, v_role_id);

  update public.staff_invitations
  set status = 'acceptee', accepted_at = now(), accepted_by = p_user_id
  where id = v_invitation.id;
end;
$$;

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_type           text := new.raw_user_meta_data ->> 'account_type';
  v_full_name              text := new.raw_user_meta_data ->> 'full_name';
  v_phone                  text := new.raw_user_meta_data ->> 'phone';
  v_staff_invitation_token text;
  v_token                  text;
  v_token_hash             text;
  v_invitation             record;
begin
  if v_account_type is null then
    raise exception 'account_type requis dans les métadonnées utilisateur'
      using detail = 'handle_new_user.account_type.missing', errcode = 'P0001';
  end if;

  if v_account_type = 'internal' then
    v_staff_invitation_token := new.raw_user_meta_data ->> 'staff_invitation_token';

    if v_staff_invitation_token is not null and btrim(v_staff_invitation_token) <> '' then
      perform private.join_organization_via_staff_invitation(
        new.id, new.email, v_full_name, v_phone, v_staff_invitation_token
      );
    else
      perform private.create_organization_for_new_user(
        new.id, new.email, v_full_name, v_phone, new.raw_user_meta_data
      );
    end if;

  elsif v_account_type = 'tenant' then
    -- Pas d'auto-inscription locataire : un jeton d'invitation valide est
    -- obligatoire dans tous les cas.
    v_token := new.raw_user_meta_data ->> 'invitation_token';
    if v_token is null or btrim(v_token) = '' then
      raise exception 'Jeton d''invitation requis pour un compte locataire'
        using detail = 'handle_new_user.tenant.invitation_token_missing', errcode = 'P0001';
    end if;

    v_token_hash := encode(extensions.digest(v_token, 'sha256'), 'hex');

    -- FOR UPDATE : verrouille la ligne le temps de la validation, empeche
    -- deux tentatives concurrentes d'accepter le meme jeton (meme logique
    -- que le verrou de limite de biens, Module 11).
    select * into v_invitation
    from public.tenant_invitations
    where token_hash = v_token_hash
      and status = 'en_attente'
      and expires_at > now()
    for update;

    if not found then
      raise exception 'Invitation invalide ou expirée'
        using detail = 'tenant_invitation.accept.invalid_or_expired', errcode = 'P0001';
    end if;

    if lower(new.email) <> lower(v_invitation.email) then
      raise exception 'Cette invitation a été émise pour une autre adresse email'
        using detail = 'tenant_invitation.accept.email_mismatch', errcode = 'P0001';
    end if;

    -- tenant_accounts doit exister avant que tenant_invitations.accepted_by
    -- (FK vers tenant_accounts) puisse le referencer.
    insert into public.tenant_accounts (id, email, full_name, phone)
    values (new.id, new.email, v_full_name, v_phone);

    update public.tenant_invitations
    set status = 'acceptee', accepted_at = now(), accepted_by = new.id
    where id = v_invitation.id;

    insert into public.tenant_organization_memberships (tenant_account_id, organization_id, status)
    values (new.id, v_invitation.organization_id, 'actif');

  else
    raise exception 'account_type invalide: %', v_account_type
      using detail = 'handle_new_user.account_type.invalid', errcode = 'P0001';
  end if;

  return new;
end;
$$;
