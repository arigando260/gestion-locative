"use server";

import { randomBytes, createHash } from "node:crypto";
import { headers } from "next/headers";
import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { insertStaffInvitation, type StaffRoleCode } from "@/data/staff-invitations";
import { toUserMessage } from "@/lib/errors";

// Même durée que tenant_invitations (Module 12), même raison : constante
// applicative, pas une colonne configurable.
const INVITATION_VALIDITY_DAYS = 7;

const STAFF_ROLE_CODES: StaffRoleCode[] = ["admin", "agent", "comptable"];

export type InviteStaffActionState =
  | { success: true; inviteUrl: string }
  | { success: false; message: string }
  | null;

export async function inviteStaffAction(
  _prevState: InviteStaffActionState,
  formData: FormData
): Promise<InviteStaffActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant) --
  // même patron que actions/tenant-invitations.ts. La vraie garantie reste
  // la policy RLS staff_invitations_insert (has_permission('users',
  // 'create')), pas cette vérification côté écran.
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();
  const roleCode = String(formData.get("role_code") ?? "");

  if (!email) {
    return { success: false, message: "Email requis." };
  }
  if (!STAFF_ROLE_CODES.includes(roleCode as StaffRoleCode)) {
    return { success: false, message: "Rôle invalide." };
  }

  // Jeton brut jamais stocké : seule son empreinte SHA-256 (hex) va en
  // base -- même schéma que tenant_invitations.
  const rawToken = randomBytes(32).toString("hex");
  const tokenHash = createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(
    Date.now() + INVITATION_VALIDITY_DAYS * 24 * 60 * 60 * 1000
  ).toISOString();

  const { error } = await insertStaffInvitation({
    organization_id: profile.organization_id,
    email,
    role_code: roleCode as StaffRoleCode,
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
  const inviteUrl = `${protocol}://${host}/${locale}/staff-invite/accept?token=${rawToken}`;

  // Envoi d'email non câblé pour l'instant, même limite que
  // tenant_invitations (voir actions/tenant-invitations.ts) : le lien
  // affiché à l'écran est le mécanisme de remise réel en attendant Resend.

  revalidatePath("/team");
  return { success: true, inviteUrl };
}
