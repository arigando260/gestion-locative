import "server-only";
import { createClient } from "@/lib/supabase/server";

// Aucune fonction SECURITY DEFINER ici, volontairement (Règle 1 du projet :
// pas de migration pour ce chantier) : toute lecture passe par les policies
// RLS déjà en place (properties_select / leases_select /
// payment_schedules_select / invoice_schedule_items_select), toutes déjà
// scopées par private.agent_property_scope() depuis le Module 12p — un
// agent à périmètre restreint ne voit donc qu'une partie de l'immeuble,
// silencieusement, sans code dédié ici.

// Jamais `new Date(year, month, ...)` pour calculer le dernier jour du mois
// (le projet évite les objets Date pour toute arithmétique de calendrier —
// voir lib/format-date.ts) : calcul par table statique + année bissextile,
// purement entier, aucun risque de fuseau horaire.
function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}

function daysInMonth(year: number, month: number): number {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month === 2 && isLeapYear(year)) return 29;
  return days[month - 1];
}

// month : "YYYY-MM" (valeur native d'un <input type="month">). Renvoie les
// bornes inclusives du mois calendaire, en dates "YYYY-MM-DD".
function monthBounds(month: string): { start: string; end: string } {
  const [yearStr, monthStr] = month.split("-");
  const year = Number(yearStr);
  const monthNum = Number(monthStr);
  const lastDay = daysInMonth(year, monthNum);
  return {
    start: `${month}-01`,
    end: `${month}-${String(lastDay).padStart(2, "0")}`,
  };
}

export type PendingScheduleDetail = {
  id: string;
  periodStartDate: string;
  periodEndDate: string;
  amountDue: number;
};

export type LeaseToInvoice = {
  leaseId: string;
  propertyId: string;
  propertyName: string;
  tenantName: string;
  schedules: PendingScheduleDetail[];
  totalAmount: number;
};

export type BuildingInvoicingSummary = {
  totalProperties: number;
  toInvoice: LeaseToInvoice[];
  vacantCount: number;
  alreadyInvoicedCount: number;
  // Bail actif mais aucune échéance ne chevauche le mois choisi (horizon de
  // génération pas encore atteint, bail trop récent...) -- ne correspond à
  // aucun des 3 autres compteurs, isolé explicitement pour que le total
  // reste cohérent avec totalProperties (voir plan validé, point D.1).
  noScheduleThisMonthCount: number;
};

const EMPTY_SUMMARY: BuildingInvoicingSummary = {
  totalProperties: 0,
  toInvoice: [],
  vacantCount: 0,
  alreadyInvoicedCount: 0,
  noScheduleThisMonthCount: 0,
};

export async function getBuildingInvoicingSummary(
  buildingId: string,
  month: string
): Promise<BuildingInvoicingSummary> {
  const supabase = await createClient();
  const { start: monthStart, end: monthEnd } = monthBounds(month);

  const { data: properties, error: propertiesError } = await supabase
    .from("properties")
    .select("id, name")
    .eq("building_id", buildingId);
  if (propertiesError) throw propertiesError;

  const totalProperties = properties?.length ?? 0;
  if (totalProperties === 0) {
    return EMPTY_SUMMARY;
  }
  const propertyIds = properties.map((p) => p.id);
  const propertyNameById = new Map(properties.map((p) => [p.id, p.name]));

  const { data: leases, error: leasesError } = await supabase
    .from("leases")
    .select("id, property_id, tenant_account_id")
    .in("property_id", propertyIds)
    .eq("status", "actif");
  if (leasesError) throw leasesError;

  const vacantCount = totalProperties - (leases?.length ?? 0);

  if (!leases || leases.length === 0) {
    return { ...EMPTY_SUMMARY, totalProperties, vacantCount };
  }

  const tenantIds = [...new Set(leases.map((l) => l.tenant_account_id))];
  const { data: tenants, error: tenantsError } = await supabase
    .from("tenant_accounts")
    .select("id, full_name")
    .in("id", tenantIds);
  if (tenantsError) throw tenantsError;
  const tenantNameById = new Map((tenants ?? []).map((t) => [t.id, t.full_name]));

  const leaseIds = leases.map((l) => l.id);

  // Chevauchement du mois choisi : bornes inclusives des deux côtés.
  // status != 'annulee' -- 'payee'/'partiellement_payee'/'en_retard' ne
  // sont jamais écrits dans la colonne brute (voir ARCHITECTURE.md), donc
  // exclure uniquement 'annulee' capture tout le reste correctement.
  const { data: schedules, error: schedulesError } = await supabase
    .from("payment_schedules")
    .select("id, lease_id, period_start_date, period_end_date, amount_due")
    .in("lease_id", leaseIds)
    .neq("status", "annulee")
    .lte("period_start_date", monthEnd)
    .gte("period_end_date", monthStart);
  if (schedulesError) throw schedulesError;

  const scheduleIds = (schedules ?? []).map((s) => s.id);

  const invoicedScheduleIds = new Set<string>();
  if (scheduleIds.length > 0) {
    const { data: items, error: itemsError } = await supabase
      .from("invoice_schedule_items")
      .select("payment_schedule_id")
      .in("payment_schedule_id", scheduleIds);
    if (itemsError) throw itemsError;
    for (const item of items ?? []) invoicedScheduleIds.add(item.payment_schedule_id);
  }

  const schedulesByLease = new Map<string, PendingScheduleDetail[]>();
  for (const s of schedules ?? []) {
    const list = schedulesByLease.get(s.lease_id) ?? [];
    list.push({
      id: s.id,
      periodStartDate: s.period_start_date,
      periodEndDate: s.period_end_date,
      amountDue: s.amount_due,
    });
    schedulesByLease.set(s.lease_id, list);
  }

  const toInvoice: LeaseToInvoice[] = [];
  let alreadyInvoicedCount = 0;
  let noScheduleThisMonthCount = 0;

  for (const lease of leases) {
    const leaseSchedules = schedulesByLease.get(lease.id) ?? [];
    if (leaseSchedules.length === 0) {
      noScheduleThisMonthCount++;
      continue;
    }

    const pending = leaseSchedules.filter((s) => !invoicedScheduleIds.has(s.id));
    if (pending.length === 0) {
      alreadyInvoicedCount++;
      continue;
    }

    toInvoice.push({
      leaseId: lease.id,
      propertyId: lease.property_id,
      propertyName: propertyNameById.get(lease.property_id) ?? "—",
      tenantName: tenantNameById.get(lease.tenant_account_id) ?? "—",
      schedules: pending,
      totalAmount: pending.reduce((sum, s) => sum + s.amountDue, 0),
    });
  }

  return {
    totalProperties,
    toInvoice,
    vacantCount,
    alreadyInvoicedCount,
    noScheduleThisMonthCount,
  };
}
