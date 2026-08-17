"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  createLease,
  updateLeaseTenantCapture,
  updateLeaseEndDate,
  recordKeysReturned,
  closeLeaseDefinitively,
  updateLeaseSpecialTerms,
  deleteLease,
} from "@/data/leases";
import { generateSchedulesForLease } from "@/data/schedules";
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

// Volet B (Module 10) — "renouveler" : end_date vide = durée indéterminée,
// même convention que createLeaseAction ci-dessus.
export async function updateLeaseEndDateAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const endDateRaw = String(formData.get("end_date") ?? "").trim();

  if (!lease_id) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await updateLeaseEndDate(lease_id, endDateRaw || null);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  // Complète immédiatement la couverture d'échéances jusqu'à la nouvelle
  // end_date — ne plus attendre le rendu suivant de la fiche bail (Module
  // 5c). Best-effort, même principe que l'extension silencieuse : la mise
  // à jour de end_date est déjà acquise à ce stade, un échec de génération
  // ne doit jamais l'invalider ni bloquer le message de succès.
  try {
    await generateSchedulesForLease(lease_id);
  } catch {
    // Best-effort, voir commentaire ci-dessus.
  }

  revalidatePath(`/leases/${lease_id}`);
  revalidatePath("/dashboard");
  const t = await getTranslations("leases");
  return { success: true, message: t("endDateUpdated") };
}

// Volet C (Module 10), étape 1 — restitution des clés.
export async function recordKeysReturnedAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const date = String(formData.get("keys_returned_at") ?? "").trim();

  if (!lease_id || !date) {
    return { success: false, message: "Merci de renseigner une date." };
  }

  const { error } = await recordKeysReturned(lease_id, date);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}`);
  revalidatePath("/dashboard");
  const t = await getTranslations("leases");
  return { success: true, message: t("keysReturnedRecorded") };
}

// Volet C (Module 10), étape finale — clôture définitive. Aucun champ à
// valider ici : le trigger de garde (Module 10) revérifie lui-même
// keys_returned_at + état des lieux de sortie finalisé et renvoie un
// message métier clair (P0001) si la condition n'est plus remplie entre
// l'affichage du bouton et le clic.
export async function closeLeaseDefinitivelyAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  if (!lease_id) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await closeLeaseDefinitively(lease_id);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}`);
  revalidatePath("/dashboard");
  const t = await getTranslations("leases");
  return { success: true, message: t("leaseClosed") };
}

// Clauses particulières (Module 10d) — override par bail, vide = retour à
// l'héritage du réglage organisation (résolu côté application, jamais ici).
export async function updateLeaseSpecialTermsAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const specialTermsRaw = String(formData.get("special_terms") ?? "").trim();

  if (!lease_id) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await updateLeaseSpecialTerms(lease_id, specialTermsRaw || null);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}`);
  const t = await getTranslations("leases");
  return { success: true, message: t("specialTermsUpdated") };
}

// Mécanisme de refus de contrat (Module 10) — visible uniquement pour un
// bail 'brouillon' (voir page). Le message d'erreur (dépôts déjà versés :
// lease.delete.has_deposit_history) remonte tel quel via toUserMessage,
// jamais un échec silencieux.
export async function deleteLeaseAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const property_id = String(formData.get("property_id") ?? "");

  if (!lease_id) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await deleteLease(lease_id);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/dashboard");
  if (property_id) revalidatePath(`/properties/${property_id}`);
  redirect({
    href: property_id ? `/properties/${property_id}` : "/dashboard",
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}
