import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 10 (lease_contracts / leases_activation_readiness en
// sont absentes) — même remarque que data/schedule-invoices.ts.

export type LeaseContract = {
  id: string;
  organization_id: string;
  lease_id: string;
  storage_path: string;
  generated_at: string;
  approved_at: string | null;
};

export type LeaseActivationReadiness = {
  lease_id: string;
  organization_id: string;
  status: string;
  deposits_complete: boolean;
  contract_id: string | null;
  contract_storage_path: string | null;
  contract_generated_at: string | null;
  contract_approved_at: string | null;
};

// Partagée staff/locataire : RLS (lease_contracts_select, Module 10)
// distingue déjà les deux dans la même policy, comme getScheduleInvoicesForLease.
export async function getLeaseContractByLeaseId(leaseId: string): Promise<LeaseContract | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("lease_contracts")
    .select("*")
    .eq("lease_id", leaseId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Source unique d'éligibilité (dépôts complets), jamais recalculée côté
// TypeScript — voir private.lease_deposits_complete (Module 10). La ligne
// n'existe que pour un bail encore 'brouillon' (la vue exclut le reste).
export async function getLeaseActivationReadiness(
  leaseId: string
): Promise<LeaseActivationReadiness | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leases_activation_readiness")
    .select("*")
    .eq("lease_id", leaseId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export async function getSignedLeaseContractUrl(storagePath: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from("lease-contracts")
    .createSignedUrl(storagePath, 3600);

  if (error) throw error;
  return data.signedUrl;
}

export type LeaseContractRenderData = {
  organizationId: string;
  organization: { name: string; address: string | null; phone: string | null; email: string | null };
  tenantName: string;
  propertyLabel: string;
  propertyAddress: string;
  rentAmount: number;
  paymentFrequency: string;
  securityDepositAmount: number;
  utilityDepositAmount: number | null;
  startDate: string;
  endDate: string | null;
  // Résolution Module 10d : le bail prime s'il définit ses propres clauses,
  // sinon celles de l'organisation, sinon aucune section dans le PDF —
  // calculée ici, jamais en base (voir migration 20260805270000).
  specialTerms: string | null;
};

// Rassemble tout ce qu'il faut pour générer le PDF du contrat — même
// pattern que getInvoiceGenerationContext (Module 9) : organisation et bien
// embarqués dans la même requête sur leases, jamais reconstruits à part.
export async function getLeaseContractRenderData(
  leaseId: string
): Promise<LeaseContractRenderData | null> {
  const supabase = await createClient();
  const { data: lease, error } = await supabase
    .from("leases")
    .select(
      "organization_id, tenant_account_id, rent_amount, payment_frequency, security_deposit_amount, utility_deposit_amount, start_date, end_date, special_terms, organizations(name, address, phone, email, special_terms), properties(name, address)"
    )
    .eq("id", leaseId)
    .maybeSingle();

  if (error) throw error;
  if (!lease) return null;

  // Même correctif d'inférence many-to-one que data/schedule-invoices.ts.
  const row = lease as unknown as {
    organization_id: string;
    tenant_account_id: string;
    rent_amount: number;
    payment_frequency: string;
    security_deposit_amount: number;
    utility_deposit_amount: number | null;
    start_date: string;
    end_date: string | null;
    special_terms: string | null;
    organizations: {
      name: string;
      address: string | null;
      phone: string | null;
      email: string | null;
      special_terms: string | null;
    } | null;
    properties: { name: string; address: string } | null;
  };

  const { data: tenant } = await supabase
    .from("tenant_accounts")
    .select("full_name")
    .eq("id", row.tenant_account_id)
    .maybeSingle();

  return {
    organizationId: row.organization_id,
    organization: row.organizations ?? { name: "—", address: null, phone: null, email: null },
    tenantName: tenant?.full_name ?? "—",
    propertyLabel: row.properties?.name ?? "—",
    propertyAddress: row.properties?.address ?? "—",
    rentAmount: row.rent_amount,
    paymentFrequency: row.payment_frequency,
    securityDepositAmount: row.security_deposit_amount,
    utilityDepositAmount: row.utility_deposit_amount,
    startDate: row.start_date,
    endDate: row.end_date,
    specialTerms: row.special_terms ?? row.organizations?.special_terms ?? null,
  };
}

export type CreateLeaseContractInput = {
  organization_id: string;
  lease_id: string;
  storage_path: string;
};

export async function createLeaseContractRecord(input: CreateLeaseContractInput) {
  const supabase = await createClient();
  return supabase.from("lease_contracts").insert(input).select().single();
}

// Le passage de leases.status à 'actif' est appliqué par le trigger security
// definer côté base (private.activate_lease_on_contract_approval, Module 10)
// — cette fonction ne fait que poser approved_at, jamais leases.status
// directement. La valeur envoyée est de toute façon écrasée par le serveur
// (trigger fill_lease_contract_approved_at) ; seule son caractère non-null
// compte pour déclencher la transition.
export async function approveLeaseContract(contractId: string) {
  const supabase = await createClient();
  return supabase
    .from("lease_contracts")
    .update({ approved_at: new Date().toISOString() })
    .eq("id", contractId)
    .select()
    .single();
}
