"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createReservation } from "@/data/reservations";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import type { ActionState } from "./properties";

// total_amount n'est calculé par aucun trigger côté base (Module 4,
// "structure uniquement") : calculé ici, jamais confié au client.
export async function createReservationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const property_id = String(formData.get("property_id") ?? "");
  const tenant_account_id = String(formData.get("tenant_account_id") ?? "");
  const check_in_date = String(formData.get("check_in_date") ?? "");
  const check_out_date = String(formData.get("check_out_date") ?? "");
  const nightly_rate = Number(formData.get("nightly_rate"));

  if (
    !property_id ||
    !tenant_account_id ||
    !check_in_date ||
    !check_out_date ||
    Number.isNaN(nightly_rate)
  ) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const nights = Math.round(
    (new Date(check_out_date).getTime() - new Date(check_in_date).getTime()) /
      (1000 * 60 * 60 * 24)
  );

  if (nights <= 0) {
    return {
      success: false,
      message: "La date de départ doit être postérieure à la date d'arrivée.",
    };
  }

  const { error } = await createReservation({
    organization_id: profile.organization_id,
    property_id,
    tenant_account_id,
    check_in_date,
    check_out_date,
    nightly_rate,
    total_amount: nights * nightly_rate,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/reservations");
  revalidatePath(`/properties/${property_id}`);

  redirect({
    href: "/reservations",
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}
