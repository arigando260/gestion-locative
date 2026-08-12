"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { updateOrganization } from "@/data/organizations";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

// RLS (organizations_update, Module 1) reste seule autorité réelle : cette
// action ne fait que déléguer, la permission 'organizations'/'update' pilote
// uniquement l'affichage du formulaire côté écran.
export async function updateOrganizationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const name = String(formData.get("name") ?? "").trim();
  const address = String(formData.get("address") ?? "").trim() || null;
  const phone = String(formData.get("phone") ?? "").trim() || null;
  const email = String(formData.get("email") ?? "").trim() || null;
  // Case à cocher HTML : absente de FormData quand décochée, jamais "false".
  const tenant_capture_enabled = formData.get("tenant_capture_enabled") === "true";

  if (!name) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await updateOrganization(profile.organization_id, {
    name,
    address,
    phone,
    email,
    tenant_capture_enabled,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/settings");
  const t = await getTranslations("settings");
  return { success: true, message: t("updateSuccess") };
}
