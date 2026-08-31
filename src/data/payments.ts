import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

export type Payment = Tables<"payments">;
export type PaymentMethod = "mobile_money" | "carte" | "especes" | "virement";

// Historique de paiements d'un bail — réutilisé côté gestionnaire et côté
// portail locataire (RLS restreint déjà ce dernier à ses propres baux).
export async function getPaymentsForLease(leaseId: string): Promise<Payment[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payments")
    .select("*")
    .eq("lease_id", leaseId)
    .order("payment_date", { ascending: false });

  if (error) throw error;
  return data;
}

export type RecordPaymentInput = {
  organization_id: string;
  lease_id: string;
  payment_schedule_id: string;
  amount: number;
  method: PaymentMethod;
  payment_date: string;
  external_reference?: string | null;
};

// Aucune intégration de paiement (Mobile Money, carte...) dans cette
// tranche : un paiement enregistré ici représente un règlement déjà reçu et
// constaté manuellement par le staff, donc confirmé immédiatement. Une
// future intégration passerelle créerait plutôt la ligne en 'en_attente'
// et la confirmerait via webhook.
export type SchedulePaymentInfo = { paymentId: string; method: string };

// Le paiement confirmé le plus récent par échéance -- utilisé pour la
// quittance de /dashboard/loyers (montant réglé lui-même toujours lu depuis
// covered_amount, vue payment_schedules_effective_status, seule source de
// vérité du montant ; ceci ne sert qu'à retrouver QUEL paiement quittancer
// quand un règlement scindé a produit plusieurs lignes confirmées pour la
// même échéance).
export async function getLatestConfirmedPaymentsForSchedules(
  scheduleIds: string[]
): Promise<Map<string, SchedulePaymentInfo>> {
  if (scheduleIds.length === 0) return new Map();

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payments")
    .select("id, payment_schedule_id, method, payment_date")
    .in("payment_schedule_id", scheduleIds)
    .eq("status", "confirme")
    .order("payment_date", { ascending: false });

  if (error) throw error;

  const map = new Map<string, SchedulePaymentInfo>();
  for (const row of data ?? []) {
    if (!row.payment_schedule_id || map.has(row.payment_schedule_id)) continue;
    map.set(row.payment_schedule_id, { paymentId: row.id, method: row.method });
  }
  return map;
}

export async function recordPayment(input: RecordPaymentInput) {
  const supabase = await createClient();
  return supabase
    .from("payments")
    .insert({
      organization_id: input.organization_id,
      lease_id: input.lease_id,
      payment_schedule_id: input.payment_schedule_id,
      amount: input.amount,
      method: input.method,
      payment_date: input.payment_date,
      external_reference: input.external_reference ?? null,
      payment_type: "loyer",
      direction: "entrant",
      status: "confirme",
    })
    .select()
    .single();
}
