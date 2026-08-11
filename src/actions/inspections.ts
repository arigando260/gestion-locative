"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  createInspection,
  addInspectionItem,
  addInspectionPhotoRecord,
  finalizeInspection,
  submitTenantValidation,
  type TenantValidationStatus,
} from "@/data/inspections";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

export async function createInspectionAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const inspection_type = String(formData.get("inspection_type") ?? "");
  const inspection_date = String(formData.get("inspection_date") ?? "");

  if (!lease_id || !inspection_type || !inspection_date) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createInspection({
    organization_id: profile.organization_id,
    lease_id,
    inspection_type,
    inspection_date,
    conducted_by: profile.id,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/inspections`);
  redirect({
    href: `/leases/${lease_id}/inspections/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}

export async function addInspectionItemAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const inspection_id = String(formData.get("inspection_id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "");
  const zone = String(formData.get("zone") ?? "").trim();
  const condition = String(formData.get("condition") ?? "");
  const description = String(formData.get("description") ?? "").trim() || null;
  const costRaw = String(formData.get("estimated_repair_cost") ?? "").trim();

  if (!inspection_id || !zone || !condition) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await addInspectionItem({
    organization_id: profile.organization_id,
    inspection_id,
    zone,
    description,
    condition,
    estimated_repair_cost: costRaw ? Number(costRaw) : null,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/inspections/${inspection_id}`);
  const t = await getTranslations("inspections");
  return { success: true, message: t("itemAdded") };
}

export type ConfirmPhotoUploadResult = {
  success: boolean;
  message?: string;
};

// Appelée directement (pas via <form action=...>) juste après un envoi
// réussi vers le bucket depuis le navigateur — voir
// components/inspections/photo-upload-field.tsx. Ne re-déclenche jamais
// l'upload : uniquement l'écriture de la ligne inspection_photos.
export async function confirmInspectionPhotoUploadAction(input: {
  organization_id: string;
  inspection_item_id: string;
  inspection_id: string;
  lease_id: string;
  storage_path: string;
  file_hash: string;
}): Promise<ConfirmPhotoUploadResult> {
  const { error } = await addInspectionPhotoRecord({
    organization_id: input.organization_id,
    inspection_item_id: input.inspection_item_id,
    storage_path: input.storage_path,
    file_hash: input.file_hash,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${input.lease_id}/inspections/${input.inspection_id}`);
  return { success: true };
}

export async function finalizeInspectionAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "");
  if (!id || !lease_id) {
    return { success: false, message: "État des lieux introuvable." };
  }

  const { error } = await finalizeInspection(id);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/inspections/${id}`);
  const t = await getTranslations("inspections");
  return { success: true, message: t("finalizeSuccess") };
}

export async function submitTenantValidationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "");
  const status = String(formData.get("status") ?? "") as TenantValidationStatus;
  const comments = String(formData.get("comments") ?? "").trim() || null;

  if (!id || !lease_id || (status !== "valide" && status !== "conteste")) {
    return { success: false, message: "Merci de choisir une réponse." };
  }

  const { error } = await submitTenantValidation(id, status, comments);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/tenant/leases/${lease_id}/inspections/${id}`);
  const t = await getTranslations("inspections");
  return { success: true, message: t("validationSubmitted") };
}
