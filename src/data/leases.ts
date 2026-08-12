import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables, TablesInsert } from "@/lib/supabase/database.types";

export type Lease = Tables<"leases">;
export type PaymentFrequency =
  | "mensuel"
  | "trimestriel"
  | "semestriel"
  | "annuel";
export type PaymentTiming = "prepaye" | "postpaye";

export type LeaseWithContext = Lease & {
  properties: { name: string; address: string; location_type: string } | null;
  organizations: { name: string } | null;
};

// Vue locataire : "toutes organisations confondues" (Module 1b), donc aucun
// filtre d'organisation ici — RLS (tenant_account_id = auth.uid()) est la
// seule chose qui restreint le résultat, pas cette fonction.
export async function getMyLeases(): Promise<LeaseWithContext[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("*, properties(name, address, location_type), organizations(name)")
    .order("created_at", { ascending: false })
    .returns<LeaseWithContext[]>();

  if (error) throw error;
  return data;
}

export async function getMyLease(id: string): Promise<LeaseWithContext | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases")
    .select("*, properties(name, address, location_type), organizations(name)")
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
