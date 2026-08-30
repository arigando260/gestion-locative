import "server-only";
import { getLeaseActivationReadiness } from "@/data/lease-contracts";
import { getInspectionsForLease } from "@/data/inspections";
import { getSchedulesForLease } from "@/data/schedules";
import { getLeaseClosureStatus, isLeaseClosureEngaged } from "@/data/lease-closure";
import type { LeaseWithContext } from "@/data/leases";

export type TenantNextAction =
  | { kind: "signature_pending"; leaseId: string }
  | { kind: "entry_inspection_pending"; leaseId: string; inspectionId: string }
  | { kind: "closure_in_progress"; leaseId: string }
  | { kind: "payment_overdue"; leaseId: string; amount: number; dueDate: string }
  | { kind: "payment_upcoming"; leaseId: string; amount: number; dueDate: string }
  | { kind: "calm"; leaseId: string };

// "Prochain sujet" pour l'accueil locataire — dérivé uniquement de
// fonctions de données déjà existantes (aucune nouvelle table/RPC), un seul
// résultat par bail dans l'ordre de priorité métier : signature > état des
// lieux d'entrée à valider > clôture engagée > échéance > calme. Les
// sous-flux avancés de la maquette (état des lieux délégué pièce par
// pièce, timeline de restitution) ne sont pas couverts ici — hors scope de
// cette passe, voir le plan.
export async function getTenantNextAction(lease: LeaseWithContext): Promise<TenantNextAction> {
  if (lease.status === "brouillon") {
    const readiness = await getLeaseActivationReadiness(lease.id);
    if (readiness?.contract_id && !readiness.contract_approved_at) {
      return { kind: "signature_pending", leaseId: lease.id };
    }
    return { kind: "calm", leaseId: lease.id };
  }

  const [inspections, closure] = await Promise.all([
    getInspectionsForLease(lease.id),
    getLeaseClosureStatus(lease.id),
  ]);

  const pendingEntryInspection = inspections.find(
    (i) => i.inspection_type === "entree" && i.effective_validation_status === "en_attente"
  );
  if (pendingEntryInspection?.id) {
    return {
      kind: "entry_inspection_pending",
      leaseId: lease.id,
      inspectionId: pendingEntryInspection.id,
    };
  }

  if (closure && isLeaseClosureEngaged(closure)) {
    return { kind: "closure_in_progress", leaseId: lease.id };
  }

  const schedules = await getSchedulesForLease(lease.id);

  const overdue = schedules.find((s) => s.effective_status === "en_retard");
  if (overdue?.due_date && overdue.amount_due != null) {
    return {
      kind: "payment_overdue",
      leaseId: lease.id,
      amount: overdue.amount_due,
      dueDate: overdue.due_date,
    };
  }

  const upcoming = schedules
    .filter((s) => s.effective_status === "en_attente" && s.due_date)
    .sort((a, b) => (a.due_date! < b.due_date! ? -1 : 1))[0];
  if (upcoming?.due_date && upcoming.amount_due != null) {
    return {
      kind: "payment_upcoming",
      leaseId: lease.id,
      amount: upcoming.amount_due,
      dueDate: upcoming.due_date,
    };
  }

  return { kind: "calm", leaseId: lease.id };
}
