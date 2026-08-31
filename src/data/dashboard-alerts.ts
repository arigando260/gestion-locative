import "server-only";
import { getLeasesWithLowScheduleCoverage, getLeasesWithOverduePayments } from "./schedules";
import {
  getLeasesWithUpcomingEndDate,
  getLeasesPendingClosure,
  getLeasesNeedingEntryInspection,
} from "./lease-closure";
import { getLeasesWithPendingDepositRefund } from "./deposits";
import { can, type PermissionSet } from "./permissions";

// Une seule définition du bloc d'alertes du tableau de bord staff — chaque
// nouvelle catégorie (Module 10, Volets B/C) s'ajoute ici, jamais en
// copiant-collant un bloc de plus dans dashboard/page.tsx (qui ne fait que
// grouper ce tableau par "kind" pour l'affichage).
export type DashboardAlert =
  | {
      kind: "low_coverage";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
      coverageEndDate: string | null;
    }
  | {
      kind: "lease_end_approaching";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
      endDate: string;
    }
  | {
      kind: "lease_closure_pending";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
      subKind: "keys_needed" | "inspection_needed" | "ready";
      dueDate: string | null;
    }
  | {
      kind: "entry_inspection_needed";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
    }
  | {
      kind: "deposit_refund_pending";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
      balances: { depositType: string; balance: number }[];
    }
  | {
      kind: "rent_overdue";
      leaseId: string;
      propertyName: string;
      tenantName: string | null;
      tenantPhone: string | null;
      dueDate: string;
      amount: number;
    };

// Gate chaque catégorie sur la permission de lecture pertinente — même
// principe que le bloc d'origine (Module 5c), juste étendu à deux
// nouvelles sources plutôt que dupliqué.
export async function getDashboardAlerts(
  organizationId: string,
  permissions: PermissionSet
): Promise<DashboardAlert[]> {
  const alerts: DashboardAlert[] = [];

  if (can(permissions, "payment_schedules", "read")) {
    const lowCoverage = await getLeasesWithLowScheduleCoverage(organizationId);
    for (const lease of lowCoverage) {
      if (!lease.lease_id) continue;
      alerts.push({
        kind: "low_coverage",
        leaseId: lease.lease_id,
        propertyName: lease.property_name ?? "—",
        tenantName: lease.tenant_full_name,
        coverageEndDate: lease.coverage_end_date,
      });
    }
  }

  if (can(permissions, "payment_schedules", "read")) {
    // Même source que l'accueil agent (getLeasesWithOverduePayments,
    // data/schedules.ts) -- pas un second calcul de retard.
    const overdue = await getLeasesWithOverduePayments(organizationId);
    for (const lease of overdue) {
      alerts.push({
        kind: "rent_overdue",
        leaseId: lease.lease_id,
        propertyName: lease.property_name,
        tenantName: lease.tenant_full_name,
        tenantPhone: lease.tenant_phone,
        dueDate: lease.due_date,
        amount: lease.amount_due,
      });
    }
  }

  if (can(permissions, "leases", "read")) {
    const upcoming = await getLeasesWithUpcomingEndDate(organizationId);
    for (const lease of upcoming) {
      alerts.push({
        kind: "lease_end_approaching",
        leaseId: lease.lease_id,
        propertyName: lease.property_name,
        tenantName: lease.tenant_full_name,
        // Non-null : la requête (data/lease-closure.ts) filtre déjà
        // lease_end_date IS NOT NULL.
        endDate: lease.lease_end_date as string,
      });
    }

    const pendingClosure = await getLeasesPendingClosure(organizationId);
    for (const lease of pendingClosure) {
      alerts.push({
        kind: "lease_closure_pending",
        leaseId: lease.lease_id,
        propertyName: lease.property_name,
        tenantName: lease.tenant_full_name,
        subKind: lease.exit_inspection_done
          ? "ready"
          : lease.keys_returned_at === null
            ? "keys_needed"
            : "inspection_needed",
        dueDate: lease.exit_inspection_due_date,
      });
    }

    const needingEntryInspection = await getLeasesNeedingEntryInspection(organizationId);
    for (const lease of needingEntryInspection) {
      alerts.push({
        kind: "entry_inspection_needed",
        leaseId: lease.lease_id,
        propertyName: lease.property_name,
        tenantName: lease.tenant_full_name,
      });
    }
  }

  // Resource dédiée (deposit_ledger), pas leases : un bail terminé sans
  // solde à rembourser n'a rien à voir ici, mais la lecture des montants
  // de caution reste gouvernée par sa propre permission, pas celle des
  // baux.
  if (can(permissions, "deposit_ledger", "read")) {
    const pendingRefunds = await getLeasesWithPendingDepositRefund(organizationId);
    for (const lease of pendingRefunds) {
      alerts.push({
        kind: "deposit_refund_pending",
        leaseId: lease.lease_id,
        propertyName: lease.property_name,
        tenantName: lease.tenant_full_name,
        balances: lease.balances.map((b) => ({ depositType: b.deposit_type, balance: b.balance })),
      });
    }
  }

  return alerts;
}
