import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions } from "@/data/permissions";
import { getDashboardAlerts, type DashboardAlert } from "@/data/dashboard-alerts";
import { formatDate } from "@/lib/format-date";
import { Link } from "@/i18n/navigation";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function DashboardPage({
  params,
}: PageProps<"/[locale]/dashboard">) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) {
    redirect({ href: "/login", locale });
    return null;
  }

  const supabase = await createClient();
  const [{ data: organization }, permissions] = await Promise.all([
    supabase
      .from("organizations")
      .select("name")
      .eq("id", profile.organization_id)
      .single(),
    getCurrentUserPermissions(),
  ]);

  // Source unique du bloc d'alertes (Module 10) — chaque nouvelle catégorie
  // s'ajoute dans data/dashboard-alerts.ts, jamais en dupliquant un fetch de
  // plus ici. Cette page ne fait que grouper par "kind" pour l'affichage.
  const alerts = await getDashboardAlerts(profile.organization_id, permissions);
  const lowCoverage = alerts.filter(
    (a): a is Extract<DashboardAlert, { kind: "low_coverage" }> => a.kind === "low_coverage"
  );
  const entryInspectionNeeded = alerts.filter(
    (a): a is Extract<DashboardAlert, { kind: "entry_inspection_needed" }> =>
      a.kind === "entry_inspection_needed"
  );
  const endApproaching = alerts.filter(
    (a): a is Extract<DashboardAlert, { kind: "lease_end_approaching" }> =>
      a.kind === "lease_end_approaching"
  );
  const closurePending = alerts.filter(
    (a): a is Extract<DashboardAlert, { kind: "lease_closure_pending" }> =>
      a.kind === "lease_closure_pending"
  );
  const depositRefundPending = alerts.filter(
    (a): a is Extract<DashboardAlert, { kind: "deposit_refund_pending" }> =>
      a.kind === "deposit_refund_pending"
  );

  const t = await getTranslations("nav");
  const tp = await getTranslations("properties");
  const td = await getTranslations("dashboard");
  // Mêmes clés que components/leases/deposit-balance-cards.tsx /
  // lease-lifecycle-banner.tsx — pas de nouveau libellé par type.
  const tdep = await getTranslations("deposits");
  const DEPOSIT_TYPE_KEY: Record<string, string> = {
    avance_garantie: "typeAvanceGarantie",
    caution_utilities: "typeCautionUtilities",
  };

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      {lowCoverage.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("lowCoverageTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {lowCoverage.map((alert) => (
              <Link
                key={alert.leaseId}
                href={`/leases/${alert.leaseId}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {alert.propertyName} — {alert.tenantName}
                </span>
                <span className="text-muted-foreground">
                  {alert.coverageEndDate
                    ? td("lowCoverageUntil", { date: formatDate(alert.coverageEndDate, locale) })
                    : td("lowCoverageNoSchedule")}
                </span>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {entryInspectionNeeded.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("entryInspectionNeededTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {entryInspectionNeeded.map((alert) => (
              <Link
                key={alert.leaseId}
                href={`/leases/${alert.leaseId}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {alert.propertyName} — {alert.tenantName}
                </span>
                <span className="text-muted-foreground">{td("entryInspectionNeeded")}</span>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {endApproaching.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("upcomingEndDateTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {endApproaching.map((alert) => (
              <Link
                key={alert.leaseId}
                href={`/leases/${alert.leaseId}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {alert.propertyName} — {alert.tenantName}
                </span>
                <span className="text-muted-foreground">
                  {td("upcomingEndDateUntil", { date: formatDate(alert.endDate, locale) })}
                </span>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {closurePending.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("closurePendingTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {closurePending.map((alert) => (
              <Link
                key={alert.leaseId}
                href={`/leases/${alert.leaseId}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {alert.propertyName} — {alert.tenantName}
                </span>
                <span className="text-muted-foreground">
                  {alert.subKind === "keys_needed" && td("closurePendingKeysNeeded")}
                  {alert.subKind === "inspection_needed" &&
                    td("closurePendingInspectionNeeded", { date: formatDate(alert.dueDate, locale) })}
                  {alert.subKind === "ready" && td("closurePendingReady")}
                </span>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      {depositRefundPending.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("depositRefundPendingTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {depositRefundPending.map((alert) => (
              <Link
                key={alert.leaseId}
                href={`/leases/${alert.leaseId}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {alert.propertyName} — {alert.tenantName}
                </span>
                {alert.balances.map((b) => (
                  <span key={b.depositType} className="text-muted-foreground">
                    {tdep(DEPOSIT_TYPE_KEY[b.depositType] ?? "typeAvanceGarantie")}: {b.balance}
                  </span>
                ))}
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>{organization?.name}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm text-muted-foreground">
          <p>{profile.full_name ?? profile.email}</p>
        </CardContent>
      </Card>
      {/* @base-ui/react utilise "render" (élément à fusionner), pas "asChild"
          comme Radix — c'est la convention à suivre partout dans ce projet
          pour rendre un Button/Link polymorphe. */}
      <Button className="w-fit" render={<Link href="/properties" />} nativeButton={false}>
        {t("properties")} — {tp("title")}
      </Button>
    </div>
  );
}
