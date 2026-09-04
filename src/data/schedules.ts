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
//
// Exception — reconduction tacite (Module 10l) : un bail encore ACTIF dont
// end_date est dépassée n'est jamais réellement "complet", il continue en
// horizon glissant (même principe que le générateur, dont le plafond
// effectif ignore end_date dans exactement ce cas). Sans ce cas particulier,
// dès que la couverture générée atteint l'ancienne end_date, cette fonction
// répondrait "rien à faire" et empêcherait à la fois l'extension silencieuse
// et l'alerte "couverture faible" de jamais relancer le générateur corrigé.
export function hasRoomToGrowSchedules(
  leaseStatus: string,
  leaseEndDate: string | null,
  coverageEndDate: string | null
): boolean {
  const today = new Date().toISOString().slice(0, 10);
  const isTacitRenewal =
    leaseStatus === "actif" && leaseEndDate !== null && leaseEndDate <= today;
  if (isTacitRenewal) return true;

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
  tenant_phone: string | null;
  due_date: string;
  amount_due: number;
};

// Une ligne par bail (la plus ancienne échéance en retard), pas une par
// échéance -- source pour l'accueil agent (tâches "Relance") ET pour la
// catégorie "loyer en retard" du tableau de bord admin (bouton "Relancer",
// lien tel: -- d'où tenant_phone, absent jusqu'ici). Même lecture que
// getLeasesWithLowScheduleCoverage ci-dessous (vue effective_status,
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
      "lease_id, due_date, amount_due, leases(properties(name), tenant_accounts(full_name, phone))"
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
      tenant_accounts: { full_name: string | null; phone: string | null } | null;
    } | null;
    byLease.set(row.lease_id, {
      lease_id: row.lease_id,
      property_name: lease?.properties?.name ?? "—",
      tenant_full_name: lease?.tenant_accounts?.full_name ?? null,
      tenant_phone: lease?.tenant_accounts?.phone ?? null,
      due_date: row.due_date,
      amount_due: row.amount_due,
    });
  }

  return Array.from(byLease.values());
}

function upcomingDaysRange(days: number): { start: string; end: string } {
  const now = new Date();
  const start = now.toISOString().slice(0, 10);
  const end = new Date(now.getTime() + days * 86_400_000).toISOString().slice(0, 10);
  return { start, end };
}

export type UpcomingSchedule = {
  id: string;
  lease_id: string;
  property_name: string;
  tenant_full_name: string | null;
  due_date: string;
  amount_due: number;
};

// Échéances dont la date tombe dans les `days` prochains jours (7 par
// défaut), statut en_attente uniquement (pas encore due, distinct de
// en_retard déjà utilisé ailleurs dans ce fichier) -- source pour le
// compteur "À venir" (toujours à 7j, cf. wrapper ci-dessous) ET la liste
// détaillée de /dashboard/echeances (fenêtre choisie par le filtre temporel
// de cet écran), jamais deux calculs séparés (même principe que
// resolvePropertyParkStatus/alertSeverity).
export async function getSchedulesDueThisWeek(
  organizationId: string,
  days = 7
): Promise<UpcomingSchedule[]> {
  const supabase = await createClient();
  const { start, end } = upcomingDaysRange(days);
  const { data, error } = await supabase
    .from("payment_schedules_effective_status")
    .select("id, lease_id, due_date, amount_due, leases(properties(name), tenant_accounts(full_name))")
    .eq("organization_id", organizationId)
    .eq("effective_status", "en_attente")
    .gte("due_date", start)
    .lte("due_date", end)
    .order("due_date", { ascending: true });

  if (error) throw error;

  const rows: UpcomingSchedule[] = [];
  for (const row of data ?? []) {
    if (!row.id || !row.lease_id || !row.due_date || row.amount_due == null) continue;
    const lease = row.leases as unknown as {
      properties: { name: string } | null;
      tenant_accounts: { full_name: string | null } | null;
    } | null;
    rows.push({
      id: row.id,
      lease_id: row.lease_id,
      property_name: lease?.properties?.name ?? "—",
      tenant_full_name: lease?.tenant_accounts?.full_name ?? null,
      due_date: row.due_date,
      amount_due: row.amount_due,
    });
  }
  return rows;
}

// Compteur "À venir" du tableau de bord -- simple wrapper de
// getSchedulesDueThisWeek ci-dessus.
export async function getUpcomingScheduleCountThisWeek(organizationId: string): Promise<number> {
  return (await getSchedulesDueThisWeek(organizationId)).length;
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
    // lease.status est typé nullable côté vue (comportement de génération
    // Supabase pour les colonnes de vue), mais la requête ci-dessus filtre
    // déjà .eq("status", "actif") -- jamais réellement null à l'exécution.
    hasRoomToGrowSchedules(lease.status ?? "", lease.lease_end_date, lease.coverage_end_date)
  );
}
