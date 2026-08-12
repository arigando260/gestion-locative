"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { getMyLease } from "@/data/leases";
import {
  createLeaseTerminationRequest,
  respondToLeaseTerminationRequest,
  cancelLeaseTerminationRequest,
  type LeaseTerminationStatus,
} from "@/data/lease-terminations";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

export async function createStaffLeaseTerminationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const requested_end_date = String(formData.get("requested_end_date") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();

  if (!lease_id || !requested_end_date || !reason) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createLeaseTerminationRequest({
    organization_id: profile.organization_id,
    lease_id,
    initiated_by_tenant_id: null,
    initiated_by_staff_id: profile.id,
    requested_end_date,
    reason,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/lease-terminations");
  redirect({
    href: `/lease-terminations/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}

// Le bien/l'organisation ne sont jamais pris tels quels dans le FormData :
// dérivés côté serveur à partir du bail choisi (getMyLease, RLS-scopé), même
// principe que createTenantMaintenanceTicketAction. Le trigger
// validate_lease_termination_request_state (Module 8) revérifie de toute
// façon que le bail est actif, mais autant ne pas dépendre uniquement de ce
// filet côté écriture.
export async function createTenantLeaseTerminationAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const tenant = await getCurrentTenant();
  if (!tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const requested_end_date = String(formData.get("requested_end_date") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();

  if (!lease_id || !requested_end_date || !reason) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const lease = await getMyLease(lease_id);
  if (!lease || lease.status !== "actif") {
    return { success: false, message: "Bail introuvable ou inactif." };
  }

  const { data, error } = await createLeaseTerminationRequest({
    organization_id: lease.organization_id,
    lease_id: lease.id,
    initiated_by_tenant_id: tenant.id,
    initiated_by_staff_id: null,
    requested_end_date,
    reason,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/tenant/lease-terminations");
  redirect({
    href: `/tenant/lease-terminations/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  return null;
}

// Partagée staff/locataire : la légitimité de la réponse (qui n'a pas
// initié, avec la bonne identité/permission) est tranchée par RLS + le
// trigger validate_lease_termination_request_transition (Module 8), pas
// ici — les deux formulaires de réponse (staff et locataire) appellent
// cette même action, comme confirmMaintenanceTicketPhotoUploadAction est
// partagée entre les deux portails.
export async function respondLeaseTerminationRequestAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  const status = String(formData.get("status") ?? "") as LeaseTerminationStatus;
  const response_note = String(formData.get("response_note") ?? "").trim() || null;

  if (!id || (status !== "validee" && status !== "refusee")) {
    return { success: false, message: "Demande introuvable." };
  }

  const { error } = await respondToLeaseTerminationRequest(id, status, response_note);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/lease-terminations/${id}`);
  revalidatePath("/lease-terminations");
  revalidatePath(`/tenant/lease-terminations/${id}`);
  revalidatePath("/tenant/lease-terminations");
  const t = await getTranslations("leaseTerminations");
  return { success: true, message: t("responseRecorded") };
}

// Partagée staff/locataire, même raisonnement que ci-dessus : seul l'auteur
// (identité vérifiée par trigger) peut effectivement annuler.
export async function cancelLeaseTerminationRequestAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const id = String(formData.get("id") ?? "");
  if (!id) {
    return { success: false, message: "Demande introuvable." };
  }

  const { error } = await cancelLeaseTerminationRequest(id);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/lease-terminations/${id}`);
  revalidatePath("/lease-terminations");
  revalidatePath(`/tenant/lease-terminations/${id}`);
  revalidatePath("/tenant/lease-terminations");
  const t = await getTranslations("leaseTerminations");
  return { success: true, message: t("requestCancelled") };
}
