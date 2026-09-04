import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 9 (schedule_invoices/invoice_schedule_items en sont
// absentes) — même remarque que data/maintenance.ts.

export type ScheduleInvoice = {
  id: string;
  organization_id: string;
  lease_id: string | null;
  storage_path: string;
  generated_by: string;
  generated_at: string;
};

// Partagée staff/locataire : RLS (schedule_invoices_select, Module 9)
// distingue déjà les deux dans la même policy — même principe que
// getSchedulesForLease/getPaymentsForLease, jamais dupliquées en "getMy...".
export async function getScheduleInvoicesForLease(leaseId: string): Promise<ScheduleInvoice[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("schedule_invoices")
    .select("*")
    .eq("lease_id", leaseId)
    .order("generated_at", { ascending: false });

  if (error) throw error;
  return data;
}

export async function getSignedScheduleInvoiceUrl(storagePath: string): Promise<string> {
  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from("schedule-invoices")
    .createSignedUrl(storagePath, 3600);

  if (error) throw error;
  return data.signedUrl;
}

export type InvoiceLineItemContext = {
  id: string;
  periodStart: string;
  periodEnd: string;
  dueDate: string;
  amountDue: number;
};

export type InvoiceGenerationContext = {
  organizationId: string;
  organization: {
    name: string;
    address: string | null;
    phone: string | null;
    email: string | null;
  };
  tenantName: string;
  propertyLabel: string;
  lineItems: InvoiceLineItemContext[];
};

// Rassemble tout ce qu'il faut pour générer la facture (organisation,
// locataire, échéances) ET revérifie que CHAQUE échéance sélectionnée
// appartient bien à ce bail (defense in depth : le trigger de cohérence sur
// invoice_schedule_items, Module 9, le bloquerait de toute façon à
// l'insertion, mais autant ne pas rendre/uploader un PDF pour une sélection
// invalide). Exclut aussi status='annulee' (même motif que
// data/building-invoicing.ts) : une échéance annulée (Module 10l -- au-delà
// de la date de résiliation) ne doit jamais être facturable, même si un
// schedule_id annulé arrivait malgré tout dans scheduleIds (contournement du
// formulaire, appel direct de l'action). Renvoie null si le bail est
// introuvable ou si une seule échéance ne correspond pas / est annulée.
export async function getInvoiceGenerationContext(
  leaseId: string,
  scheduleIds: string[]
): Promise<InvoiceGenerationContext | null> {
  const supabase = await createClient();

  const { data: lease, error: leaseError } = await supabase
    .from("leases")
    .select("organization_id, tenant_account_id, organizations(name, address, phone, email), properties(name)")
    .eq("id", leaseId)
    .maybeSingle();

  if (leaseError) throw leaseError;
  if (!lease) return null;

  // Même correctif d'inférence many-to-one que data/payment-receipts.ts.
  // Pas de resolve_property_address ici (contrairement à
  // data/lease-contracts.ts, Module 13) : invoice-document.tsx n'affiche
  // que propertyLabel (le nom du bien), jamais son adresse -- address_complement
  // était déjà sélectionné mais jamais lu dans l'objet retourné avant ce
  // ménage, colonne morte retirée au passage.
  const row = lease as unknown as {
    organization_id: string;
    tenant_account_id: string;
    organizations: { name: string; address: string | null; phone: string | null; email: string | null } | null;
    properties: { name: string } | null;
  };

  const { data: tenant } = await supabase
    .from("tenant_accounts")
    .select("full_name")
    .eq("id", row.tenant_account_id)
    .maybeSingle();

  const { data: schedules, error: scheduleError } = await supabase
    .from("payment_schedules")
    .select("id, period_start_date, period_end_date, due_date, amount_due")
    .eq("lease_id", leaseId)
    .neq("status", "annulee")
    .in("id", scheduleIds);

  if (scheduleError) throw scheduleError;
  if (!schedules || schedules.length !== scheduleIds.length) return null;

  return {
    organizationId: row.organization_id,
    organization: row.organizations ?? { name: "—", address: null, phone: null, email: null },
    tenantName: tenant?.full_name ?? "—",
    propertyLabel: row.properties?.name ?? "—",
    lineItems: schedules.map((s) => ({
      id: s.id,
      periodStart: s.period_start_date,
      periodEnd: s.period_end_date,
      dueDate: s.due_date,
      amountDue: s.amount_due,
    })),
  };
}

export type CreateScheduleInvoiceInput = {
  id: string;
  organization_id: string;
  lease_id: string;
  storage_path: string;
  generated_by: string;
};

// id fourni explicitement (généré côté action AVANT le rendu, voir
// actions/schedule-invoices.ts) plutôt que laissé au défaut gen_random_uuid() :
// le chemin de stockage {organization_id}/{invoice_id}/{uuid}.pdf (voir
// migration Module 9) doit connaître l'id de la facture avant l'upload, et
// la policy de lecture Storage compare justement ce segment à
// schedule_invoices.id.
export async function createScheduleInvoiceRecord(input: CreateScheduleInvoiceInput) {
  const supabase = await createClient();
  return supabase.from("schedule_invoices").insert(input).select().single();
}

export async function addScheduleInvoiceLineItems(
  organizationId: string,
  invoiceId: string,
  paymentScheduleIds: string[]
) {
  const supabase = await createClient();
  return supabase.from("invoice_schedule_items").insert(
    paymentScheduleIds.map((paymentScheduleId) => ({
      organization_id: organizationId,
      invoice_id: invoiceId,
      payment_schedule_id: paymentScheduleId,
    }))
  );
}
