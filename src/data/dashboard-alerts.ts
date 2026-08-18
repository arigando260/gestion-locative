import "server-only";
import { getLeasesWithLowScheduleCoverage } from "./schedules";
import {
  getLeasesWithUpcomingEndDate,
  getLeasesPendingClosure,
  getLeasesNeedingEntryInspection,
} from "./lease-closure";
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

  return alerts;
}
