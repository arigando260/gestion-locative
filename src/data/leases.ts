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
