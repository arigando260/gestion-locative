import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLease } from "@/data/leases";
import { getSchedulesForLease } from "@/data/schedules";
import { getPaymentsForLease } from "@/data/payments";
import { getDepositBalancesForLease } from "@/data/deposits";
import { ScheduleTable } from "@/components/leases/schedule-table";
import { PaymentHistoryTable } from "@/components/leases/payment-history-table";
import { DepositBalanceCards } from "@/components/leases/deposit-balance-cards";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default async function TenantLeaseDetailPage({
  params,
}: PageProps<"/[locale]/tenant/leases/[leaseId]">) {
  const { leaseId } = await params;
  const lease = await getMyLease(leaseId);
  if (!lease) notFound();

  const [schedules, payments, deposits] = await Promise.all([
    getSchedulesForLease(leaseId),
    getPaymentsForLease(leaseId),
    getDepositBalancesForLease(leaseId),
  ]);

  const t = await getTranslations("leases");
  const ts = await getTranslations("schedules");
  const tp = await getTranslations("payments");
  const td = await getTranslations("deposits");
  const ti = await getTranslations("inspections");
  const tc = await getTranslations("common");

  return (
    <div className="flex flex-col gap-6">
      <Link href="/tenant" className="text-sm text-muted-foreground hover:underline">
        ← {tc("back")}
      </Link>

      <Card className="max-w-md">
        <CardHeader>
          <CardTitle>{lease.properties?.name}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm text-muted-foreground">
          <p>{lease.organizations?.name}</p>
          <p>{lease.properties?.address}</p>
          <p>
            {t("rentAmount")}: {lease.rent_amount}
          </p>
        </CardContent>
      </Card>

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
        <PaymentHistoryTable payments={payments} />
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{td("title")}</h2>
        <DepositBalanceCards balances={deposits} />
      </div>
    </div>
  );
}
