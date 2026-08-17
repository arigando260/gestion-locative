import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLease } from "@/data/leases";
import { getSchedulesForLease } from "@/data/schedules";
import { getPaymentsForLease } from "@/data/payments";
import { getDepositBalancesForLease } from "@/data/deposits";
import { getScheduleInvoicesForLease } from "@/data/schedule-invoices";
import { getLeaseActivationReadiness, getLeaseContractByLeaseId } from "@/data/lease-contracts";
import { getOrGenerateLeaseContractUrlAction } from "@/actions/lease-contracts";
import { ScheduleTable } from "@/components/leases/schedule-table";
import { PaymentHistoryTable } from "@/components/leases/payment-history-table";
import { DepositBalanceCards } from "@/components/leases/deposit-balance-cards";
import { InvoiceList } from "@/components/billing/invoice-list";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { LeaseContractApproval } from "@/components/tenant/lease-contract-approval";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

// Mêmes clés/couleurs que leases/[leaseId]/page.tsx (côté staff) — même
// namespace "leases" déjà chargé ici (t("rentAmount") plus bas), pour ne
// pas introduire une deuxième formulation du même statut.
const STATUS_KEY: Record<string, string> = {
  brouillon: "statusBrouillon",
  actif: "statusActif",
  resilie: "statusResilie",
  termine: "statusTermine",
};
const STATUS_VARIANT: Record<string, "secondary" | "default" | "destructive" | "outline"> = {
  brouillon: "secondary",
  actif: "default",
  resilie: "destructive",
  termine: "outline",
};

export default async function TenantLeaseDetailPage({
  params,
}: PageProps<"/[locale]/tenant/leases/[leaseId]">) {
  const { leaseId } = await params;
  const lease = await getMyLease(leaseId);
  if (!lease) notFound();

  const [schedules, payments, deposits, invoices, activationReadiness, leaseContract] = await Promise.all([
    getSchedulesForLease(leaseId),
    getPaymentsForLease(leaseId),
    getDepositBalancesForLease(leaseId),
    getScheduleInvoicesForLease(leaseId),
    lease.status === "brouillon" ? getLeaseActivationReadiness(leaseId) : Promise.resolve(null),
    lease.status !== "brouillon" ? getLeaseContractByLeaseId(leaseId) : Promise.resolve(null),
  ]);

  const t = await getTranslations("leases");
  const ts = await getTranslations("schedules");
  const tp = await getTranslations("payments");
  const td = await getTranslations("deposits");
  const ti = await getTranslations("inspections");
  const tb = await getTranslations("billing");
  const tc = await getTranslations("common");

  return (
    <div className="flex flex-col gap-6">
      <Link href="/tenant" className="text-sm text-muted-foreground hover:underline">
        ← {tc("back")}
      </Link>

      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>{lease.properties?.name}</CardTitle>
          <Badge variant={STATUS_VARIANT[lease.status] ?? "secondary"}>
            {t(STATUS_KEY[lease.status] ?? "statusBrouillon")}
          </Badge>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm text-muted-foreground">
          <p>{lease.organizations?.name}</p>
          <p>{lease.properties?.address}</p>
          <p>
            {t("rentAmount")}: {lease.rent_amount}
          </p>
        </CardContent>
      </Card>

      {lease.status === "brouillon" && (
        <LeaseContractApproval leaseId={lease.id} readiness={activationReadiness} />
      )}

      {lease.status !== "brouillon" && leaseContract && (
        <DocumentDownloadButton
          action={getOrGenerateLeaseContractUrlAction.bind(null, lease.id)}
          label={t("viewContract")}
          pendingLabel={t("generatingContract")}
        />
      )}

      <Button
        variant="outline"
        className="w-fit"
        render={<Link href={`/tenant/leases/${lease.id}/inspections`} />}
        nativeButton={false}
      >
        {ti("title")}
      </Button>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{ts("title")}</h2>
        <ScheduleTable schedules={schedules} />
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{tp("history")}</h2>
        <PaymentHistoryTable payments={payments} variant="tenant" />
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{tb("invoicesTitle")}</h2>
        <InvoiceList invoices={invoices} />
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{td("title")}</h2>
        <DepositBalanceCards balances={deposits} />
      </div>
    </div>
  );
}
