import "server-only";
import { createClient } from "@/lib/supabase/server";
import { getMonthRentSchedules, summarizeMonthRentSchedules } from "@/data/rent-collection";

export type DashboardStats = {
  propertiesCount: number;
  buildingsCount: number;
  occupancyRate: number;
  rentThisMonth: number;
  collectedThisMonth: number;
  collectedRate: number;
  overdueAmount: number;
  overdueLeasesCount: number;
  oldestOverdueDueDate: string | null;
};

// Agrégats pour les tuiles du tableau de bord — dérivés des vues déjà
// exploitées ailleurs (properties_effective_status,
// payment_schedules_effective_status), pas de nouvelle table/RPC.
//
// "À encaisser" (overdueAmount/overdueLeasesCount/oldestOverdueDueDate) lit
// le vrai statut effectif en_retard SANS restriction de mois -- même
// principe que getLeasesWithOverduePayments (agent-today-view) et
// tenant-next-action : un impayé de juillet reste un impayé en septembre.
// Volontairement distinct de rentThisMonth/collectedThisMonth, qui eux
// portent spécifiquement sur la facturation du mois calendaire en cours
// (deux notions différentes, pas un bug de délimitation commun).
export async function getDashboardStats(organizationId: string): Promise<DashboardStats> {
  const supabase = await createClient();

  const [
    { data: properties, error: propertiesError },
    { count: buildingsCount, error: buildingsError },
    monthSchedules,
    { data: overdueSchedules, error: overdueSchedulesError },
  ] = await Promise.all([
    supabase
      .from("properties_effective_status")
      .select("effective_status")
      .eq("organization_id", organizationId),
    supabase
      .from("buildings")
      .select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId),
    getMonthRentSchedules(organizationId),
    supabase
      .from("payment_schedules_effective_status")
      .select("lease_id, due_date, amount_due, covered_amount")
      .eq("organization_id", organizationId)
      .eq("effective_status", "en_retard"),
  ]);

  if (propertiesError) throw propertiesError;
  if (buildingsError) throw buildingsError;
  if (overdueSchedulesError) throw overdueSchedulesError;

  const propertiesCount = properties.length;
  const occupiedCount = properties.filter((p) => p.effective_status === "occupe").length;
  const occupancyRate = propertiesCount > 0 ? Math.round((occupiedCount / propertiesCount) * 100) : 0;

  const { billedAmount: rentThisMonth, collectedAmount: collectedThisMonth, collectedRate } =
    summarizeMonthRentSchedules(monthSchedules);

  const overdueAmount = overdueSchedules.reduce(
    (sum, s) => sum + Math.max((s.amount_due ?? 0) - (s.covered_amount ?? 0), 0),
    0
  );
  const overdueLeasesCount = new Set(overdueSchedules.map((s) => s.lease_id)).size;
  const oldestOverdueDueDate = overdueSchedules.reduce<string | null>((oldest, s) => {
    if (!s.due_date) return oldest;
    return !oldest || s.due_date < oldest ? s.due_date : oldest;
  }, null);

  return {
    propertiesCount,
    buildingsCount: buildingsCount ?? 0,
    occupancyRate,
    rentThisMonth,
    collectedThisMonth,
    collectedRate,
    overdueAmount,
    overdueLeasesCount,
    oldestOverdueDueDate,
  };
}
