import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

export type ScheduleWithEffectiveStatus =
  Tables<"payment_schedules_effective_status">;

// Lit toujours le statut EFFECTIF (calculé à la volée), jamais la colonne
// brute payment_schedules.status qui ne porte plus que la décision manuelle
// (en_attente/annulee) — voir ARCHITECTURE.md.
export async function getSchedulesForLease(
  leaseId: string
): Promise<ScheduleWithEffectiveStatus[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_schedules_effective_status")
    .select("*")
    .eq("lease_id", leaseId)
    .order("period_start_date");

  if (error) throw error;
  return data;
}

export async function getSchedule(
  id: string
): Promise<ScheduleWithEffectiveStatus | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_schedules_effective_status")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Délègue entièrement à la fonction RPC (idempotente, gère raccordement,
// prépayé, jour de facturation) — voir Module 5b. Renvoie le nombre
// d'échéances effectivement créées par CET appel.
export async function generateSchedulesForLease(leaseId: string) {
  const supabase = await createClient();
  return supabase.rpc("generate_payment_schedules_for_lease", {
    p_lease_id: leaseId,
  });
}

export type LeaseScheduleCoverage = Tables<"leases_schedule_coverage">;

// Seuil "couverture faible" partagé par l'extension silencieuse (fiche
// bail) et le bloc d'alertes (tableau de bord) — Module 5c. Une seule
// définition du seuil, pas une par appelant.
const LOW_COVERAGE_HORIZON_MONTHS = 2;

export function scheduleCoverageThresholdDate(): string {
  const d = new Date();
  d.setMonth(d.getMonth() + LOW_COVERAGE_HORIZON_MONTHS);
  return d.toISOString().slice(0, 10);
}

export async function getLeaseScheduleCoverage(
  leaseId: string
): Promise<LeaseScheduleCoverage | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_schedule_coverage")
    .select("*")
    .eq("lease_id", leaseId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Un seul aller-retour, pas de boucle par bail : le filtre (organisation +
// actif + couverture sous le seuil) est appliqué côté base sur la vue
// leases_schedule_coverage (Module 5c).
export async function getLeasesWithLowScheduleCoverage(
  organizationId: string
): Promise<LeaseScheduleCoverage[]> {
  const supabase = await createClient();
  const threshold = scheduleCoverageThresholdDate();
  const { data, error } = await supabase
    .from("leases_schedule_coverage")
    .select("*")
    .eq("organization_id", organizationId)
    .eq("status", "actif")
    .or(`coverage_end_date.is.null,coverage_end_date.lt.${threshold}`)
    .order("coverage_end_date", { ascending: true, nullsFirst: true });

  if (error) throw error;
  return data;
}
