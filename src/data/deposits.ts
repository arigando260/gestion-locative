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
