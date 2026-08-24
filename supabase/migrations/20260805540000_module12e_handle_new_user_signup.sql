-- ============================================================================
-- MODULE 12e — Correction de private.handle_new_user() (Phase 2, volet 2).
--
-- Dette de sécurité identifiée en Phase 1 : la fonction faisait
-- aveuglément confiance à raw_user_meta_data.organization_id pour rattacher
-- un compte interne à une organisation existante. Aucun flux légitime
-- n'exploite ça aujourd'hui (pas d'invitation staff construite), donc la
-- correction retenue est radicale plutôt que "revérifier" : organization_id
-- n'est PLUS JAMAIS lu depuis les métadonnées pour un compte interne. Un
-- signup interne crée TOUJOURS une nouvelle organisation, dans la même
-- transaction que l'INSERT sur auth.users (déclenche en cascade
-- trg_seed_default_roles et trg_seed_default_subscription, déjà en place).
--
-- Un compte locataire, lui, n'a jamais de chemin sans jeton d'invitation
-- (pas d'auto-inscription locataire, décision actée) : organization_id
-- provient exclusivement de la ligne tenant_invitations validée (jamais du
-- client), verrouillée (FOR UPDATE) le temps de la validation pour empêcher
-- une double utilisation concurrente du même jeton.
-- ============================================================================

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_type  text := new.raw_user_meta_data ->> 'account_type';
  v_full_name     text := new.raw_user_meta_data ->> 'full_name';
  v_phone         text := new.raw_user_meta_data ->> 'phone';
  v_org_name      text;
  v_org_country   text;
  v_org_phone     text;
  v_org_id        uuid;
  v_admin_role_id uuid;
  v_slug          text;
  v_token         text;
  v_token_hash    text;
  v_invitation    record;
begin
  if v_account_type is null then
    raise exception 'account_type requis dans les métadonnées utilisateur'
      using detail = 'handle_new_user.account_type.missing', errcode = 'P0001';
  end if;

  if v_account_type = 'internal' then
    -- Toujours une nouvelle organisation. organization_id n'est jamais lu
    -- depuis raw_user_meta_data, meme s'il est present -- c'est
    -- precisement ce qui permettait la faille corrigee ici. Aucun chemin,
    -- dans ce chantier, ne permet a un compte interne de rejoindre une
    -- organisation existante par self-signup (l'invitation staff,
    -- permission users:create deja au catalogue, est un chantier futur --
    -- elle suivra le meme patron que l'invitation locataire ci-dessous).
    v_org_name    := new.raw_user_meta_data ->> 'organization_name';
    v_org_country := new.raw_user_meta_data ->> 'organization_country';
    v_org_phone   := new.raw_user_meta_data ->> 'organization_phone';

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

    insert into public.organizations (name, slug, country_code, phone)
    values (v_org_name, v_slug, v_org_country, v_org_phone)
    returning id into v_org_id;
    -- Declenche en cascade, dans la meme transaction :
    -- trg_seed_default_roles (admin/agent/comptable + permissions) et
    -- trg_seed_default_subscription (palier starter, statut essai).

    insert into public.profiles (id, organization_id, email, full_name, phone)
    values (new.id, v_org_id, new.email, v_full_name, v_phone);

    select id into v_admin_role_id
    from public.roles
    where organization_id = v_org_id and code = 'admin';

    insert into public.user_roles (user_id, role_id)
    values (new.id, v_admin_role_id);

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
