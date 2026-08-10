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
