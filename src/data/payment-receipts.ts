import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 9 (payment_receipts en est absent) — même remarque que
// data/maintenance.ts et data/lease-terminations.ts.

export type PaymentReceipt = {
  id: string;
  organization_id: string;
  payment_id: string;
  storage_path: string | null;
  created_at: string;
  generated_at: string | null;
};

// Sert aussi bien le staff (vérifier storage_path avant de générer) que le
// locataire (vérifier avant de proposer le téléchargement) — RLS
// (payment_receipts_select, Module 9) distingue déjà les deux dans la même
// policy, pas besoin d'une variante "getMy...".
export async function getPaymentReceiptByPaymentId(
  paymentId: string
): Promise<PaymentReceipt | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_receipts")
    .select("*")
    .eq("payment_id", paymentId)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Variante groupée de getPaymentReceiptByPaymentId, pour éviter un N+1 sur
// un historique de paiements (PaymentHistoryTable) — même table, même RLS
// (payment_receipts_select), juste .in() au lieu de .eq() sur payment_id.
export async function getPaymentReceiptsForPayments(
  paymentIds: string[]
): Promise<PaymentReceipt[]> {
  if (paymentIds.length === 0) return [];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("payment_receipts")
    .select("*")
    .in("payment_id", paymentIds);

  if (error) throw error;
  return data;
}

// Réservé au staff (RLS payment_receipts_update, Module 9) : seule
// transition légitime, storage_path null -> renseigné, imposée par le
// trigger fill_payment_receipt_storage_path — cette fonction ne fait
// qu'écrire, la base tranche de la légitimité.
export async function markPaymentReceiptGenerated(paymentId: string, storagePath: string) {
  const supabase = await createClient();
  return supabase
    .from("payment_receipts")
    .update({ storage_path: storagePath })
    .eq("payment_id", paymentId)
    .select()
    .single();
}

export async function getSignedPaymentReceiptUrl(storagePath: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from("payment-receipts")
    .createSignedUrl(storagePath, 3600);

  if (error) throw error;
  return data.signedUrl;
}

export type PaymentReceiptRenderData = {
  organization: {
    name: string;
    address: string | null;
    phone: string | null;
    email: string | null;
  };
  tenantName: string;
  amount: number;
  paymentDate: string;
  method: string;
  schedulePeriodStart: string | null;
  schedulePeriodEnd: string | null;
  receiptId: string;
};

// Rassemble tout ce que le template PDF a besoin d'afficher (voir
// lib/pdf/receipt-document.tsx) : organisation, locataire (résolu via le
// bail du paiement, payments_lease_required, Module 5/C), échéance
// concernée. Réservé au staff (seul appelant, voir
// actions/payment-receipts.ts) : jamais utilisé côté locataire, qui ne
// génère jamais.
export async function getPaymentReceiptRenderData(
  paymentId: string
): Promise<PaymentReceiptRenderData | null> {
  const supabase = await createClient();

  const { data: payment, error } = await supabase
    .from("payments")
    .select(
      "amount, payment_date, method, organizations(name, address, phone, email), payment_schedules(period_start_date, period_end_date), leases(tenant_account_id)"
    )
    .eq("id", paymentId)
    .maybeSingle();

  if (error) throw error;
  if (!payment) return null;

  // .maybeSingle() combiné à plusieurs relations many-to-one dans le même
  // select() : même correctif d'inférence qu'ailleurs dans ce projet (voir
  // data/leases.ts getMyLease) — un cast explicite plutôt qu'un générique
  // de requête qui n'enchaîne pas proprement avec .maybeSingle().
  const row = payment as unknown as {
    amount: number;
    payment_date: string;
    method: string;
    organizations: { name: string; address: string | null; phone: string | null; email: string | null } | null;
    payment_schedules: { period_start_date: string; period_end_date: string } | null;
    leases: { tenant_account_id: string } | null;
  };

  const tenantAccountId = row.leases?.tenant_account_id ?? null;
  let tenantName = "—";
  if (tenantAccountId) {
    const { data: tenant } = await supabase
      .from("tenant_accounts")
      .select("full_name")
      .eq("id", tenantAccountId)
      .maybeSingle();
    tenantName = tenant?.full_name ?? "—";
  }

  const { data: receipt } = await supabase
    .from("payment_receipts")
    .select("id")
    .eq("payment_id", paymentId)
    .maybeSingle();

  return {
    organization: row.organizations ?? { name: "—", address: null, phone: null, email: null },
    tenantName,
    amount: row.amount,
    paymentDate: row.payment_date,
    method: row.method,
    schedulePeriodStart: row.payment_schedules?.period_start_date ?? null,
    schedulePeriodEnd: row.payment_schedules?.period_end_date ?? null,
    receiptId: receipt?.id ?? paymentId,
  };
}
