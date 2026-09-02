import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 12d (tenant_invitations, get_tenant_invitation_preview
// absentes du fichier généré). À remplacer par Tables<"tenant_invitations">
// etc. dès que `supabase gen types` est rejoué.
export type TenantInvitationStatus =
  | "en_attente"
  | "acceptee"
  | "expiree"
  | "revoquee";

export type TenantInvitation = {
  id: string;
  organization_id: string;
  email: string;
  status: TenantInvitationStatus;
  invited_by: string;
  accepted_by: string | null;
  expires_at: string;
  created_at: string;
  accepted_at: string | null;
};

export type InvitationPreview = {
  organization_name: string;
  email: string;
  status: TenantInvitationStatus;
  expires_at: string;
} | null;

// Appelable sans session (get_tenant_invitation_preview est
// SECURITY DEFINER, accordée à anon) : /invite/accept l'utilise avant que
// l'invité n'ait de compte.
export async function getTenantInvitationPreview(
  token: string
): Promise<InvitationPreview> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("get_tenant_invitation_preview", { p_token: token })
    .maybeSingle();

  if (error) throw error;
  return data as InvitationPreview;
}

export async function getTenantInvitations(
  organizationId: string
): Promise<TenantInvitation[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tenant_invitations")
    .select("*")
    .eq("organization_id", organizationId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data as TenantInvitation[];
}

export type OrgTenant = {
  tenant_account_id: string;
  status: "actif" | "inactif";
  email: string;
  full_name: string | null;
};

export async function getOrgTenants(
  organizationId: string
): Promise<OrgTenant[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("tenant_organization_memberships")
    .select("tenant_account_id, status, tenant_accounts(email, full_name)")
    .eq("organization_id", organizationId);

  if (error) throw error;
  return (data ?? []).map((row) => {
    const tenant = row.tenant_accounts as unknown as {
      email: string;
      full_name: string | null;
    } | null;
    return {
      tenant_account_id: row.tenant_account_id,
      status: row.status,
      email: tenant?.email ?? "",
      full_name: tenant?.full_name ?? null,
    };
  });
}

// COUNT pur, sans l'embed tenant_accounts -- source pour le libellé de nav
// "Mon locataire"/"Mes locataires" (layout.tsx, Espace propriétaire). Même
// table que getOrgTenants ci-dessus (tenant_organization_memberships), pour
// rester cohérent avec ce que /tenants affiche déjà.
export async function getOrgTenantsCount(organizationId: string): Promise<number> {
  const supabase = await createClient();
  const { count, error } = await supabase
    .from("tenant_organization_memberships")
    .select("tenant_account_id", { count: "exact", head: true })
    .eq("organization_id", organizationId);

  if (error) throw error;
  return count ?? 0;
}

// Écriture : {data, error} renvoyé tel quel, jamais throw — la Server
// Action appelante décide comment le traduire, même convention que
// data/properties.ts createProperty.
export async function insertTenantInvitation(input: {
  organization_id: string;
  email: string;
  token_hash: string;
  invited_by: string;
  expires_at: string;
}) {
  const supabase = await createClient();
  return supabase.from("tenant_invitations").insert(input).select().single();
}

// Module 12h : rattachement direct d'un locataire déjà existant (compte
// créé via une première organisation) à une nouvelle organisation, sans
// jamais repasser par signUp(). SECURITY DEFINER côté base -- revalide
// tout elle-même (jeton, verrou, email de l'appelant) ; cette fonction ne
// fait que relayer l'appel .rpc(), même convention {data,error} que
// insertTenantInvitation.
export async function acceptTenantInvitationExistingAccount(token: string) {
  const supabase = await createClient();
  return supabase.rpc("accept_tenant_invitation_existing_account", {
    p_token: token,
  });
}
