import "server-only";
import { createClient } from "@/lib/supabase/server";

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

function currentMonthRange(): { start: string; end: string } {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

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
  const { start, end } = currentMonthRange();

  const [
    { data: properties, error: propertiesError },
    { count: buildingsCount, error: buildingsError },
    { data: monthSchedules, error: monthSchedulesError },
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
    supabase
      .from("payment_schedules_effective_status")
      .select("amount_due, covered_amount")
      .eq("organization_id", organizationId)
      .gte("due_date", start)
      .lte("due_date", end)
      .neq("effective_status", "annulee")
      .neq("effective_status", "hors_periode"),
    supabase
      .from("payment_schedules_effective_status")
      .select("lease_id, due_date, amount_due, covered_amount")
      .eq("organization_id", organizationId)
      .eq("effective_status", "en_retard"),
  ]);

  if (propertiesError) throw propertiesError;
  if (buildingsError) throw buildingsError;
  if (monthSchedulesError) throw monthSchedulesError;
  if (overdueSchedulesError) throw overdueSchedulesError;

  const propertiesCount = properties.length;
  const occupiedCount = properties.filter((p) => p.effective_status === "occupe").length;
  const occupancyRate = propertiesCount > 0 ? Math.round((occupiedCount / propertiesCount) * 100) : 0;

  const rentThisMonth = monthSchedules.reduce((sum, s) => sum + (s.amount_due ?? 0), 0);
  const dueThisMonth = monthSchedules.reduce(
    (sum, s) => sum + Math.max((s.amount_due ?? 0) - (s.covered_amount ?? 0), 0),
    0
  );
  const collectedThisMonth = rentThisMonth - dueThisMonth;
  const collectedRate = rentThisMonth > 0 ? Math.round((collectedThisMonth / rentThisMonth) * 100) : 0;

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
