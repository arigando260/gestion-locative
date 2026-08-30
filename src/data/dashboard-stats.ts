import "server-only";
import { createClient } from "@/lib/supabase/server";

export type DashboardStats = {
  propertiesCount: number;
  occupancyRate: number;
  rentThisMonth: number;
  dueThisMonth: number;
};

function currentMonthRange(): { start: string; end: string } {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 0);
  return { start: start.toISOString().slice(0, 10), end: end.toISOString().slice(0, 10) };
}

// Agrégats simples pour les 4 tuiles du tableau de bord — dérivés des vues
// déjà exploitées ailleurs (properties_effective_status,
// payment_schedules_effective_status), pas de nouvelle table/RPC.
export async function getDashboardStats(organizationId: string): Promise<DashboardStats> {
  const supabase = await createClient();
  const { start, end } = currentMonthRange();

  const [{ data: properties, error: propertiesError }, { data: schedules, error: schedulesError }] =
    await Promise.all([
      supabase
        .from("properties_effective_status")
        .select("effective_status")
        .eq("organization_id", organizationId),
      supabase
        .from("payment_schedules_effective_status")
        .select("amount_due, covered_amount")
        .eq("organization_id", organizationId)
        .gte("due_date", start)
        .lte("due_date", end)
        .neq("effective_status", "annulee")
        .neq("effective_status", "hors_periode"),
    ]);

  if (propertiesError) throw propertiesError;
  if (schedulesError) throw schedulesError;

  const propertiesCount = properties.length;
  const occupiedCount = properties.filter((p) => p.effective_status === "occupe").length;
  const occupancyRate = propertiesCount > 0 ? Math.round((occupiedCount / propertiesCount) * 100) : 0;

  const rentThisMonth = schedules.reduce((sum, s) => sum + (s.amount_due ?? 0), 0);
  const dueThisMonth = schedules.reduce(
    (sum, s) => sum + Math.max((s.amount_due ?? 0) - (s.covered_amount ?? 0), 0),
    0
  );

  return { propertiesCount, occupancyRate, rentThisMonth, dueThisMonth };
}
