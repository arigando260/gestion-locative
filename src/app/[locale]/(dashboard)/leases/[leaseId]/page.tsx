import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getProperty } from "@/data/properties";
import { getOrganization } from "@/data/organizations";
import {
  getSchedulesForLease,
  getLeaseScheduleCoverage,
  scheduleCoverageThresholdDate,
  generateSchedulesForLease,
  hasRoomToGrowSchedules,
} from "@/data/schedules";
import { getPaymentsForLease } from "@/data/payments";
import { getScheduleInvoicesForLease } from "@/data/schedule-invoices";
import { getDepositBalancesForLease, getLeaseDepositBalancesWithRemainder } from "@/data/deposits";
import { getLeaseActivationReadiness, getLeaseContractByLeaseId } from "@/data/lease-contracts";
import { getOrGenerateLeaseContractUrlAction } from "@/actions/lease-contracts";
import { getInspection } from "@/data/inspections";
import {
  getLeaseClosureStatus,
  isLeaseClosureEngaged,
  leaseEndApproachingThresholdDate,
} from "@/data/lease-closure";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { ScheduleTable } from "@/components/leases/schedule-table";
import { GenerateSchedulesForm } from "@/components/leases/generate-schedules-form";
import { PaymentForm } from "@/components/leases/payment-form";
import { PaymentHistoryTable } from "@/components/leases/payment-history-table";
import { TenantCaptureToggle } from "@/components/leases/tenant-capture-toggle";
import { LeaseActivationPanel } from "@/components/leases/lease-activation-panel";
import { LeaseLifecycleBanner } from "@/components/leases/lease-lifecycle-banner";
import { LeaseSpecialTermsForm } from "@/components/leases/lease-special-terms-form";
import { DeleteLeaseButton } from "@/components/leases/delete-lease-button";
import { InvoiceGenerateForm } from "@/components/billing/invoice-generate-form";
import { InvoiceList } from "@/components/billing/invoice-list";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";

// Même idiome que schedule-table.tsx (Module 5) : Record<string, ...> avec
// fallback ?? plutôt qu'un type littéral — lease.status reste "string" côté
// génération de types (non régénérée), même remarque que partout ailleurs
// dans ce module.
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

