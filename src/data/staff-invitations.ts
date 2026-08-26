import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 12m (staff_invitations, get_staff_invitation_preview
// absentes du fichier généré). À remplacer par Tables<"staff_invitations">
// etc. dès que `supabase gen types` est rejoué -- même remarque que
// data/tenant-invitations.ts.
export type StaffRoleCode = "admin" | "agent" | "comptable";

export type StaffInvitationStatus =
  | "en_attente"
  | "acceptee"
  | "expiree"
  | "revoquee";

export type StaffInvitation = {
  id: string;
  organization_id: string;
  email: string;
  role_code: StaffRoleCode;
  status: StaffInvitationStatus;
  invited_by: string;
  accepted_by: string | null;
  expires_at: string;
  created_at: string;
  accepted_at: string | null;
};

export type StaffInvitationPreview = {
  organization_name: string;
  email: string;
  role_code: StaffRoleCode;
  status: StaffInvitationStatus;
  expires_at: string;
} | null;

// Appelable sans session (get_staff_invitation_preview est SECURITY
// DEFINER, accordée à anon) : /staff-invite/accept l'utilise avant que
// l'invité n'ait de compte -- même principe que
// data/tenant-invitations.ts getTenantInvitationPreview.
export async function getStaffInvitationPreview(
  token: string
): Promise<StaffInvitationPreview> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("get_staff_invitation_preview", { p_token: token })
    .maybeSingle();

  if (error) throw error;
  return data as StaffInvitationPreview;
}

export async function getStaffInvitations(
  organizationId: string
): Promise<StaffInvitation[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("staff_invitations")
    .select("*")
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data as StaffInvitation[];
}

export type OrgStaffMember = {
  id: string;
  email: string;
  full_name: string | null;
  role_code: StaffRoleCode | null;
};

// user_roles est many-to-many (schéma) mais chaque compte n'a en pratique
// qu'un seul rôle aujourd'hui (aucun écran ne permet d'en cumuler) -- ne
// prend que le premier renvoyé, cohérent avec ce que l'écran peut afficher
// sans ambiguïté.
export async function getOrgStaff(
  organizationId: string
): Promise<OrgStaffMember[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("profiles")
    .select("id, email, full_name, user_roles(roles(code))")
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: true });

  if (error) throw error;
  return (data ?? []).map((row) => {
    const userRoles = row.user_roles as unknown as
      | { roles: { code: StaffRoleCode } | null }[]
      | null;
    return {
      id: row.id,
      email: row.email,
      full_name: row.full_name,
      role_code: userRoles?.[0]?.roles?.code ?? null,
    };
  });
}

// Écriture : {data, error} renvoyé tel quel, jamais throw -- la Server
// Action appelante décide comment le traduire, même convention que
// data/tenant-invitations.ts insertTenantInvitation.
export async function insertStaffInvitation(input: {
  organization_id: string;
  email: string;
  role_code: StaffRoleCode;
  token_hash: string;
  invited_by: string;
  expires_at: string;
}) {
  const supabase = await createClient();
  return supabase.from("staff_invitations").insert(input).select().single();
}
