import { getTranslations } from "next-intl/server";
import { redirect, Link } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentStaffRole } from "@/data/session";
import { getMonthRentSchedules, summarizeMonthRentSchedules } from "@/data/rent-collection";
import { getLatestConfirmedPaymentsForSchedules } from "@/data/payments";
import { getOrGeneratePaymentReceiptUrlAction } from "@/actions/payment-receipts";
import { formatDate } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import { StatTile } from "@/components/dashboard/stat-tile";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

// Fidèle à la maquette design/Clarisse V5 - Espace Agence.dc.html (écran
// "Loyers & paiements", isRents) : tuiles KPI + tableau, pour le mois
// calendaire en cours uniquement (voir data/rent-collection.ts). Statut
// "Annoncé" et action "Confirmer" volontairement absents -- aucune
// déclaration de paiement locataire n'existe dans le modèle actuel
// (payments.status='en_attente' n'est jamais produit par le code, voir
// diagnostic validé), fonctionnalité à concevoir séparément.
const ROW_STATUSES = ["en_retard", "partiellement_payee", "payee"] as const;
type RowStatus = (typeof ROW_STATUSES)[number];

const STATUS_BADGE_VARIANT: Record<RowStatus, "danger" | "warning" | "success"> = {
  en_retard: "danger",
  partiellement_payee: "warning",
  payee: "success",
};
const STATUS_LABEL_KEY: Record<RowStatus, string> = {
  en_retard: "statusEnRetard",
  partiellement_payee: "statusPartiellementPayee",
  payee: "statusPayee",
};
const METHOD_KEY: Record<string, string> = {
  mobile_money: "methodMobileMoney",
  carte: "methodCarte",
  especes: "methodEspeces",
  virement: "methodVirement",
};

function isRowStatus(status: string): status is RowStatus {
  return (ROW_STATUSES as readonly string[]).includes(status);
}

export default async function DashboardRentsPage({
  params,
}: PageProps<"/[locale]/dashboard/loyers">) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) {
    redirect({ href: "/login", locale });
    return null;
  }

  const role = await getCurrentStaffRole();
  if (role === "agent") {
    redirect({ href: "/dashboard", locale });
    return null;
  }

  const schedules = await getMonthRentSchedules(profile.organization_id);
  const summary = summarizeMonthRentSchedules(schedules);
  const rows = schedules.filter((s) => isRowStatus(s.effective_status));
  const payeeIds = rows.filter((s) => s.effective_status === "payee").map((s) => s.id);
  const paymentBySchedule = await getLatestConfirmedPaymentsForSchedules(payeeIds);

  const t = await getTranslations("dashboard");
  const tp = await getTranslations("payments");
  const tsched = await getTranslations("schedules");

  const monthLabel = new Intl.DateTimeFormat(locale, { month: "long", year: "numeric" }).format(new Date());
  const outstandingMeta = [
    summary.overdueCount > 0 ? t("rentsOverdueCount", { count: summary.overdueCount }) : null,
    summary.partialCount > 0 ? t("rentsPartialCount", { count: summary.partialCount }) : null,
  ]
    .filter((part): part is string => part !== null)
    .join(" · ");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("rentsPageTitle")}</h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">
          {t("rentsPageSubtitle", { month: monthLabel, rate: summary.collectedRate })}
        </p>
      </div>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <StatTile label={t("rentsBilled")} value={formatCurrency(summary.billedAmount, locale)} />
        <StatTile
          label={t("rentsCollected")}
          value={formatCurrency(summary.collectedAmount, locale)}
          valueClassName="text-status-success-fg"
          progress={summary.collectedRate}
        />
        <StatTile
          label={t("rentsOutstanding")}
          value={formatCurrency(summary.monthOutstandingAmount, locale)}
          valueClassName="text-status-danger-fg"
          meta={outstandingMeta || undefined}
        />
      </div>

      {rows.length === 0 ? (
        <Card className="p-0">
          <p className="px-[22px] py-6 text-sm text-muted-foreground">{t("rentsEmpty")}</p>
        </Card>
      ) : (
        <Card className="overflow-auto p-0">
          <div className="grid min-w-[860px] grid-cols-[1.3fr_1.4fr_1fr_1fr_1.1fr_0.9fr] gap-4 px-[22px] py-[13px] text-[11.5px] font-semibold tracking-[0.06em] text-muted-foreground uppercase">
            <div>{t("rentsColTenant")}</div>
            <div>{t("rentsColProperty")}</div>
            <div className="text-right">{t("rentsColAmount")}</div>
            <div>{t("rentsColDueDate")}</div>
            <div>{t("rentsColStatus")}</div>
            <div className="text-right">{t("rentsColAction")}</div>
          </div>
          <div className="flex flex-col">
            {rows.map((row) => {
              const status = row.effective_status as RowStatus;
              const payment = paymentBySchedule.get(row.id);
              return (
                <div
                  key={row.id}
                  className="grid min-w-[860px] grid-cols-[1.3fr_1.4fr_1fr_1fr_1.1fr_0.9fr] items-center gap-4 border-t border-[#f2f2f4] px-[22px] py-[13px] text-[13.5px] hover:bg-[#fafafa]"
                >
                  <div className="font-semibold tracking-[-0.01em]">
                    {row.tenant_full_name ?? row.property_name}
                  </div>
                  <div className="text-muted-foreground">{row.property_name}</div>
                  <div className="text-right font-semibold tabular-nums">
                    {formatCurrency(row.amount_due, locale)}
                  </div>
                  <div className="text-[12.5px] text-muted-foreground">{formatDate(row.due_date, locale)}</div>
                  <div>
                    <Badge variant={STATUS_BADGE_VARIANT[status]}>{tsched(STATUS_LABEL_KEY[status])}</Badge>
                    {status === "partiellement_payee" ? (
                      <div className="mt-[3px] text-[11.5px] text-muted-foreground">
                        {t("rentsReceivedMeta", { amount: formatCurrency(row.covered_amount, locale) })}
                      </div>
                    ) : null}
                    {status === "payee" && payment ? (
                      <div className="mt-[3px] text-[11.5px] text-muted-foreground">
                        {tp(METHOD_KEY[payment.method] ?? "methodEspeces")}
                      </div>
                    ) : null}
                  </div>
                  <div className="text-right">
                    {status === "en_retard" ? (
                      <Button
                        variant="outline"
                        size="sm"
                        render={
                          row.tenant_phone ? (
                            <a href={`tel:${row.tenant_phone}`} />
                          ) : (
                            <Link href={`/leases/${row.lease_id}`} />
                          )
                        }
                        nativeButton={false}
                      >
                        {t("relanceAction")}
                      </Button>
                    ) : status === "partiellement_payee" ? (
                      <Button
                        variant="outline"
                        size="sm"
                        render={<Link href={`/leases/${row.lease_id}`} />}
                        nativeButton={false}
                      >
                        {t("viewDetails")}
                      </Button>
                    ) : payment ? (
                      <DocumentDownloadButton
                        action={getOrGeneratePaymentReceiptUrlAction.bind(null, payment.paymentId)}
                        label={t("actionQuittance")}
                        pendingLabel={tp("generatingReceipt")}
                      />
                    ) : null}
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </div>
  );
}
