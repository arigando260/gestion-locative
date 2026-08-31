import "server-only";
import { createClient } from "@/lib/supabase/server";

// Bornes du mois calendaire en cours, calculées en UTC -- new Date(y, m, 1)
// suivi de .toISOString() décale le mois d'un jour dès que le fuseau local
// du serveur a un offset positif (ex. Europe/Paris l'été), même précaution
// que daysSince (lib/format-date.ts).
export function currentMonthRange(): { start: string; end: string } {
  const now = new Date();
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth();
  const start = new Date(Date.UTC(year, month, 1));
  const end = new Date(Date.UTC(year, month + 1, 0));
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

export type MonthRentSchedule = {
  id: string;
  lease_id: string;
  property_name: string;
  tenant_full_name: string | null;
  tenant_phone: string | null;
  due_date: string;
  amount_due: number;
  covered_amount: number;
  effective_status: string;
};

// Échéances de loyer du mois calendaire en cours (hors annulée/hors
// période) -- source UNIQUE pour les tuiles KPI (getDashboardStats en
// délègue le calcul à summarizeMonthRentSchedules ci-dessous, sur ce même
// jeu de lignes) ET pour le tableau détaillé de /dashboard/loyers, jamais
// deux requêtes/calculs distincts qui pourraient diverger.
export async function getMonthRentSchedules(organizationId: string): Promise<MonthRentSchedule[]> {
  const supabase = await createClient();
  const { start, end } = currentMonthRange();
  const { data, error } = await supabase
    .from("payment_schedules_effective_status")
    .select(
      "id, lease_id, due_date, amount_due, covered_amount, effective_status, leases(properties(name), tenant_accounts(full_name, phone))"
    )
    .eq("organization_id", organizationId)
    .gte("due_date", start)
    .lte("due_date", end)
    .neq("effective_status", "annulee")
    .neq("effective_status", "hors_periode")
    .order("due_date", { ascending: true });

  if (error) throw error;

  const rows: MonthRentSchedule[] = [];
  for (const row of data ?? []) {
    if (!row.id || !row.lease_id || !row.due_date || row.amount_due == null) continue;
    const lease = row.leases as unknown as {
      properties: { name: string } | null;
      tenant_accounts: { full_name: string | null; phone: string | null } | null;
    } | null;
    rows.push({
      id: row.id,
      lease_id: row.lease_id,
      property_name: lease?.properties?.name ?? "—",
      tenant_full_name: lease?.tenant_accounts?.full_name ?? null,
      tenant_phone: lease?.tenant_accounts?.phone ?? null,
      due_date: row.due_date,
      amount_due: row.amount_due,
      covered_amount: row.covered_amount ?? 0,
      effective_status: row.effective_status ?? "en_attente",
    });
  }
  return rows;
}

export type MonthRentCollectionSummary = {
  billedAmount: number;
  collectedAmount: number;
  collectedRate: number;
  // Reste à encaisser DU MOIS CALENDAIRE EN COURS uniquement
  // (billedAmount - collectedAmount) -- à ne JAMAIS confondre avec
  // overdueAmount (data/dashboard-stats.ts), qui lui est volontairement non
  // borné dans le temps (tous les impayés, toutes périodes confondues,
  // décision actée séparément). Nom distinct exprès, même si le libellé
  // affiché à l'utilisateur est "À encaisser" aux deux endroits.
  monthOutstandingAmount: number;
  overdueCount: number;
  partialCount: number;
};

// Dérivé du même jeu de lignes que getMonthRentSchedules -- aucune requête
// supplémentaire, pure agrégation en mémoire.
export function summarizeMonthRentSchedules(schedules: MonthRentSchedule[]): MonthRentCollectionSummary {
  const billedAmount = schedules.reduce((sum, s) => sum + s.amount_due, 0);
  const monthOutstandingAmount = schedules.reduce(
    (sum, s) => sum + Math.max(s.amount_due - s.covered_amount, 0),
    0
  );
  const collectedAmount = billedAmount - monthOutstandingAmount;
  const collectedRate = billedAmount > 0 ? Math.round((collectedAmount / billedAmount) * 100) : 0;
  const overdueCount = schedules.filter((s) => s.effective_status === "en_retard").length;
  const partialCount = schedules.filter((s) => s.effective_status === "partiellement_payee").length;

  return { billedAmount, collectedAmount, collectedRate, monthOutstandingAmount, overdueCount, partialCount };
}
