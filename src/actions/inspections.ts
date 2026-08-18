"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  createInspection,
  addInspectionItem,
  updateInspectionItem,
  deleteInspectionItem,
  addInspectionPhotoRecord,
  deleteInspectionPhoto,
  finalizeInspection,
  updateInspectionObservations,
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

export async function updateInspectionItemAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const item_id = String(formData.get("item_id") ?? "");
  const inspection_id = String(formData.get("inspection_id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "");
  const zone = String(formData.get("zone") ?? "").trim();
  const condition = String(formData.get("condition") ?? "");
  const description = String(formData.get("description") ?? "").trim() || null;
  const costRaw = String(formData.get("estimated_repair_cost") ?? "").trim();

  if (!item_id || !inspection_id || !zone || !condition) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await updateInspectionItem(item_id, {
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
  return { success: true, message: t("itemUpdated") };
}

export type ConfirmPhotoUploadResult = {
  success: boolean;
  message?: string;
};

// Appelée directement (pas via <form action=...>), même patron que
// deleteMaintenanceTicketPhotoAction (Module 7b). inspection_photos_item_org_fk
// est ON DELETE RESTRICT : supprimer un item qui a encore des photos échoue —
// il faut supprimer ses photos d'abord (voir deleteInspectionItem). Ce cas
// précis (23503 sur CETTE contrainte) a un message dédié, plus actionnable
// que le message générique "violation de contrainte" de toUserMessage —
// même principe que lib/errors.ts (code connu -> message dédié), mais
// scopé ici : la contrainte n'a de sens que pour cette action-ci, pas pour
// toutes les violations 23503 de l'app.
export async function deleteInspectionItemAction(input: {
  id: string;
  inspection_id: string;
  lease_id: string;
}): Promise<ConfirmPhotoUploadResult> {
  const { error } = await deleteInspectionItem(input.id);

  if (error) {
    const t = await getTranslations("inspections");
    if (error.code === "23503" && error.message?.includes("inspection_photos_item_org_fk")) {
      return { success: false, message: t("deleteItemHasPhotos") };
    }
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${input.lease_id}/inspections/${input.inspection_id}`);
  return { success: true };
}

// Appelée directement (pas via <form action=...>), même patron que
// deleteMaintenanceTicketPhotoAction (Module 7b).
export async function deleteInspectionPhotoAction(input: {
  id: string;
  storage_path: string;
  inspection_id: string;
  lease_id: string;
}): Promise<ConfirmPhotoUploadResult> {
  const { error } = await deleteInspectionPhoto(input.id, input.storage_path);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${input.lease_id}/inspections/${input.inspection_id}`);
  return { success: true };
}

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

// Seul point de saisie des observations (Module 6g) : la création
// (InspectionForm) n'expose plus ce champ — il n'a pas sa place avant que
// le staff ait commencé à constater. Colonne NULL à l'insertion, remplie
// ici depuis la page de détail/édition du brouillon. La colonne redevient
// immuable une fois finalisé (private.prevent_finalized_inspection_change,
// Module 6, observations y figure déjà) — cette action échouera donc
// naturellement si appelée après finalisation, sans logique dupliquée ici.
export async function updateInspectionObservationsAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "");
  const observations = String(formData.get("observations") ?? "").trim() || null;

  if (!id || !lease_id) {
    return { success: false, message: "État des lieux introuvable." };
  }

  const { error } = await updateInspectionObservations(id, observations);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${lease_id}/inspections/${id}`);
  const t = await getTranslations("inspections");
  return { success: true, message: t("observationsUpdated") };
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
