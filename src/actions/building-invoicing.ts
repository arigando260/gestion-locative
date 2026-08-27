"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { getBuildingInvoicingSummary } from "@/data/building-invoicing";
import { generateScheduleInvoiceForLease } from "./schedule-invoices";

export type BuildingInvoicingResult = {
  leaseId: string;
  propertyName: string;
  success: boolean;
  message?: string;
};

export type BuildingInvoicingActionState = {
  success: boolean;
  message?: string;
  results?: BuildingInvoicingResult[];
} | null;

// Boucle bail par bail sur le même cœur que le formulaire à un seul bail
// (generateScheduleInvoiceForLease, actions/schedule-invoices.tsx) --
// jamais un document fusionnant plusieurs locataires (une facture par bail,
// invoice_schedule_items reste 1 facture <-> N échéances d'un SEUL bail).
// Séquentiel, pas Promise.all : évite de concurrencer l'upload Storage et
// garde un rapport par bail lisible même en cas d'échec partiel.
async function generateInvoicesForLeases(
  leases: { leaseId: string; propertyName: string; scheduleIds: string[] }[],
  generatedBy: string
): Promise<BuildingInvoicingResult[]> {
  const results: BuildingInvoicingResult[] = [];
  for (const lease of leases) {
    const outcome = await generateScheduleInvoiceForLease({
      leaseId: lease.leaseId,
      scheduleIds: lease.scheduleIds,
      generatedBy,
    });
    results.push({
      leaseId: lease.leaseId,
      propertyName: lease.propertyName,
      success: outcome.success,
      message: outcome.message,
    });
  }
  return results;
}

function summarizeResults(results: BuildingInvoicingResult[]): BuildingInvoicingActionState {
  const successCount = results.filter((r) => r.success).length;
  return {
    success: successCount === results.length,
    message: `${successCount}/${results.length} facture(s) générée(s).`,
    results,
  };
}

// Chemin automatique ("Générer les X factures") : la liste à facturer est
// RECALCULÉE ici, jamais transmise par le client -- pas de fenêtre entre
// l'affichage du résumé et le clic où une sélection périmée ou trafiquée
// pourrait être soumise (voir plan validé). Le coût (une requête de plus)
// est négligeable face à cette garantie.
export async function generateBuildingInvoicesAction(
  _prevState: BuildingInvoicingActionState,
  formData: FormData
): Promise<BuildingInvoicingActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const buildingId = String(formData.get("building_id") ?? "");
  const month = String(formData.get("month") ?? "");
  if (!buildingId || !month) {
    return { success: false, message: "Immeuble ou mois manquant." };
  }

  const summary = await getBuildingInvoicingSummary(buildingId, month);
  if (summary.toInvoice.length === 0) {
    return { success: false, message: "Aucun logement à facturer pour ce mois." };
  }

  const results = await generateInvoicesForLeases(
    summary.toInvoice.map((lease) => ({
      leaseId: lease.leaseId,
      propertyName: lease.propertyName,
      scheduleIds: lease.schedules.map((s) => s.id),
    })),
    profile.id
  );

  revalidatePath(`/buildings/${buildingId}`);
  return summarizeResults(results);
}

// Chemin personnalisé : la sélection VIENT du client (l'utilisateur a
// délibérément décoché certaines échéances), mais generateScheduleInvoiceForLease
// revérifie déjà, pour chaque bail, que chaque schedule_id lui appartient
// réellement (getInvoiceGenerationContext) -- même protection qu'un envoi
// trafiqué du formulaire à un seul bail existant, rien à dupliquer ici.
export async function generateCustomBuildingInvoicesAction(
  _prevState: BuildingInvoicingActionState,
  formData: FormData
): Promise<BuildingInvoicingActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const buildingId = String(formData.get("building_id") ?? "");
  const selectionsRaw = String(formData.get("selections") ?? "[]");

  let selections: { leaseId: string; propertyName: string; scheduleIds: string[] }[];
  try {
    selections = JSON.parse(selectionsRaw);
  } catch {
    return { success: false, message: "Sélection invalide." };
  }

  const withSchedules = selections.filter(
    (s) => Array.isArray(s.scheduleIds) && s.scheduleIds.length > 0
  );
  if (withSchedules.length === 0) {
    return { success: false, message: "Sélectionnez au moins une échéance." };
  }

  const results = await generateInvoicesForLeases(withSchedules, profile.id);

  revalidatePath(`/buildings/${buildingId}`);
  return summarizeResults(results);
}
