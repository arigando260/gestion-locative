"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { getMyLease } from "@/data/leases";
import {
  createMaintenanceTicket,
  createTenantMaintenanceTicket,
  updateMaintenanceTicketStatus,
  updateMaintenanceTicketCost,
  updateMaintenanceTicketDetails,
  addMaintenanceTicketPhotoRecord,
  deleteMaintenanceTicketPhoto,
  type MaintenanceTicketStatus,
  type MaintenanceTicketPriority,
} from "@/data/maintenance";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

const VALID_PRIORITIES: MaintenanceTicketPriority[] = [
  "basse",
  "normale",
  "haute",
  "urgente",
];

export async function createMaintenanceTicketAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const property_id = String(formData.get("property_id") ?? "");
  const lease_id = String(formData.get("lease_id") ?? "").trim() || null;
  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const priority = String(formData.get("priority") ?? "normale") as MaintenanceTicketPriority;

  if (!property_id || !title || !VALID_PRIORITIES.includes(priority)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createMaintenanceTicket({
    organization_id: profile.organization_id,
    property_id,
    lease_id,
    reported_by_staff_id: profile.id,
    title,
    description,
    priority,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/maintenance");
  redirect({
    href: `/maintenance/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}

// Le bien/l'organisation ne sont jamais pris tels quels dans le FormData :
// dérivés côté serveur à partir du bail choisi (getMyLease, RLS-scopé), pour
// ne jamais dépendre de champs cachés qu'un client pourrait faire diverger
// de son bail réel. Le trigger validate_maintenance_ticket_tenant_lease
// (Module 7) rejetterait de toute façon une incohérence, mais autant ne pas
// dépendre uniquement de ce filet côté écriture.
export async function createTenantMaintenanceTicketAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const tenant = await getCurrentTenant();
  if (!tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  if (!lease_id || !title) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const lease = await getMyLease(lease_id);
  if (!lease || lease.status !== "actif") {
    return { success: false, message: "Bail introuvable ou inactif." };
  }

  const { data, error } = await createTenantMaintenanceTicket({
    organization_id: lease.organization_id,
    property_id: lease.property_id,
    lease_id: lease.id,
    reported_by_tenant_id: tenant.id,
    title,
    description,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/tenant/maintenance");
  redirect({
    href: `/tenant/maintenance/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}

// Restreint par la base (RLS + restrict_tenant_maintenance_ticket_update_fields,
// Module 7) à titre/description, et seulement tant que status = 'signale' —
// ticket-tenant-edit-form.tsx ne rend même pas ce formulaire au-delà, mais
// l'action reste rejouable telle quelle si un ticket a changé de statut
// entre l'affichage et la soumission : la base tranche, message P0001 inchangé.
export async function updateTenantMaintenanceTicketAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const tenant = await getCurrentTenant();
  if (!tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const id = String(formData.get("id") ?? "");
  const title = String(formData.get("title") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;

  if (!id || !title) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { error } = await updateMaintenanceTicketDetails(id, { title, description });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/tenant/maintenance/${id}`);
  const t = await getTranslations("maintenance");
  return { success: true, message: t("ticketUpdated") };
}

export async function updateMaintenanceTicketStatusAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  const status = String(formData.get("status") ?? "") as MaintenanceTicketStatus;

  if (!id || !status) {
    return { success: false, message: "Ticket introuvable." };
  }

  const { error } = await updateMaintenanceTicketStatus(id, status);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/maintenance/${id}`);
  revalidatePath("/maintenance");
  const t = await getTranslations("maintenance");
  return { success: true, message: t("statusUpdated") };
}

export async function updateMaintenanceTicketCostAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  if (!id) {
    return { success: false, message: "Ticket introuvable." };
  }

  const estimatedRaw = String(formData.get("estimated_cost") ?? "").trim();
  const actualRaw = String(formData.get("actual_cost") ?? "").trim();

  // Le gel post-imputation est vérifié côté écran (ticket-cost-fields.tsx)
  // pour désactiver les champs en amont — cet appel reste tout de même
  // possible (course concurrente) et la base tranche en dernier ressort,
  // voir data/maintenance.ts.
  const { error } = await updateMaintenanceTicketCost(id, {
    estimated_cost: estimatedRaw ? Number(estimatedRaw) : null,
    actual_cost: actualRaw ? Number(actualRaw) : null,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/maintenance/${id}`);
  const t = await getTranslations("maintenance");
  return { success: true, message: t("costsUpdated") };
}

export type ConfirmPhotoUploadResult = { success: boolean; message?: string };

// Partagées staff/locataire (ticket-photo-gallery.tsx est réutilisé tel
// quel des deux côtés) : les deux chemins de détail sont revalidés, l'appelant
// n'étant jamais forcément le staff — RLS/les triggers du Module 7b décident
// seuls de ce qui est réellement permis, cette action ne fait qu'écrire.

// Appelée directement (pas via <form action=...>) juste après un envoi
// réussi vers le bucket depuis le navigateur — même principe que
// confirmInspectionPhotoUploadAction. Ne re-déclenche jamais l'upload :
// uniquement l'écriture de la ligne maintenance_ticket_photos.
export async function confirmMaintenanceTicketPhotoUploadAction(input: {
  organization_id: string;
  maintenance_ticket_id: string;
  storage_path: string;
  file_hash: string;
}): Promise<ConfirmPhotoUploadResult> {
  const { error } = await addMaintenanceTicketPhotoRecord(input);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/maintenance/${input.maintenance_ticket_id}`);
  revalidatePath(`/tenant/maintenance/${input.maintenance_ticket_id}`);
  return { success: true };
}

export async function deleteMaintenanceTicketPhotoAction(input: {
  id: string;
  storage_path: string;
  maintenance_ticket_id: string;
}): Promise<ConfirmPhotoUploadResult> {
  const { error } = await deleteMaintenanceTicketPhoto(input.id, input.storage_path);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/maintenance/${input.maintenance_ticket_id}`);
  revalidatePath(`/tenant/maintenance/${input.maintenance_ticket_id}`);
  return { success: true };
}
