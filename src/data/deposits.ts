import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

export type DepositBalance = Tables<"deposit_ledger_balances">;
export type DepositLedgerEntry = Tables<"deposit_ledger">;
export type DepositType = "avance_garantie" | "caution_utilities";
export type ImputationCategory = "loyer" | "degats" | "impayes_utilities";

// Solde calculé à la volée (vue Module 5) — une ligne par deposit_type
// effectivement mouvementé sur ce bail, jamais matérialisé.
export async function getDepositBalancesForLease(
  leaseId: string
): Promise<DepositBalance[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("deposit_ledger_balances")
    .select("*")
    .eq("lease_id", leaseId);

  if (error) throw error;
  return data;
}

// Solde(s) restant à rembourser pour un bail — même vue que ci-dessus,
// filtrée balance > 0 en base (pas côté JS, cohérent avec le reste du
// projet, ex: getLeasesWithUpcomingEndDate). Utilisée par
// LeaseLifecycleBanner (bail 'termine') : un tableau vide signifie "rien à
// rembourser", que la caution ait été intégralement consommée ou jamais
// versée — les deux cas sont indiscernables ici et n'ont pas à l'être.
export async function getLeaseDepositBalancesWithRemainder(
  leaseId: string
): Promise<DepositBalance[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("deposit_ledger_balances")
    .select("*")
    .eq("lease_id", leaseId)
    .gt("balance", 0);

  if (error) throw error;
  return data;
}

export type LeaseDepositRefundPending = {
  lease_id: string;
  property_name: string;
  tenant_full_name: string | null;
  balances: { deposit_type: string; balance: number }[];
};

// Type écrit à la main pour la ligne embarquée (properties/tenant_accounts) :
// même remarque que data/lease-terminations.ts, database.types.ts ne suit
// pas la forme exacte d'un select avec embeds imbriqués.
type LeaseWithNamesRow = {
  id: string;
  properties: { name: string } | null;
  tenant_accounts: { full_name: string | null } | null;
};

// Baux 'termine' de l'organisation avec au moins un solde de caution non
// remboursé — pour le bloc d'alertes dashboard (data/dashboard-alerts.ts).
// deposit_ledger_balances est une vue sans FK exploitable par PostgREST
// pour un embed direct depuis leases (contrairement à leases_closure_status,
// qui expose déjà nom du bien/locataire) : deux lectures scopées à
// l'organisation, jointes ici plutôt qu'une vue de plus (aucune migration
// pour ce chantier).
export async function getLeasesWithPendingDepositRefund(
  organizationId: string
): Promise<LeaseDepositRefundPending[]> {
  const supabase = await createClient();

  const { data: leases, error: leasesError } = await supabase
    .from("leases")
    .select("id, properties(name), tenant_accounts(full_name)")
    .eq("organization_id", organizationId)
    .eq("status", "termine")
    .returns<LeaseWithNamesRow[]>();
  if (leasesError) throw leasesError;
  if (!leases || leases.length === 0) return [];

  const { data: balances, error: balancesError } = await supabase
    .from("deposit_ledger_balances")
    .select("lease_id, deposit_type, balance")
    .eq("organization_id", organizationId)
    .in(
      "lease_id",
      leases.map((l) => l.id)
    )
    .gt("balance", 0);
  if (balancesError) throw balancesError;

  const balancesByLease = new Map<string, { deposit_type: string; balance: number }[]>();
  for (const b of balances ?? []) {
    if (!b.lease_id) continue;
    const list = balancesByLease.get(b.lease_id) ?? [];
    list.push({ deposit_type: b.deposit_type ?? "", balance: b.balance ?? 0 });
    balancesByLease.set(b.lease_id, list);
  }

  return leases
    .filter((l) => balancesByLease.has(l.id))
    .map((l) => ({
      lease_id: l.id,
      property_name: l.properties?.name ?? "—",
      tenant_full_name: l.tenant_accounts?.full_name ?? null,
      balances: balancesByLease.get(l.id)!,
    }));
}

// Historique brut, append-only — aucune fonction update/delete dans ce
// module : une correction se fait par une nouvelle écriture, jamais par
// modification de l'historique (voir Module 5).
export async function getDepositLedgerForLease(
  leaseId: string
): Promise<DepositLedgerEntry[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("deposit_ledger")
    .select("*")
    .eq("lease_id", leaseId)
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data;
}

export type RecordInitialDepositInput = {
  organization_id: string;
  lease_id: string;
  deposit_type: DepositType;
  amount: number;
};

export async function recordInitialDeposit(input: RecordInitialDepositInput) {
  const supabase = await createClient();
  return supabase
    .from("deposit_ledger")
    .insert({ ...input, entry_type: "depot_initial" })
    .select()
    .single();
}

export type RecordImputationInput = {
  organization_id: string;
  lease_id: string;
  deposit_type: DepositType;
  imputation_category: ImputationCategory;
  amount: number;
  reason: string;
  payment_schedule_id?: string | null;
};

// Le trigger validate_deposit_ledger_damage_imputation_requires_inspections
// (dégâts) et validate_deposit_ledger_rent_imputation_authorized (loyer)
// rejettent déjà côté base tout ce qui ne respecte pas les règles métier —
// rien à revérifier ici, l'erreur P0001 remonte telle quelle à l'écran.
export async function recordImputation(input: RecordImputationInput) {
  const supabase = await createClient();
  return supabase
    .from("deposit_ledger")
    .insert({
      ...input,
      entry_type: "imputation",
      payment_schedule_id: input.payment_schedule_id ?? null,
    })
    .select()
    .single();
}

export type RecordRefundInput = {
  organization_id: string;
  lease_id: string;
  deposit_type: DepositType;
  amount: number;
  reason?: string | null;
};

export async function recordRefund(input: RecordRefundInput) {
  const supabase = await createClient();
  return supabase
    .from("deposit_ledger")
    .insert({ ...input, entry_type: "remboursement", reason: input.reason ?? null })
    .select()
    .single();
}

// Écrit sur `leases`, pas sur une table de caution — placé ici plutôt que
// dans data/leases.ts car exposé uniquement depuis l'écran de suivi des
// cautions : une imputation 'loyer' sur l'avance de garantie exige ce flag
// (trigger Module 5/6d). advance_consumption_authorized_at est forcé par
// trigger serveur ; _by et (à la révocation) _at doivent être fournis
// explicitement ici, la contrainte de cohérence (Module 3c) l'exige.
export async function setAdvanceConsumptionAuthorized(
  leaseId: string,
  authorized: boolean,
  authorizedByProfileId: string
) {
  const supabase = await createClient();
  return supabase
    .from("leases")
    .update(
      authorized
        ? {
            advance_consumption_authorized: true,
            advance_consumption_authorized_by: authorizedByProfileId,
          }
        : {
            advance_consumption_authorized: false,
            advance_consumption_authorized_by: null,
            advance_consumption_authorized_at: null,
          }
    )
    .eq("id", leaseId)
    .select()
    .single();
}
