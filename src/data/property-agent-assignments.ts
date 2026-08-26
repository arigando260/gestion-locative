import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 12o (property_agent_assignments absente du fichier
// généré) -- même remarque que data/staff-invitations.ts.
export type PropertyAgentAssignment = {
  id: string;
  agent_id: string;
  full_name: string | null;
  email: string;
  assigned_at: string;
};

export async function getPropertyAgentAssignments(
  propertyId: string
): Promise<PropertyAgentAssignment[]> {
  const supabase = await createClient();
  // property_agent_assignments a deux FK vers profiles (agent_id ET
  // assigned_by) -- l'embed implicite profiles(...) est ambigu pour
  // PostgREST (PGRST201, vérifié empiriquement), le nom de la contrainte
  // désambiguïse.
  const { data, error } = await supabase
    .from("property_agent_assignments")
    .select("id, agent_id, assigned_at, profiles!property_agent_assignments_agent_org_fk(full_name, email)")
    .eq("property_id", propertyId)
    .order("assigned_at", { ascending: true });

  if (error) throw error;
  return (data ?? []).map((row) => {
    const profile = row.profiles as unknown as { full_name: string | null; email: string } | null;
    return {
      id: row.id,
      agent_id: row.agent_id,
      full_name: profile?.full_name ?? null,
      email: profile?.email ?? "",
      assigned_at: row.assigned_at,
    };
  });
}

export type AvailableAgent = {
  id: string;
  full_name: string | null;
  email: string;
};

// Agents de l'organisation qui ont le rôle "agent" et ne sont PAS déjà
// assignés à ce bien -- exclusion faite ici plutôt que laissée à l'écran,
// pour que le select du formulaire ne propose jamais un doublon.
export async function getAvailableAgentsForAssignment(
  organizationId: string,
  propertyId: string
): Promise<AvailableAgent[]> {
  const supabase = await createClient();

  const { data: assigned, error: assignedError } = await supabase
    .from("property_agent_assignments")
    .select("agent_id")
    .eq("property_id", propertyId);
  if (assignedError) throw assignedError;
  const assignedIds = new Set((assigned ?? []).map((row) => row.agent_id));

  const { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, email, user_roles(roles(code))")
    .eq("organization_id", organizationId);
  if (error) throw error;

  return (data ?? [])
    .filter((row) => {
      const userRoles = row.user_roles as unknown as
        | { roles: { code: string } | null }[]
        | null;
      const roleCode = userRoles?.[0]?.roles?.code ?? null;
      return roleCode === "agent" && !assignedIds.has(row.id);
    })
    .map((row) => ({ id: row.id, full_name: row.full_name, email: row.email }));
}

// Écriture : {data, error} renvoyé tel quel, jamais throw -- la Server
// Action appelante décide comment le traduire, même convention que
// data/tenant-invitations.ts.
export async function insertPropertyAgentAssignment(input: {
  organization_id: string;
  property_id: string;
  agent_id: string;
  assigned_by: string;
}) {
  const supabase = await createClient();
  return supabase.from("property_agent_assignments").insert(input).select().single();
}

export async function deletePropertyAgentAssignment(id: string) {
  const supabase = await createClient();
  return supabase.from("property_agent_assignments").delete().eq("id", id);
}
