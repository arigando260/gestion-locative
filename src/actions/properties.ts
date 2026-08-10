"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createProperty } from "@/data/properties";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";

export type ActionState = { success: boolean; message?: string } | null;

export async function createPropertyAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant).
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const name = String(formData.get("name") ?? "").trim();
  const address = String(formData.get("address") ?? "").trim();
  const price = Number(formData.get("price"));
  const location_type = String(formData.get("location_type") ?? "");

  if (!name || !address || !location_type || Number.isNaN(price)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createProperty({
    organization_id: profile.organization_id,
    name,
    address,
    price,
    location_type,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/properties");
  redirect({
    href: `/properties/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  // redirect() lève toujours — inatteignable, seulement pour satisfaire le
  // contrôle de flux TypeScript (le type de retour de redirect() n'est pas
  // "never" dans cette version de next-intl).
  return null;
}
