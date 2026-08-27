"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createBuilding } from "@/data/buildings";
import { toUserMessage } from "@/lib/errors";
import type { ActionState } from "./properties";

export async function createBuildingAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant) --
  // la vraie garantie reste la policy RLS buildings_insert
  // (has_permission('buildings','create')), pas cette vérification côté écran.
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const name = String(formData.get("name") ?? "").trim();
  const country_code = String(formData.get("country_code") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const neighborhood = String(formData.get("neighborhood") ?? "").trim();
  const addressComplementRaw = String(formData.get("address_complement") ?? "").trim();
  const address_complement = addressComplementRaw === "" ? null : addressComplementRaw;
  const floorsCountRaw = String(formData.get("floors_count") ?? "").trim();
  const floors_count = floorsCountRaw === "" ? null : Number(floorsCountRaw);

  if (!name || !country_code || !city || !neighborhood || (floors_count !== null && Number.isNaN(floors_count))) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await createBuilding({
    organization_id: profile.organization_id,
    name,
    country_code,
    city,
    neighborhood,
    address_complement,
    floors_count,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/buildings");
  return { success: true };
}
