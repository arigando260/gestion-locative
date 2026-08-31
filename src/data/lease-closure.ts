import "server-only";
import { createClient } from "@/lib/supabase/server";

// Type écrit à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 10 (leases_closure_status en est absente).
export type LeaseClosureStatus = {
  lease_id: string;
  organization_id: string;
  status: string;
  lease_end_date: string | null;
  property_id: string;
  property_name: string;
  tenant_account_id: string;
  tenant_full_name: string | null;
  keys_returned_at: string | null;
  exit_inspection_due_date: string | null;
  latest_finalized_exit_inspection_id: string | null;
  latest_finalized_exit_inspection_date: string | null;
  exit_inspection_done: boolean;
  latest_finalized_entry_inspection_id: string | null;
  latest_finalized_entry_inspection_date: string | null;
  entry_inspection_done: boolean;
  // Module 10i : responded_at (resilie) / end_date (actif) / NULL sinon —
  // voir supabase/migrations/20260805430000_module10i_closure_reference_date.sql.
  // NULL couvre aussi le cas orphelin (bail resilie sans lease_termination_
  // requests validee associée) : à traiter comme "aucune borne connue",
  // jamais comme une erreur.
  closure_reference_date: string | null;
};

// Seuil d'affichage du bandeau "fin de bail" (Volet B) — décision
// d'affichage, pas une règle de base (leases_closure_status, Module 10,
// n'encode aucun seuil). Même esprit que LOW_COVERAGE_HORIZON_MONTHS
// (Module 5c) : partagé par la fiche bail et le bloc d'alertes dashboard,
// une seule définition.
export const LEASE_END_APPROACHING_DAYS = 30;

export function leaseEndApproachingThresholdDate(days: number = LEASE_END_APPROACHING_DAYS): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// "Clôture engagée" : soit le bail est résilié (Module 8, la chaîne
// universelle du Module 10 le fait de toute façon rejoindre ce même
// parcours), soit les clés ont déjà été restituées. C'est cette condition,
// et elle seule, qui distingue le bandeau Volet B (fin de bail normale) du
// bandeau Volet C (clôture en cours) — jamais les deux à la fois pour un
// même bail.
export function isLeaseClosureEngaged(
  row: Pick<LeaseClosureStatus, "status" | "keys_returned_at">
): boolean {
  return row.status === "resilie" || row.keys_returned_at !== null;
}

export async function getLeaseClosureStatus(leaseId: string): Promise<LeaseClosureStatus | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_closure_status")
    .select("*")
    .eq("lease_id", leaseId)
    .maybeSingle();

  if (error) throw error;
  return data as LeaseClosureStatus | null;
}

// Baux actifs dont la fin approche/est dépassée, PAS déjà engagés en
// clôture (sinon doublon avec getLeasesPendingClosure — même règle de
// non-chevauchement que le bandeau sur la fiche bail). status='actif' +
// keys_returned_at IS NULL suffit à exclure tout bail déjà engagé, un bail
// 'resilie' n'apparaît jamais ici par construction (filtré ci-dessous).
export async function getLeasesWithUpcomingEndDate(
  organizationId: string,
  days: number = LEASE_END_APPROACHING_DAYS
): Promise<LeaseClosureStatus[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_closure_status")
    .select("*")
    .eq("organization_id", organizationId)
    .eq("status", "actif")
    .is("keys_returned_at", null)
    .not("lease_end_date", "is", null)
    .lte("lease_end_date", leaseEndApproachingThresholdDate(days))
    .order("lease_end_date", { ascending: true });

  if (error) throw error;
  return data as LeaseClosureStatus[];
}

// Baux actifs sans état des lieux d'entrée finalisé, PAS déjà engagés en
// clôture — même exclusion (status='actif' + keys_returned_at IS NULL) que
// getLeasesWithUpcomingEndDate ci-dessus, pour la même raison de non-
// chevauchement : un bail déjà engagé en clôture ne doit apparaître que
// sous getLeasesPendingClosure, jamais sous deux catégories d'alerte à la
// fois (Module 10g).
export async function getLeasesNeedingEntryInspection(
  organizationId: string
): Promise<LeaseClosureStatus[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_closure_status")
    .select("*")
    .eq("organization_id", organizationId)
    .eq("status", "actif")
    .is("keys_returned_at", null)
    .eq("entry_inspection_done", false);

  if (error) throw error;
  return data as LeaseClosureStatus[];
}

// Baux dont la clôture est engagée (voir isLeaseClosureEngaged), quel que
// soit le sous-état (clés à restituer / état des lieux à faire / prêt à
// clôturer) — regroupe les 3 sous-états du bandeau Volet C en une seule
// liste, chaque appelant décide comment les distinguer à l'affichage.
export async function getLeasesPendingClosure(
  organizationId: string
): Promise<LeaseClosureStatus[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_closure_status")
    .select("*")
    .eq("organization_id", organizationId)
    .in("status", ["actif", "resilie"]);

  if (error) throw error;
  return ((data ?? []) as LeaseClosureStatus[]).filter(isLeaseClosureEngaged);
}

// Un seul jeu d'ids de biens "en préparation de sortie" (bail en clôture
// engagée) -- source unique pour la puce "État du parc" du tableau de bord
// ET le filtre de /properties, jamais deux calculs séparés qui pourraient
// diverger. Bâti sur getLeasesPendingClosure ci-dessus, pas une nouvelle
// requête.
export async function getClosurePendingPropertyIds(organizationId: string): Promise<Set<string>> {
  const leases = await getLeasesPendingClosure(organizationId);
  return new Set(leases.map((l) => l.property_id));
}

export type PropertyParkStatus = "occupe" | "disponible" | "en_travaux" | "en_preparation_sortie";

// Statut "parc" effectif d'un bien : la clôture de bail engagée prime sur
// le statut brut (occupe/disponible/en_travaux) -- un bien en préparation
// de sortie ne compte jamais aussi comme "occupé". Même règle utilisée par
// la puce du tableau de bord et le filtre /properties, une seule
// définition.
export function resolvePropertyParkStatus(
  propertyId: string,
  rawStatus: string,
  closurePropertyIds: ReadonlySet<string>
): PropertyParkStatus {
  return closurePropertyIds.has(propertyId) ? "en_preparation_sortie" : (rawStatus as PropertyParkStatus);
}
