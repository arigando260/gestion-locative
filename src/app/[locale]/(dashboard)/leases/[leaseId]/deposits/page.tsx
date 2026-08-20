import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getDepositBalancesForLease, getDepositLedgerForLease } from "@/data/deposits";
import { getSchedulesForLease } from "@/data/schedules";
import { getInspectionsForLease } from "@/data/inspections";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { DepositBalanceCards } from "@/components/leases/deposit-balance-cards";
import { DepositLedgerTable } from "@/components/leases/deposit-ledger-table";
import { InitialDepositForm } from "@/components/leases/initial-deposit-form";
import { ImputationForm } from "@/components/leases/imputation-form";
import { RefundForm } from "@/components/leases/refund-form";
import { AdvanceAuthorizationToggle } from "@/components/leases/advance-authorization-toggle";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export default async function LeaseDepositsPage({
  params,
}: PageProps<"/[locale]/leases/[leaseId]/deposits">) {
  const { leaseId } = await params;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const [balances, ledger, schedules, permissions, inspections] = await Promise.all([
    getDepositBalancesForLease(leaseId),
    getDepositLedgerForLease(leaseId),
    getSchedulesForLease(leaseId),
    getCurrentUserPermissions(),
    getInspectionsForLease(leaseId),
  ]);

  const t = await getTranslations("deposits");
  const tc = await getTranslations("common");
  const canWrite = can(permissions, "deposit_ledger", "create");
  // Pas de filtre de statut de bail (contrairement à getLeaseClosureStatus/
  // entry_inspection_done, Module 10g/10k, scopé actif/resilie) : la page
  // cautions reste accessible quel que soit le statut, cette lecture doit
  // rester fiable dans tous les cas.
  const hasFinalizedEntryInspection = inspections.some(
    (i) => i.inspection_type === "entree" && i.document_status === "finalise"
  );

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/leases/${leaseId}`}
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {tc("back")}
      </Link>

      <h1 className="text-xl font-semibold">{t("title")}</h1>

      <DepositBalanceCards balances={balances} />

      {canWrite && (
        <AdvanceAuthorizationToggle
          leaseId={lease.id}
          authorized={lease.advance_consumption_authorized}
        />
      )}

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("history")}</h2>
        <DepositLedgerTable entries={ledger} />
      </div>

      {canWrite && (
        <div className="grid gap-6 sm:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">{t("recordInitialDeposit")}</CardTitle>
            </CardHeader>
            <CardContent>
              <InitialDepositForm leaseId={lease.id} lease={lease} balances={balances} />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">{t("recordImputation")}</CardTitle>
            </CardHeader>
            <CardContent>
              <ImputationForm
                leaseId={lease.id}
                schedules={schedules}
                hasFinalizedEntryInspection={hasFinalizedEntryInspection}
              />
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle className="text-base">{t("recordRefund")}</CardTitle>
            </CardHeader>
            <CardContent>
              <RefundForm leaseId={lease.id} balances={balances} />
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
