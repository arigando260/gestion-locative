"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createLease } from "@/data/leases";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import type { ActionState } from "./properties";

export async function createLeaseAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const property_id = String(formData.get("property_id") ?? "");
  const tenant_account_id = String(formData.get("tenant_account_id") ?? "");
  const start_date = String(formData.get("start_date") ?? "");
  const endDateRaw = String(formData.get("end_date") ?? "").trim();
  const rent_amount = Number(formData.get("rent_amount"));
  const payment_frequency = String(formData.get("payment_frequency") ?? "");
  const payment_timing = String(formData.get("payment_timing") ?? "");
  const security_deposit_amount = Number(
    formData.get("security_deposit_amount")
  );
  const utilityDepositRaw = String(
    formData.get("utility_deposit_amount") ?? ""
  ).trim();
  const billingDayRaw = String(formData.get("billing_day") ?? "").trim();

  if (
    !property_id ||
    !tenant_account_id ||
    !start_date ||
    !payment_frequency ||
    !payment_timing ||
    Number.isNaN(rent_amount) ||
    Number.isNaN(security_deposit_amount)
  ) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createLease({
    organization_id: profile.organization_id,
    property_id,
    tenant_account_id,
    start_date,
    end_date: endDateRaw || null,
    rent_amount,
    payment_frequency,
    payment_timing,
    security_deposit_amount,
    utility_deposit_amount: utilityDepositRaw ? Number(utilityDepositRaw) : null,
    billing_day: billingDayRaw ? Number(billingDayRaw) : null,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/properties/${property_id}`);
  redirect({
    href: `/leases/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}
