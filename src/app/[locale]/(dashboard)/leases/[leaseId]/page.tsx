import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getProperty } from "@/data/properties";
import { getSchedulesForLease } from "@/data/schedules";
import { getPaymentsForLease } from "@/data/payments";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { ScheduleTable } from "@/components/leases/schedule-table";
import { GenerateSchedulesForm } from "@/components/leases/generate-schedules-form";
import { PaymentForm } from "@/components/leases/payment-form";
import { PaymentHistoryTable } from "@/components/leases/payment-history-table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

export default async function LeasePage({
  params,
}: PageProps<"/[locale]/leases/[leaseId]">) {
  const { leaseId } = await params;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const [property, schedules, payments, permissions] = await Promise.all([
    getProperty(lease.property_id),
    getSchedulesForLease(leaseId),
    getPaymentsForLease(leaseId),
    getCurrentUserPermissions(),
  ]);

  const t = await getTranslations("leases");
  const ts = await getTranslations("schedules");
  const tp = await getTranslations("payments");
  const ti = await getTranslations("inspections");
  const td = await getTranslations("deposits");

  return (
    <div className="flex flex-col gap-6">
      {property && (
        <Link
          href={`/properties/${property.id}`}
          className="text-sm text-muted-foreground hover:underline"
        >
          ← {property.name}
        </Link>
      )}

      <div className="flex flex-wrap gap-2">
        <Button
          variant="outline"
          render={<Link href={`/leases/${lease.id}/inspections`} />}
          nativeButton={false}
        >
          {ti("title")}
        </Button>
        <Button
          variant="outline"
          render={<Link href={`/leases/${lease.id}/deposits`} />}
          nativeButton={false}
        >
          {td("title")}
        </Button>
      </div>

      <Card className="max-w-md">
        <CardHeader>
          <CardTitle>{t("createTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm text-muted-foreground">
          <p>
            {t("rentAmount")}: {lease.rent_amount}
          </p>
          <p>
            {t("paymentFrequency")}: {t(`frequency${capitalize(lease.payment_frequency)}`)}
          </p>
          <p>
            {t("paymentTiming")}: {t(`timing${capitalize(lease.payment_timing)}`)}
          </p>
          <p>
            {t("startDate")}: {lease.start_date}
          </p>
        </CardContent>
      </Card>

      <div className="flex flex-col gap-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-semibold">{ts("title")}</h2>
          {can(permissions, "payment_schedules", "create") && (
            <GenerateSchedulesForm leaseId={lease.id} />
          )}
        </div>
        <ScheduleTable schedules={schedules} />
      </div>

      {can(permissions, "payments", "create") && (
        <PaymentForm leaseId={lease.id} schedules={schedules} />
      )}

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{tp("history")}</h2>
        <PaymentHistoryTable payments={payments} />
      </div>
    </div>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
