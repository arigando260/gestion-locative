"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  recordInitialDeposit,
  recordImputation,
  recordRefund,
  setAdvanceConsumptionAuthorized,
  type DepositType,
  type ImputationCategory,
} from "@/data/deposits";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

// Une catégorie d'imputation détermine sans ambiguïté le type de caution
// concerné (contrainte deposit_ledger_category_matches_deposit_type,
// Module 6) : pas besoin de le demander séparément dans le formulaire.
const DEPOSIT_TYPE_FOR_CATEGORY: Record<ImputationCategory, DepositType> = {
  loyer: "avance_garantie",
  degats: "avance_garantie",
  impayes_utilities: "caution_utilities",
};

export async function recordInitialDepositAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const deposit_type = String(formData.get("deposit_type") ?? "") as DepositType;
  const amount = Number(formData.get("amount"));

  if (!lease_id || !deposit_type || Number.isNaN(amount)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await recordInitialDeposit({
    organization_id: profile.organization_id,
    lease_id,
    deposit_type,
    amount,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/deposits`);
  const t = await getTranslations("deposits");
  return { success: true, message: t("depositRecorded") };
}

export async function recordImputationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const imputation_category = String(
    formData.get("imputation_category") ?? ""
  ) as ImputationCategory;
  const amount = Number(formData.get("amount"));
  const reason = String(formData.get("reason") ?? "").trim();
  const payment_schedule_id =
    String(formData.get("payment_schedule_id") ?? "").trim() || null;

  if (!lease_id || !imputation_category || !reason || Number.isNaN(amount)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await recordImputation({
    organization_id: profile.organization_id,
    lease_id,
    deposit_type: DEPOSIT_TYPE_FOR_CATEGORY[imputation_category],
    imputation_category,
    amount,
    reason,
    payment_schedule_id: imputation_category === "loyer" ? payment_schedule_id : null,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/deposits`);
  const t = await getTranslations("deposits");
  return { success: true, message: t("imputationRecorded") };
}

export async function recordRefundAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const deposit_type = String(formData.get("deposit_type") ?? "") as DepositType;
  const amount = Number(formData.get("amount"));
  const reason = String(formData.get("reason") ?? "").trim() || null;

  if (!lease_id || !deposit_type || Number.isNaN(amount)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await recordRefund({
    organization_id: profile.organization_id,
    lease_id,
    deposit_type,
    amount,
    reason,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/deposits`);
  const t = await getTranslations("deposits");
  return { success: true, message: t("refundRecorded") };
}

export async function toggleAdvanceAuthorizationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const authorized = String(formData.get("authorized") ?? "") === "true";
  if (!lease_id) {
    return { success: false, message: "Bail introuvable." };
  }

  const { error } = await setAdvanceConsumptionAuthorized(
    lease_id,
    authorized,
    profile.id
  );

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/deposits`);
  const t = await getTranslations("deposits");
  return { success: true, message: t("authorizationUpdated") };
}
