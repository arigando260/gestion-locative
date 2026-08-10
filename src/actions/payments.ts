"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { recordPayment, type PaymentMethod } from "@/data/payments";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

export async function recordPaymentAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const payment_schedule_id = String(formData.get("payment_schedule_id") ?? "");
  const amount = Number(formData.get("amount"));
  const method = String(formData.get("method") ?? "") as PaymentMethod;
  const payment_date = String(formData.get("payment_date") ?? "");
  const external_reference =
    String(formData.get("external_reference") ?? "").trim() || null;

  if (!lease_id || !payment_schedule_id || !method || !payment_date || Number.isNaN(amount)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await recordPayment({
    organization_id: profile.organization_id,
    lease_id,
    payment_schedule_id,
    amount,
    method,
    payment_date,
    external_reference,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}`);

  const t = await getTranslations("payments");
  return { success: true, message: t("success") };
}
