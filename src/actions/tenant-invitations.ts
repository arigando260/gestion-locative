"use server";

import { randomBytes, createHash } from "node:crypto";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  insertTenantInvitation,
  acceptTenantInvitationExistingAccount,
} from "@/data/tenant-invitations";
import { createClient } from "@/lib/supabase/server";
import { toUserMessage } from "@/lib/errors";

// Durée d'expiration : constante applicative, pas une colonne configurable
// (décision actée en conception, Module 12 -- contrairement à
// subscription_plans.trial_days, ce n'est pas une décision métier chiffrée,
// juste un paramètre d'implémentation).
const INVITATION_VALIDITY_DAYS = 7;

export type InviteTenantActionState =
  | { success: true; inviteUrl: string }
  | { success: false; message: string }
  | null;

export async function inviteTenantAction(
  _prevState: InviteTenantActionState,
  formData: FormData
): Promise<InviteTenantActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant) --
  // même patron que actions/properties.ts.
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();
  if (!email) {
    return { success: false, message: "Email requis." };
  }

  // Jeton brut jamais stocké : seule son empreinte SHA-256 (hex) va en
  // base, format identique à extensions.digest(token,'sha256')::hex côté
  // trigger (Module 12e) -- une comparaison différente ne matcherait
  // jamais.
  const rawToken = randomBytes(32).toString("hex");
  const tokenHash = createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(
    Date.now() + INVITATION_VALIDITY_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();

  const { error } = await insertTenantInvitation({
    organization_id: profile.organization_id,
    email,
    token_hash: tokenHash,
    invited_by: profile.id,
    expires_at: expiresAt,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  const headerList = await headers();
  const host = headerList.get("host");
  const protocol = host?.startsWith("localhost") ? "http" : "https";
  const locale = String(formData.get("locale") ?? "fr");
  const inviteUrl = `${protocol}://${host}/${locale}/invite/accept?token=${rawToken}`;

  // Envoi d'email non câblé pour l'instant : Supabase ne propose aucune API
  // d'envoi générique pour un contenu personnalisé (son mailer par défaut
  // est réservé à ses propres flux Auth -- confirmation/invite/recovery/
  // magic link -- chacun avec son propre système de jeton, incompatible
  // avec tenant_invitations). En attendant Resend, le lien affiché à
  // l'écran (voir InviteTenantForm) est le mécanisme de remise réel.

  revalidatePath("/tenants");
  return { success: true, inviteUrl };
}

export type AcceptExistingAccountResult =
  | { success: true }
  | { success: false; message: string };

// Module 12h : rattachement d'un locataire déjà existant à une nouvelle
// organisation -- appelée soit directement (bouton "Rejoindre", déjà
// connecté avec le bon compte), soit depuis /login juste après une
// connexion réussie initiée par ce même parcours. Jamais signUp() ici.
export async function acceptTenantInvitationForExistingAccountAction(
  token: string
): Promise<AcceptExistingAccountResult> {
  // Vérification légère ici, purement pour un message rapide -- la vraie
  // autorité reste accept_tenant_invitation_existing_account() côté base
  // (SECURITY DEFINER), qui revalide tout elle-même indépendamment de ce
  // qui a pu être vérifié plus haut dans la requête (même discipline que
  // RLS : l'écran/l'action reflètent, la base fait autorité).
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const { error } = await acceptTenantInvitationExistingAccount(token);
  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/tenant");
  return { success: true };
}
