"use server";

import { randomUUID } from "node:crypto";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import {
  getPaymentReceiptByPaymentId,
  getPaymentReceiptRenderData,
  markPaymentReceiptGenerated,
  getSignedPaymentReceiptUrl,
} from "@/data/payment-receipts";
import { createClient } from "@/lib/supabase/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { ReceiptDocument } from "@/lib/pdf/receipt-document";
import { getTranslations } from "next-intl/server";

export type DocumentUrlResult = { success: boolean; message?: string; url?: string };

const METHOD_LABEL_KEY: Record<string, string> = {
  mobile_money: "methodMobileMoney",
  carte: "methodCarte",
  especes: "methodEspeces",
  virement: "methodVirement",
};

// Staff uniquement : vérifie storage_path, génère à la volée si absent
// (conception validée — le reçu est déjà "dû" dès la confirmation du
// paiement via le trigger ensure_payment_receipt_pending côté base, voir
// Module 9), sinon sert directement l'URL signée existante. Jamais appelée
// côté locataire (voir getTenantPaymentReceiptUrlAction ci-dessous), qui ne
// génère jamais.
export async function getOrGeneratePaymentReceiptUrlAction(
  paymentId: string
): Promise<DocumentUrlResult> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const receipt = await getPaymentReceiptByPaymentId(paymentId);
  if (!receipt) {
    return { success: false, message: "Reçu introuvable pour ce paiement." };
  }

  if (receipt.storage_path) {
    try {
      const url = await getSignedPaymentReceiptUrl(receipt.storage_path);
      return { success: true, url };
    } catch {
      return { success: false, message: "Impossible de générer le lien de téléchargement." };
    }
  }

  const renderData = await getPaymentReceiptRenderData(paymentId);
  if (!renderData) {
    return { success: false, message: "Paiement introuvable." };
  }

  const t = await getTranslations("payments");
  const buffer = await renderToBuffer(
    <ReceiptDocument
      data={{
        organization: renderData.organization,
        tenantName: renderData.tenantName,
        amount: String(renderData.amount),
        paymentDate: renderData.paymentDate,
        methodLabel: t(METHOD_LABEL_KEY[renderData.method] ?? "methodEspeces"),
        scheduleReference:
          renderData.schedulePeriodStart && renderData.schedulePeriodEnd
            ? `${renderData.schedulePeriodStart} → ${renderData.schedulePeriodEnd}`
            : "—",
        receiptReference: renderData.receiptId,
      }}
    />
  );

  const storagePath = `${profile.organization_id}/${paymentId}/${randomUUID()}.pdf`;
  const supabase = await createClient();
  const { error: uploadError } = await supabase.storage
    .from("payment-receipts")
    .upload(storagePath, buffer, { contentType: "application/pdf" });

  // Erreur Storage, pas Postgrest : lib/errors.ts (toUserMessage) attend un
  // objet {code, message} au sens Postgres/PostgREST, une erreur Storage a
  // une forme différente — message générique dédié plutôt que de la faire
  // transiter par ce traducteur.
  if (uploadError) {
    return { success: false, message: "Échec de la génération du reçu. Réessayez." };
  }

  const { error: markError } = await markPaymentReceiptGenerated(paymentId, storagePath);
  if (markError) {
    return { success: false, message: "Échec de l'enregistrement du reçu. Réessayez." };
  }

  try {
    const url = await getSignedPaymentReceiptUrl(storagePath);
    return { success: true, url };
  } catch {
    return { success: false, message: "Impossible de générer le lien de téléchargement." };
  }
}

// Locataire uniquement : jamais de génération, uniquement servir l'URL
// signée d'un reçu déjà généré. RLS (payment_receipts_select, Module 9)
// scope déjà la visibilité au(x) bail(s)/réservation(s) du locataire
// courant.
export async function getTenantPaymentReceiptUrlAction(
  paymentId: string
): Promise<DocumentUrlResult> {
  const tenant = await getCurrentTenant();
  if (!tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const receipt = await getPaymentReceiptByPaymentId(paymentId);
  if (!receipt || !receipt.storage_path) {
    const t = await getTranslations("payments");
    return { success: false, message: t("receiptNotReady") };
  }

  try {
    const url = await getSignedPaymentReceiptUrl(receipt.storage_path);
    return { success: true, url };
  } catch {
    return { success: false, message: "Impossible de générer le lien de téléchargement." };
  }
}
