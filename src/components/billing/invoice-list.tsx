import { getTranslations } from "next-intl/server";
import { Card, CardContent } from "@/components/ui/card";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { getSignedScheduleInvoiceUrlAction } from "@/actions/schedule-invoices";
import type { ScheduleInvoice } from "@/data/schedule-invoices";

// Partagée staff/locataire (comme PaymentHistoryTable) : aucune génération
// possible ici dans les deux cas, storage_path est toujours déjà renseigné
// (schedule_invoices, Module 9) — une seule Server Action de téléchargement
// suffit, la policy Storage tranche seule qui peut effectivement récupérer
// le fichier.
export async function InvoiceList({ invoices }: { invoices: ScheduleInvoice[] }) {
  const t = await getTranslations("billing");

  if (invoices.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("noInvoices")}</p>;
  }

  return (
    <div className="flex flex-col gap-2">
      {invoices.map((invoice) => (
        <Card key={invoice.id}>
          <CardContent className="flex items-center justify-between gap-2">
            <span className="text-sm text-muted-foreground">
              {t("invoiceGeneratedOn")}: {invoice.generated_at.slice(0, 16).replace("T", " ")}
            </span>
            <DocumentDownloadButton
              action={getSignedScheduleInvoiceUrlAction.bind(null, invoice.storage_path)}
              label={t("downloadInvoice")}
              pendingLabel={t("preparingDownload")}
            />
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
