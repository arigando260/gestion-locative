import { getTranslations, getLocale } from "next-intl/server";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { formatDate, formatDateTime } from "@/lib/format-date";
import {
  getOrGeneratePaymentReceiptUrlAction,
  getTenantPaymentReceiptUrlAction,
} from "@/actions/payment-receipts";
import type { Payment } from "@/data/payments";
import type { PaymentReceipt } from "@/data/payment-receipts";

const METHOD_KEY: Record<string, string> = {
  mobile_money: "methodMobileMoney",
  carte: "methodCarte",
  especes: "methodEspeces",
  virement: "methodVirement",
};

// Partagée staff/locataire (comme ScheduleTable) : seule la variante change
// quelle Server Action le bouton reçu appelle — génère à la volée si besoin
// côté staff (getOrGeneratePaymentReceiptUrlAction), jamais côté locataire
// (getTenantPaymentReceiptUrlAction, Module 9). Rendue serveur malgré le
// bouton interactif : seul DocumentDownloadButton est un composant client,
// même principe que SubmitButton dans le reste du projet.
export async function PaymentHistoryTable({
  payments,
  receipts,
  variant,
}: {
  payments: Payment[];
  // Voir data/payment-receipts.ts getPaymentReceiptsForPayments — une ligne
  // existe dès la confirmation du paiement (trigger ensure_payment_receipt_
  // pending, Module 9), mais generated_at reste NULL tant que personne n'a
  // téléchargé le reçu au moins une fois.
  receipts: PaymentReceipt[];
  variant: "staff" | "tenant";
}) {
  const t = await getTranslations("payments");
  const locale = await getLocale();

  if (payments.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const receiptByPaymentId = new Map(receipts.map((receipt) => [receipt.payment_id, receipt]));

  const receiptButton = (payment: Payment) => {
    if (payment.status !== "confirme") return null;
    const action =
      variant === "staff"
        ? getOrGeneratePaymentReceiptUrlAction.bind(null, payment.id)
        : getTenantPaymentReceiptUrlAction.bind(null, payment.id);
    const generatedAt = receiptByPaymentId.get(payment.id)?.generated_at ?? null;
    return (
      <div className="flex flex-col items-start gap-1">
        <DocumentDownloadButton
          action={action}
          label={t("downloadReceipt")}
          pendingLabel={t("generatingReceipt")}
        />
        {generatedAt && (
          <span className="text-xs text-muted-foreground">
            {t("receiptGeneratedOn", { date: formatDateTime(generatedAt, locale) })}
          </span>
        )}
      </div>
    );
  };

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("paymentDate")}</TableHead>
              <TableHead>{t("amount")}</TableHead>
              <TableHead>{t("method")}</TableHead>
              <TableHead>{t("reference")}</TableHead>
              <TableHead>{t("receipt")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {payments.map((payment) => (
              <TableRow key={payment.id}>
                <TableCell>{formatDate(payment.payment_date, locale)}</TableCell>
                <TableCell>{payment.amount}</TableCell>
                <TableCell>{t(METHOD_KEY[payment.method] ?? "methodEspeces")}</TableCell>
                <TableCell>{payment.external_reference ?? "—"}</TableCell>
                <TableCell>{receiptButton(payment)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {payments.map((payment) => (
          <Card key={payment.id}>
            <CardContent className="flex flex-col gap-1">
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium">{payment.amount}</span>
                <span className="text-sm text-muted-foreground">{formatDate(payment.payment_date, locale)}</span>
              </div>
              <span className="text-sm text-muted-foreground">
                {t(METHOD_KEY[payment.method] ?? "methodEspeces")}
              </span>
              {receiptButton(payment)}
            </CardContent>
          </Card>
        ))}
      </div>
    </>
  );
}
