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

// Un bail à durée déterminée dont la couverture déjà générée atteint (ou
// dépasse) sa date de fin n'a plus rien à générer — ni l'extension
// silencieuse (fiche bail) ni l'alerte dashboard ne doivent le traiter
// comme "à compléter". Une seule définition, réutilisée aux deux endroits
// plutôt que dupliquée (auparavant inline sur leases/[leaseId]/page.tsx
// sous le nom stillRoomToGrow, absente de getLeasesWithLowScheduleCoverage).
export function hasRoomToGrowSchedules(
  leaseEndDate: string | null,
  coverageEndDate: string | null
): boolean {
  return (
    leaseEndDate === null ||
    coverageEndDate === null ||
    coverageEndDate < leaseEndDate
  );
}

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
// leases_schedule_coverage (Module 5c). "Room to grow" (Module 10) filtré
// côté application : PostgREST ne sait pas comparer deux colonnes entre
// elles (coverage_end_date < lease_end_date) dans un filtre .or(), seul un
// littéral est possible côté requête — même limite déjà contournée ainsi
// sur la fiche bail.
export type OverdueLease = {
  lease_id: string;
  property_name: string;
  tenant_full_name: string | null;
  due_date: string;
  amount_due: number;
};

// Une ligne par bail (la plus ancienne échéance en retard), pas une par
// échéance -- source pour l'accueil agent (tâches "Relance"). Même lecture
// que getLeasesWithLowScheduleCoverage ci-dessous (vue effective_status,
// jamais la colonne brute), mais pas de vue dédiée "leases en retard" :
// jointure directe payment_schedules_effective_status -> leases ->
// properties/tenant_accounts plutôt qu'une nouvelle vue SQL pour un seul
// écran.
export async function getLeasesWithOverduePayments(
  organizationId: string
): Promise<OverdueLease[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_schedules_effective_status")
    .select(
      "lease_id, due_date, amount_due, leases(properties(name), tenant_accounts(full_name))"
    )
    .eq("organization_id", organizationId)
    .eq("effective_status", "en_retard")
    .order("due_date", { ascending: true });

  if (error) throw error;

  const byLease = new Map<string, OverdueLease>();
  for (const row of data ?? []) {
    if (!row.lease_id || !row.due_date || row.amount_due == null) continue;
    if (byLease.has(row.lease_id)) continue;
    const lease = row.leases as unknown as {
      properties: { name: string } | null;
      tenant_accounts: { full_name: string | null } | null;
    } | null;
    byLease.set(row.lease_id, {
      lease_id: row.lease_id,
      property_name: lease?.properties?.name ?? "—",
      tenant_full_name: lease?.tenant_accounts?.full_name ?? null,
      due_date: row.due_date,
      amount_due: row.amount_due,
    });
  }

  return Array.from(byLease.values());
}

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
  return data.filter((lease) =>
    hasRoomToGrowSchedules(lease.lease_end_date, lease.coverage_end_date)
  );
}
