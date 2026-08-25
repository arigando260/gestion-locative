import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables, TablesInsert } from "@/lib/supabase/database.types";

// special_terms : colonne du Module 10d, absente de database.types.ts tant
// que `supabase gen types` n'a pas été rejoué — même remarque que
// data/organizations.ts. Étend le type généré plutôt que de le réécrire.
export type Lease = Tables<"leases"> & { special_terms: string | null };
export type PaymentFrequency =
  | "mensuel"
  | "trimestriel"
  | "semestriel"
  | "annuel";
export type PaymentTiming = "prepaye" | "postpaye";

export type LeaseWithContext = Lease & {
  properties: {
    name: string;
    address_complement: string | null;
    location_type: string;
  } | null;
  organizations: { name: string } | null;
};

// Vue locataire : "toutes organisations confondues" (Module 1b), donc aucun
// filtre d'organisation ici — RLS (tenant_account_id = auth.uid()) est la
// seule chose qui restreint le résultat, pas cette fonction.
export async function getMyLeases(): Promise<LeaseWithContext[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("*, properties(name, address_complement, location_type), organizations(name)")
    .order("created_at", { ascending: false })
    .returns<LeaseWithContext[]>();

  if (error) throw error;
  return data;
}

export async function getMyLease(id: string): Promise<LeaseWithContext | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("*, properties(name, address_complement, location_type), organizations(name)")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  // .returns<T>() n'enchaîne pas proprement avec .maybeSingle() dans cette
  // version — même correctif d'inférence many-to-one qu'ailleurs, via un
  // simple cast plutôt qu'un générique de requête.
  return data as LeaseWithContext | null;
}

export async function getLease(id: string): Promise<Lease | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data as Lease | null;
}

// Une seule ligne possible (leases_one_pending_or_active_per_property,
// Module 10b) — utilisé uniquement pour proposer un lien direct depuis la
// fiche bien vers son bail en cours (actif OU brouillon), quand il en
// existe un ; renommée pour refléter l'index qu'elle reflète désormais.
export async function getPendingOrActiveLeaseForProperty(
  propertyId: string
): Promise<{ id: string; status: string } | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("id, status")
    .eq("property_id", propertyId)
    .in("status", ["actif", "brouillon"])
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Locataires ayant une adhésion ACTIVE avec l'organisation courante (RLS sur
// tenant_organization_memberships s'applique déjà : ne renvoie que ceux de
// l'organisation de l'appelant). Pas de gestion de locataires dans cette
// tranche — un compte doit déjà exister (script bootstrap ou module futur).
type TenantOption = { id: string; full_name: string | null; email: string };

export async function getTenantsForOrg(): Promise<TenantOption[]> {
  const supabase = await createClient();
  // tenant_account_id -> tenant_accounts est many-to-one (une ligne
  // d'adhésion référence exactement un tenant), mais sans types générés
  // précis pour cette relation, PostgREST/supabase-js l'infère par défaut
  // comme un tableau — .returns<T>() corrige l'annotation de type pour
  // correspondre à la forme réelle (même correctif qu'au Module 1 pour
  // user_roles -> roles).
  const { data, error } = await supabase
    .from("tenant_organization_memberships")
    .select("tenant_account_id, tenant_accounts(id, full_name, email)")
    .eq("status", "actif")
    .returns<{ tenant_accounts: TenantOption | null }[]>();

  if (error) throw error;
  return data
    .map((m) => m.tenant_accounts)
    .filter((t): t is TenantOption => t !== null);
}

// Baux de l'organisation courante, toutes propriétés confondues — utilisé
// par le formulaire de création de ticket de maintenance pour filtrer les
// baux selon le bien choisi côté client, sans aller-retour supplémentaire.
// RLS (is_internal + organization_id = current_org_id()) scope déjà à
// l'organisation, comme getProperties().
export type LeaseOption = Pick<Lease, "id" | "property_id" | "status" | "start_date">;

export async function getLeasesForOrg(): Promise<LeaseOption[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("id, property_id, status, start_date")
    .order("start_date", { ascending: false });

  if (error) throw error;
  return data;
}

// null = hérite du réglage organisation (Module 6) — même principe que les
// heures standard du Module 4b. Champ unique, écrit à part plutôt que via
// un futur updateLease générique : même discipline que
// setAdvanceConsumptionAuthorized (Module 3c/5), qui reste elle aussi une
// fonction dédiée à un seul champ plutôt qu'un update générique sur leases.
export async function updateLeaseTenantCapture(leaseId: string, value: boolean | null) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update({ tenant_capture_enabled: value })
    .eq("id", leaseId)
    .select()
    .single();
}

export type CreateLeaseInput = Pick<
  TablesInsert<"leases">,
  | "organization_id"
  | "property_id"
  | "tenant_account_id"
  | "start_date"
  | "end_date"
  | "rent_amount"
  | "payment_frequency"
  | "payment_timing"
  | "security_deposit_amount"
  | "utility_deposit_amount"
  | "billing_day"
>;

export async function createLease(input: CreateLeaseInput) {
  const supabase = await createClient();
  return supabase.from("leases").insert(input).select().single();
}

// ----------------------------------------------------------------------------
// Module 10, Volets B/C — trois écritures dédiées, un seul champ à la fois
// chacune (même discipline que updateLeaseTenantCapture ci-dessus) : le
// garde-fou de transition (Module 10) et la règle métier de clôture
// (keys_returned_at + état des lieux de sortie finalisé) sont déjà portés
// par la base, ces fonctions ne font que relayer l'écriture.
// ----------------------------------------------------------------------------

// Volet B — "renouveler" : simple UPDATE de end_date sur un bail actif, déjà
// couvert par la contrainte leases_end_after_start existante (Module 3).
export async function updateLeaseEndDate(leaseId: string, endDate: string | null) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update({ end_date: endDate })
    .eq("id", leaseId)
    .select()
    .single();
}

// Volet C, étape 1 — restitution des clés (Module 6, jusqu'ici inaccessible
// depuis aucun écran, voir diagnostic Module 10).
export async function recordKeysReturned(leaseId: string, date: string) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update({ keys_returned_at: date })
    .eq("id", leaseId)
    .select()
    .single();
}

// Volet C, étape finale — clôture définitive. Le trigger de garde (Module
// 10) revérifie lui-même keys_returned_at + état des lieux de sortie
// finalisé ; cette fonction ne fait que relayer la transition, jamais un
// geste automatique ou silencieux (toujours un clic staff explicite).
export async function closeLeaseDefinitively(leaseId: string) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update({ status: "termine" })
    .eq("id", leaseId)
    .select()
    .single();
}

// Clauses particulières (Module 10d) — override par bail, NULL = hérite du
// réglage organisation (résolution faite côté application, jamais en base
// — voir data/lease-contracts.ts).
export async function updateLeaseSpecialTerms(leaseId: string, specialTerms: string | null) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update({ special_terms: specialTerms })
    .eq("id", leaseId)
    .select()
    .single();
}

// Refus de contrat (Module 10) : la seule garde est déjà en base
// (trg_leases_prevent_delete_with_deposit_history — refuse avec un
// message P0001 clair si deposit_ledger n'est pas vide pour ce bail,
// jamais un 23503 brut). Rien à revérifier ici, l'erreur remonte telle
// quelle via toUserMessage (voir actions/leases.ts).
export async function deleteLease(leaseId: string) {
  const supabase = await createClient();
  return supabase.from("leases").delete().eq("id", leaseId);
}
