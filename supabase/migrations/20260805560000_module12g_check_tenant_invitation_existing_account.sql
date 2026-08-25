-- ============================================================================
-- MODULE 12g — Détection d'un compte locataire déjà existant pour une
-- invitation (Phase 2, volet 2, suivi).
--
-- Problème découvert en test manuel : un locataire déjà inscrit (via une
-- première organisation) invité par une DEUXIÈME organisation voit
-- signUp() échouer silencieusement (comportement anti-énumération de
-- GoTrue, vérifié empiriquement : succès factice avec identities: [],
-- aucune ligne auth.users créée, private.handle_new_user() ne se
-- déclenche jamais). Cette fonction permet à l'écran de détecter ce cas
-- AVANT de tenter signUp(), pour proposer un chemin différent (connexion
-- + rattachement direct, Module 12h).
--
-- En public (pas private) : doit être appelable via .rpc() depuis le
-- client, private est exclu de l'exposition PostgREST (db_schema =
-- "public,graphql_public", vérifié en Phase 1).
--
-- Scopée par jeton, pas par email en paramètre : l'appelant ne choisit
-- jamais quel email interroger — seul l'email déjà lié à un jeton
-- d'invitation valide qu'il détient est révélé. Empêche toute énumération
-- libre : sans jeton valide, aucune information. Même granularité de
-- validation que private.handle_new_user() (Module 12e) : token_hash
-- correspond, status='en_attente', expires_at > now(). Jeton invalide ->
-- false (pas d'exception) : la distinction fine (inexistant/expiré/
-- utilisé) est déjà faite par get_tenant_invitation_preview en amont dans
-- le parcours écran, pas la responsabilité de cette fonction.
--
-- Vérifie tenant_accounts.email, pas auth.users.email : répond
-- précisément à "cette personne est-elle déjà locataire quelque part ?",
-- pas à "cet email existe-t-il dans Auth pour n'importe quel type de
-- compte ?". Évite un cas limite sinon réel : un email déjà utilisé par
-- un compte STAFF (profiles) sans tenant_accounts ferait échouer
-- accept_tenant_invitation_existing_account (Module 12h) sur une
-- violation de clé étrangère brute plutôt qu'un message propre -- en
-- vérifiant tenant_accounts ici, ce cas reste simplement non détecté (le
-- formulaire de création s'affiche, et heurte le même silencieux échec
-- GoTrue déjà connu), pas une nouvelle erreur brute en plus.
-- ============================================================================

create or replace function public.check_tenant_invitation_existing_account(p_token text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select ti.email into v_email
  from public.tenant_invitations ti
  where ti.token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    and ti.status = 'en_attente'
    and ti.expires_at > now();

  if not found then
    return false;
  end if;

  return exists (
    select 1 from public.tenant_accounts where lower(email) = lower(v_email)
  );
end;
$$;

grant execute on function public.check_tenant_invitation_existing_account(text) to anon, authenticated;
