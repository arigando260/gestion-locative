"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  insertPropertyAgentAssignment,
  deletePropertyAgentAssignment,
} from "@/data/property-agent-assignments";
import { toUserMessage } from "@/lib/errors";
import type { ActionState } from "./properties";

export async function assignAgentToPropertyAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant) --
  // la vraie garantie reste la policy RLS property_agent_assignments_insert
  // (has_permission('property_agent_assignments','create')), pas cette
  // vérification côté écran.
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const propertyId = String(formData.get("property_id") ?? "");
  const agentId = String(formData.get("agent_id") ?? "");
  if (!propertyId || !agentId) {
    return { success: false, message: "Agent requis." };
  }

  const { error } = await insertPropertyAgentAssignment({
    organization_id: profile.organization_id,
    property_id: propertyId,
    agent_id: agentId,
    assigned_by: profile.id,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/properties/${propertyId}`);
  return { success: true };
}

export async function unassignAgentFromPropertyAction(
  assignmentId: string,
  propertyId: string
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const { error } = await deletePropertyAgentAssignment(assignmentId);
  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/properties/${propertyId}`);
  return { success: true };
}
