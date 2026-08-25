-- ============================================================================
-- MODULE 12h — Rattachement direct d'un locataire déjà existant à une
-- nouvelle organisation, sans passer par signUp() (Phase 2, volet 2,
-- suivi).
--
-- Complète Module 12g : une fois détecté qu'un compte locataire existe
-- déjà pour l'email de l'invitation, l'acceptation ne peut plus passer
-- par private.handle_new_user() (déclenché uniquement à la création d'un
-- auth.users, qui n'a pas lieu ici). Cette fonction reprend la même
-- validation que la branche tenant de handle_new_user (jeton + verrou +
-- vérification email), moins la création de tenant_accounts (déjà là) :
-- ajoute seulement le rattachement à la nouvelle organisation.
--
-- En public (même raison que Module 12g). SECURITY DEFINER nécessaire :
-- ni tenant_invitations ni tenant_organization_memberships ne sont
-- accessibles en écriture à un locataire via RLS (policies réservées au
-- staff -- is_internal() + permissions). Callable seulement par
-- authenticated (pas anon, contrairement à la fonction de détection) --
-- identifie l'appelant exclusivement via auth.uid(), jamais un paramètre
-- fourni par le client.
--
-- ON CONFLICT DO NOTHING sur l'insertion du rattachement : idempotent si
-- l'invitation est revisitée alors que le rattachement existe déjà
-- (contrainte unique tenant_account_id/organization_id, Module 1b) --
-- l'invitation est quand même marquée acceptée dans ce cas, le but
-- fonctionnel (le rattachement existe) étant de toute façon atteint.
-- ============================================================================

create or replace function public.accept_tenant_invitation_existing_account(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invitation   record;
  v_caller_id    uuid := auth.uid();
  v_caller_email text;
begin
  if v_caller_id is null then
    raise exception 'Connexion requise pour accepter cette invitation'
      using detail = 'tenant_invitation.accept_existing.not_authenticated', errcode = 'P0001';
  end if;

  select * into v_invitation
  from public.tenant_invitations
  where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and status = 'en_attente'
    and expires_at > now()
  for update;

  if not found then
    raise exception 'Invitation invalide ou expirée'
      using detail = 'tenant_invitation.accept.invalid_or_expired', errcode = 'P0001';
  end if;

  select email into v_caller_email from auth.users where id = v_caller_id;

  if lower(v_caller_email) <> lower(v_invitation.email) then
    raise exception 'Cette invitation a été émise pour une autre adresse email'
      using detail = 'tenant_invitation.accept.email_mismatch', errcode = 'P0001';
  end if;

  -- Garde explicite plutôt qu'une violation de clé étrangère brute sur
  -- l'INSERT ci-dessous : ne devrait jamais se produire si l'écran est
  -- passé par check_tenant_invitation_existing_account() au préalable
  -- (Module 12g, qui vérifie déjà tenant_accounts), mais cette fonction
  -- ne fait jamais confiance à ce qui a été vérifié plus tôt dans la
  -- requête -- revalidée ici aussi.
  if not exists (select 1 from public.tenant_accounts where id = v_caller_id) then
    raise exception 'Aucun compte locataire associé à cet utilisateur'
      using detail = 'tenant_invitation.accept_existing.not_a_tenant_account', errcode = 'P0001';
  end if;

  insert into public.tenant_organization_memberships (tenant_account_id, organization_id, status)
  values (v_caller_id, v_invitation.organization_id, 'actif')
  on conflict (tenant_account_id, organization_id) do nothing;

  update public.tenant_invitations
  set status = 'acceptee', accepted_at = now(), accepted_by = v_caller_id
  where id = v_invitation.id;
end;
$$;

grant execute on function public.accept_tenant_invitation_existing_account(text) to authenticated;
