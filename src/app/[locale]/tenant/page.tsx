import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLeases } from "@/data/leases";
import { getTenantNextAction } from "@/data/tenant-next-action";
import { getSchedulesForLease } from "@/data/schedules";
import { getPaymentsForLease } from "@/data/payments";
import { getLeaseContractByLeaseId } from "@/data/lease-contracts";
import { getMyMaintenanceTickets } from "@/data/maintenance";
import { formatDate } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { LEASE_STATUS_KEY } from "@/components/tenant/lease-list";
import { NextActionCard } from "@/components/tenant/next-action-card";
import { InfoCard } from "@/components/tenant/info-card";

export default async function TenantHomePage({ params }: PageProps<"/[locale]/tenant">) {
  const { locale } = await params;
  const leases = await getMyLeases();
  const t = await getTranslations("tenant");
  const tl = await getTranslations("leases");

  if (leases.length === 0) {
    return (
      <div className="flex flex-col gap-6">
        <h1 className="text-xl font-semibold">{t("homeTitle")}</h1>
        <p className="text-sm text-muted-foreground">{t("noLeases")}</p>
      </div>
    );
  }

  const activeLeases = leases.filter((l) => l.status === "actif");

  // Plusieurs baux actifs : liste "Mes logements", pas de sélecteur global —
  // chaque carte renvoie vers la fiche existante (/tenant/leases/[leaseId]),
  // aucune agrégation cross-bail (voir design/CLAUDE.md : soldes toujours
  // par bail).
  if (activeLeases.length > 1) {
    return (
      <div className="flex flex-col gap-6">
        <div>
          <h1 className="text-xl font-bold tracking-tight">{t("overviewTitle")}</h1>
          <p className="mt-1 text-[13px] text-muted-foreground">
            {t("overviewSubtitle", { count: activeLeases.length })}
          </p>
        </div>
        <div className="flex flex-col gap-3">
          {activeLeases.map((lease) => (
            <Card key={lease.id} className="gap-2 border-l-[3px] border-l-primary p-5">
              <div className="text-[16px] font-bold">{lease.properties?.name ?? "—"}</div>
              <div className="text-[13px] text-muted-foreground">
                {lease.properties?.address_complement ?? ""}
              </div>
              <div className="mt-1 flex gap-2">
                <Badge variant="secondary">{tl(LEASE_STATUS_KEY[lease.status] ?? "statusBrouillon")}</Badge>
              </div>
              <Button
                className="mt-2 w-fit"
                size="sm"
                variant="outline"
                render={<Link href={`/tenant/leases/${lease.id}`} />}
                nativeButton={false}
              >
                {t("open")}
              </Button>
            </Card>
          ))}
        </div>
        <p className="text-[12px] text-muted-foreground">{t("perLeaseNote")}</p>
      </div>
    );
  }

  const lease = activeLeases[0] ?? leases[0];

  const [nextAction, schedules, payments, contract, tickets] = await Promise.all([
    getTenantNextAction(lease),
    getSchedulesForLease(lease.id),
    getPaymentsForLease(lease.id),
    getLeaseContractByLeaseId(lease.id),
    getMyMaintenanceTickets(),
  ]);

  const hasOverdue = schedules.some((s) => s.effective_status === "en_retard");
  const leaseTicketsCount = tickets.filter((tk) => tk.lease_id === lease.id).length;
  const lastPayment = payments[0];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">{t("homeTitle")}</h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">{t("homeSubtitle")}</p>
      </div>

      <Card className="gap-2 p-5">
        <div className="text-[11.5px] font-semibold tracking-[0.06em] text-muted-foreground uppercase">
          {t("infoMyLease")}
        </div>
        <div className="text-[19px] font-bold">{lease.properties?.name ?? "—"}</div>
        <div className="text-[13px] text-muted-foreground">
          {lease.properties?.address_complement ?? ""}
        </div>
        <div className="mt-1 flex gap-2">
          <Badge variant="secondary">{tl(LEASE_STATUS_KEY[lease.status] ?? "statusBrouillon")}</Badge>
          <Badge variant={hasOverdue ? "danger" : "success"}>
            {hasOverdue ? t("paymentLate") : t("paymentUpToDate")}
          </Badge>
        </div>
      </Card>

      <NextActionCard action={nextAction} t={t} locale={locale} />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <InfoCard
          label={t("infoLastPayment")}
          value={lastPayment ? formatCurrency(lastPayment.amount, locale) : t("infoLastPaymentEmpty")}
          meta={lastPayment ? formatDate(lastPayment.payment_date, locale) : undefined}
          href={`/tenant/leases/${lease.id}`}
        />
        <InfoCard
          label={t("infoIssues")}
          value={t("infoIssuesCount", { count: leaseTicketsCount })}
          href="/tenant/maintenance"
        />
        <InfoCard
          label={t("infoDocuments")}
          value={contract ? t("infoDocumentsValue") : t("infoDocumentsEmpty")}
          href={`/tenant/leases/${lease.id}`}
        />
        <InfoCard
          label={t("infoMyLease")}
          value={tl(LEASE_STATUS_KEY[lease.status] ?? "statusBrouillon")}
          href={`/tenant/leases/${lease.id}`}
        />
      </div>
    </div>
  );
}
