"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createLease, updateLeaseTenantCapture } from "@/data/leases";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { getTranslations } from "next-intl/server";
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

const TENANT_CAPTURE_VALUE: Record<string, boolean | null> = {
  inherit: null,
  true: true,
  false: false,
};

export async function updateLeaseTenantCaptureAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const raw = String(formData.get("tenant_capture_enabled") ?? "inherit");

  if (!lease_id || !(raw in TENANT_CAPTURE_VALUE)) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await updateLeaseTenantCapture(lease_id, TENANT_CAPTURE_VALUE[raw]);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}`);
  const t = await getTranslations("leases");
  return { success: true, message: t("tenantCaptureUpdated") };
}
