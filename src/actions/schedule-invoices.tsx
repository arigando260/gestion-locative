"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import {
  getInvoiceGenerationContext,
  createScheduleInvoiceRecord,
  addScheduleInvoiceLineItems,
  getSignedScheduleInvoiceUrl,
} from "@/data/schedule-invoices";
import { createClient } from "@/lib/supabase/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { InvoiceDocument } from "@/lib/pdf/invoice-document";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";
import type { DocumentUrlResult } from "./payment-receipts";

// Cœur partagé, extrait de generateScheduleInvoiceAction (module facturation
// groupée par immeuble) : aucune logique changée, seulement sortie de la
// lecture de FormData/ActionState pour être appelable aussi bien par le
// formulaire à un seul bail (ci-dessous) que par la génération groupée
// (actions/building-invoicing.ts), bail par bail, sans dupliquer le rendu
// PDF/upload/écriture des 2 tables. Toujours synchrone (rendu + upload +
// écriture des 2 tables en un seul appel) — geste toujours délibéré du
// staff, jamais de trigger côté base (voir conception Module 9).
export async function generateScheduleInvoiceForLease(input: {
  leaseId: string;
  scheduleIds: string[];
  generatedBy: string;
}): Promise<{ success: boolean; message?: string; invoiceId?: string }> {
  const { leaseId, scheduleIds, generatedBy } = input;

  if (scheduleIds.length === 0) {
    return { success: false, message: "Sélectionnez au moins une échéance." };
  }

  const context = await getInvoiceGenerationContext(leaseId, scheduleIds);
  if (!context) {
    return {
      success: false,
      message: "Sélection invalide : une échéance ne correspond pas à ce bail.",
    };
  }

  // Généré AVANT le rendu : le chemin de stockage doit connaître l'id de la
  // facture (voir data/schedule-invoices.ts createScheduleInvoiceRecord).
  const invoiceId = randomUUID();
  const totalAmount = context.lineItems.reduce((sum, item) => sum + item.amountDue, 0);

  const buffer = await renderToBuffer(
    <InvoiceDocument
      data={{
        organization: context.organization,
        tenantName: context.tenantName,
        propertyLabel: context.propertyLabel,
        invoiceReference: invoiceId,
        issuedDate: new Date().toISOString().slice(0, 10),
        lineItems: context.lineItems.map((item) => ({
          id: item.id,
          periodLabel: `${item.periodStart} → ${item.periodEnd}`,
          dueDate: item.dueDate,
          amount: String(item.amountDue),
        })),
        totalAmount: String(totalAmount),
      }}
    />
  );

  const storagePath = `${context.organizationId}/${invoiceId}/${randomUUID()}.pdf`;
  const supabase = await createClient();
  const { error: uploadError } = await supabase.storage
    .from("schedule-invoices")
    .upload(storagePath, buffer, { contentType: "application/pdf" });

  // Erreur Storage, pas Postgrest : voir même remarque dans
  // actions/payment-receipts.tsx.
  if (uploadError) {
    return { success: false, message: "Échec de la génération de la facture. Réessayez." };
  }

  const { error: insertError } = await createScheduleInvoiceRecord({
    id: invoiceId,
    organization_id: context.organizationId,
    lease_id: leaseId,
    storage_path: storagePath,
    generated_by: generatedBy,
  });

  if (insertError) {
    return { success: false, message: await toUserMessage(insertError) };
  }

  const { error: itemsError } = await addScheduleInvoiceLineItems(
    context.organizationId,
    invoiceId,
    scheduleIds
  );

  if (itemsError) {
    return { success: false, message: await toUserMessage(itemsError) };
  }

  revalidatePath(`/leases/${leaseId}`);
  revalidatePath(`/tenant/leases/${leaseId}`);
  const t = await getTranslations("billing");
  return { success: true, message: t("invoiceGenerated"), invoiceId };
}

// Wrapper FormData/ActionState pour le formulaire à un seul bail
// (components/billing/invoice-generate-form.tsx) — comportement et
// signature strictement inchangés par l'extraction ci-dessus : mêmes
// validations, mêmes messages, même ordre.
export async function generateScheduleInvoiceAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const lease_id = String(formData.get("lease_id") ?? "");
  const scheduleIds = formData.getAll("schedule_ids").map(String);

  if (!lease_id || scheduleIds.length === 0) {
    return { success: false, message: "Sélectionnez au moins une échéance." };
  }

  const result = await generateScheduleInvoiceForLease({
    leaseId: lease_id,
    scheduleIds,
    generatedBy: profile.id,
  });

  return { success: result.success, message: result.message };
}

// Partagée staff/locataire : storage_path est toujours déjà connu de
// l'appelant (les deux variantes de InvoiceList, voir components/billing/invoice-list.tsx,
// le tiennent déjà de getScheduleInvoicesForLease — jamais de génération ici,
// schedule_invoices.storage_path n'est jamais null). createSignedUrl
// revérifie lui-même la policy Storage (schedule_invoices_storage_select,
// Module 9) pour l'identité de l'appelant, même principe que
// getSignedMaintenanceTicketPhotoUrls : accepter un chemin brut est sûr,
// l'autorisation réelle est tranchée à la signature, pas ici.
export async function getSignedScheduleInvoiceUrlAction(
  storagePath: string
): Promise<DocumentUrlResult> {
  try {
    const url = await getSignedScheduleInvoiceUrl(storagePath);
    return { success: true, url };
  } catch {
    return { success: false, message: "Impossible de générer le lien de téléchargement." };
  }
}
