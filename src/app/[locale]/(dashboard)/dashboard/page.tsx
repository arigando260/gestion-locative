import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentStaffRole } from "@/data/session";
import { getCurrentUserPermissions } from "@/data/permissions";
import { getDashboardAlerts, type DashboardAlert } from "@/data/dashboard-alerts";
import { getDashboardStats } from "@/data/dashboard-stats";
import { getPropertiesWithEffectiveStatus } from "@/data/properties";
import { getOrganization } from "@/data/organizations";
import { PROPERTY_STATUS_KEY } from "@/components/properties/property-list";
import { formatDate } from "@/lib/format-date";
import { formatCompactCurrency } from "@/lib/format-currency";
import { StatTile } from "@/components/dashboard/stat-tile";
import { AlertRow } from "@/components/dashboard/alert-row";
import { AgentTodayView } from "@/components/dashboard/agent-today-view";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

type AlertRowProps = React.ComponentProps<typeof AlertRow>;

export default async function DashboardPage({
  params,
}: PageProps<"/[locale]/dashboard">) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) {
    redirect({ href: "/login", locale });
    return null;
  }

  // Écran dédié pour l'agent terrain (Espace agent, "Aujourd'hui") — admin/
  // comptable gardent le tableau de bord ci-dessous inchangé. Sidebar/layout
  // non affectés, seul ce contenu bascule.
  const role = await getCurrentStaffRole();
  if (role === "agent") {
    return (
      <AgentTodayView
        organizationId={profile.organization_id}
        profileName={profile.full_name ?? profile.email}
        locale={locale}
      />
    );
  }

  const permissions = await getCurrentUserPermissions();

  // Source unique du bloc d'alertes (Module 10) — chaque nouvelle catégorie
  // s'ajoute dans data/dashboard-alerts.ts, jamais en dupliquant un fetch de
  // plus ici. Cette page ne fait que mettre en forme ce tableau pour
  // l'affichage.
  const [alerts, stats, properties, organization] = await Promise.all([
    getDashboardAlerts(profile.organization_id, permissions),
    getDashboardStats(profile.organization_id),
    getPropertiesWithEffectiveStatus(),
    getOrganization(profile.organization_id),
  ]);
  // "Espace propriétaire" (maquette) : même vue, seule l'accroche change
  // selon organization_type -- voir (dashboard)/layout.tsx pour la même
  // logique côté tagline sidebar.
  const isOwnerOrg = organization?.organization_type === "proprietaire";

  const t = await getTranslations("dashboard");
  const tdep = await getTranslations("deposits");
  const tprop = await getTranslations("properties");
  const DEPOSIT_TYPE_KEY: Record<string, string> = {
    avance_garantie: "typeAvanceGarantie",
    caution_utilities: "typeCautionUtilities",
  };

  const parkByStatus = properties.reduce<Record<string, number>>((acc, p) => {
    acc[p.effective_status] = (acc[p.effective_status] ?? 0) + 1;
    return acc;
  }, {});

  function alertToRow(alert: DashboardAlert): AlertRowProps {
    const name = alert.tenantName ?? alert.propertyName;
    const base = {
      name,
      subtitle: alert.propertyName,
      actionLabel: t("viewDetails"),
      actionHref: `/leases/${alert.leaseId}`,
    };

    switch (alert.kind) {
      case "low_coverage":
        return {
          ...base,
          badgeLabel: t("badgeCoverage"),
          badgeVariant: "warning",
          meta: alert.coverageEndDate
            ? t("lowCoverageUntil", { date: formatDate(alert.coverageEndDate, locale) })
            : t("lowCoverageNoSchedule"),
        };
      case "entry_inspection_needed":
        return {
          ...base,
          badgeLabel: t("badgeInspection"),
          badgeVariant: "warning",
          meta: t("entryInspectionNeeded"),
        };
      case "lease_end_approaching":
        return {
          ...base,
          badgeLabel: t("badgeEndApproaching"),
          badgeVariant: "warning",
          meta: t("upcomingEndDateUntil", { date: formatDate(alert.endDate, locale) }),
        };
      case "lease_closure_pending":
        return {
          ...base,
          badgeLabel: t("badgeClosure"),
          badgeVariant: alert.subKind === "ready" ? "success" : alert.subKind === "keys_needed" ? "danger" : "warning",
          meta:
            alert.subKind === "keys_needed"
              ? t("closurePendingKeysNeeded")
              : alert.subKind === "inspection_needed"
                ? t("closurePendingInspectionNeeded", { date: formatDate(alert.dueDate, locale) })
                : t("closurePendingReady"),
        };
      case "deposit_refund_pending":
        return {
          ...base,
          badgeLabel: t("badgeDeposit"),
          badgeVariant: "danger",
          meta: alert.balances
            .map((b) => `${tdep(DEPOSIT_TYPE_KEY[b.depositType] ?? "typeAvanceGarantie")}: ${b.balance}`)
            .join(" · "),
        };
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">
          {t("greeting", { name: profile.full_name ?? profile.email })}
        </h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">
          {isOwnerOrg ? t("ownerSubtitle") : t("subtitle")}
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatTile label={t("statProperties")} value={String(stats.propertiesCount)} />
        <StatTile
          label={t("statOccupancy")}
          value={`${stats.occupancyRate} %`}
          progress={stats.occupancyRate}
        />
        <StatTile
          label={t("statRent")}
          value={formatCompactCurrency(stats.rentThisMonth, locale)}
        />
        <StatTile
          label={t("statDue")}
          value={formatCompactCurrency(stats.dueThisMonth, locale)}
          valueClassName="text-status-danger-fg"
        />
      </div>

      {Object.keys(parkByStatus).length > 0 ? (
        <div className="flex flex-wrap gap-2">
          {Object.entries(parkByStatus).map(([status, count]) => (
            <Badge key={status} variant="secondary" className="px-2.5 py-1 text-[12px]">
              {count}{" "}
              {tprop(PROPERTY_STATUS_KEY[status as keyof typeof PROPERTY_STATUS_KEY] ?? "statusAvailable")}
            </Badge>
          ))}
        </div>
      ) : null}

      <Card className="p-0">
        <div className="px-[22px] pt-4 pb-1 text-[15px] font-bold">{t("todoTitle")}</div>
        {alerts.length === 0 ? (
          <p className="px-[22px] py-6 text-sm text-muted-foreground">{t("todoEmpty")}</p>
        ) : (
          <div className="flex flex-col">
            {alerts.map((alert, i) => (
              <AlertRow key={`${alert.kind}-${alert.leaseId}-${i}`} {...alertToRow(alert)} />
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
