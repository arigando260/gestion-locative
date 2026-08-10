import "server-only";
import { createClient } from "@/lib/supabase/server";

export type PaymentMethod = "mobile_money" | "carte" | "especes" | "virement";

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