export default async function LeasePage({
  params,
}: PageProps<"/[locale]/leases/[leaseId]">) {
  const { leaseId } = await params;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  // Extension silencieuse de la couverture d'échéances (Module 5c) : best-
  // effort, avant le rendu, jamais bloquant — le bouton manuel "Générer les
  // échéances" reste disponible en secours si cet appel échoue.
  if (lease.status === "actif") {
    const coverage = await getLeaseScheduleCoverage(lease.id);
    if (coverage) {
      const threshold = scheduleCoverageThresholdDate();
      const lowCoverage =
        coverage.coverage_end_date === null ||
        coverage.coverage_end_date < threshold;
      if (hasRoomToGrowSchedules(lease.end_date, coverage.coverage_end_date) && lowCoverage) {
        try {
          await generateSchedulesForLease(lease.id);
        } catch {
          // Best-effort, voir commentaire ci-dessus.
        }
      }
    }
  }

  const [
    property,
    organization,
    schedules,
    payments,
    invoices,
    permissions,
    activationReadiness,
    depositBalances,
    closureStatus,
    leaseContract,
    depositRefundBalances,
  ] = await Promise.all([
    getProperty(lease.property_id),
    getOrganization(lease.organization_id),
    getSchedulesForLease(leaseId),
    getPaymentsForLease(leaseId),
    getScheduleInvoicesForLease(leaseId),
    getCurrentUserPermissions(),
    lease.status === "brouillon" ? getLeaseActivationReadiness(leaseId) : Promise.resolve(null),
    lease.status === "brouillon" ? getDepositBalancesForLease(leaseId) : Promise.resolve([]),
    lease.status === "actif" || lease.status === "resilie" ? getLeaseClosureStatus(leaseId) : Promise.resolve(null),
    lease.status !== "brouillon" ? getLeaseContractByLeaseId(leaseId) : Promise.resolve(null),
    // leases_closure_status (closureStatus ci-dessus) filtre déjà status
    // in ('actif','resilie') côté vue : un bail 'termine' n'y apparaît
    // jamais, lecture séparée pour ce cas précis.
    lease.status === "termine" ? getLeaseDepositBalancesWithRemainder(leaseId) : Promise.resolve([]),
  ]);

  // Séquentiel, dépend du résultat ci-dessus (id de l'état des lieux) —
  // uniquement pertinent quand le bandeau "prêt à clôturer" va s'afficher.
  const exitInspectionValidationStatus = closureStatus?.latest_finalized_exit_inspection_id
    ? ((await getInspection(closureStatus.latest_finalized_exit_inspection_id))?.effective_validation_status ?? null)
    : null;

  const t = await getTranslations("leases");
  const ts = await getTranslations("schedules");
  const tp = await getTranslations("payments");
  const ti = await getTranslations("inspections");
  const td = await getTranslations("deposits");
  const tb = await getTranslations("billing");

  // Le nouveau cas "solde de caution à rembourser" affiche des montants de
  // caution : gate sur leases:update ET deposit_ledger:read. Les cas
  // préexistants (actif/résilié) restent gatés sur leases:update seul,
  // inchangé — aucun rapport avec des montants de caution, pas de
  // nouvelle permission à leur imposer.
  const canSeeDepositRefund = can(permissions, "deposit_ledger", "read");
  const visibleDepositRefundBalances = canSeeDepositRefund ? depositRefundBalances : [];
  const showLifecycleBanner =
    (closureStatus !== null || visibleDepositRefundBalances.length > 0) &&
    can(permissions, "leases", "update");

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
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>
            {property ? `${t("summaryTitle")} — ${property.name}` : t("summaryTitle")}
          </CardTitle>
          <Badge variant={STATUS_VARIANT[lease.status] ?? "secondary"}>
            {t(STATUS_KEY[lease.status] ?? "statusBrouillon")}
          </Badge>
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

      {lease.status === "brouillon" && (
        <LeaseActivationPanel
          leaseId={lease.id}
          lease={lease}
          readiness={activationReadiness}
          balances={depositBalances}
          canGenerate={can(permissions, "lease_contracts", "create")}
        />
      )}

      {lease.status === "brouillon" && can(permissions, "leases", "delete") && (
        <DeleteLeaseButton leaseId={lease.id} propertyId={lease.property_id} />
      )}

      {lease.status !== "brouillon" && leaseContract && (
        <DocumentDownloadButton
          action={getOrGenerateLeaseContractUrlAction.bind(null, lease.id)}
          label={t("viewContract")}
          pendingLabel={t("generatingContract")}
        />
      )}

      {showLifecycleBanner && (
        <LeaseLifecycleBanner
          leaseId={lease.id}
          closureReferenceDate={closureStatus?.closure_reference_date ?? null}
          closureEngaged={closureStatus ? isLeaseClosureEngaged(closureStatus) : false}
          entryInspectionDone={closureStatus?.entry_inspection_done ?? false}
          endDateApproaching={
            closureStatus?.lease_end_date !== null &&
            closureStatus?.lease_end_date !== undefined &&
            closureStatus.lease_end_date <= leaseEndApproachingThresholdDate()
          }
          endDate={closureStatus?.lease_end_date ?? null}
          keysReturnedAt={closureStatus?.keys_returned_at ?? null}
          exitInspectionDueDate={closureStatus?.exit_inspection_due_date ?? null}
          exitInspectionDone={closureStatus?.exit_inspection_done ?? false}
          exitInspectionValidationStatus={exitInspectionValidationStatus}
          depositRefundBalances={visibleDepositRefundBalances}
        />
      )}

      {can(permissions, "leases", "update") && organization && (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle className="text-base">{t("tenantCaptureLabel")}</CardTitle>
          </CardHeader>
          <CardContent>
            <TenantCaptureToggle
              leaseId={lease.id}
              leaseValue={lease.tenant_capture_enabled}
              organizationDefault={organization.tenant_capture_enabled}
            />
          </CardContent>
        </Card>
      )}

      {can(permissions, "leases", "update") && (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle className="text-base">{t("specialTermsLabel")}</CardTitle>
          </CardHeader>
          <CardContent>
            <LeaseSpecialTermsForm leaseId={lease.id} specialTerms={lease.special_terms} />
          </CardContent>
        </Card>
      )}

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
        <PaymentHistoryTable payments={payments} variant="staff" />
      </div>

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{tb("invoicesTitle")}</h2>
        {can(permissions, "schedule_invoices", "create") && (
          <InvoiceGenerateForm leaseId={lease.id} schedules={schedules} />
        )}
        <InvoiceList invoices={invoices} />
      </div>
    </div>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
