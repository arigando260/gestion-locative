import { getTranslations } from "next-intl/server";
import { redirect, Link } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentStaffRole } from "@/data/session";
import { getCurrentUserPermissions } from "@/data/permissions";
import { getDashboardAlerts } from "@/data/dashboard-alerts";
import { getDashboardStats } from "@/data/dashboard-stats";
import { getPropertiesWithEffectiveStatus } from "@/data/properties";
import { getOrganization } from "@/data/organizations";
import {
  getClosurePendingPropertyIds,
  resolvePropertyParkStatus,
  getLeasesWithUpcomingEndDate,
} from "@/data/lease-closure";
import { getLeasesWithPendingDepositRefund } from "@/data/deposits";
import { getUpcomingScheduleCountThisWeek } from "@/data/schedules";
import { getRecentActivity, type RecentActivityEvent } from "@/data/dashboard-activity";
import { formatDateTime, daysSince } from "@/lib/format-date";
import { formatCompactCurrency } from "@/lib/format-currency";
import { cn } from "@/lib/utils";
import { StatTile } from "@/components/dashboard/stat-tile";
import { AlertRow } from "@/components/dashboard/alert-row";
import { alertToRowProps, sortAlertsBySeverity } from "@/components/dashboard/alert-mapping";
import { AgentTodayView } from "@/components/dashboard/agent-today-view";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

// Ordre d'affichage fixe des chips "État du parc" (pas l'ordre naturel des
// biens) + couleur de puce par catégorie -- même palette sémantique que le
// reste du tableau de bord.
const PARK_ORDER = ["occupe", "disponible", "en_preparation_sortie", "en_travaux"] as const;
const PARK_LABEL_KEY: Record<(typeof PARK_ORDER)[number], string> = {
  occupe: "parkOccupied",
  disponible: "parkAvailable",
  en_preparation_sortie: "parkClosurePending",
  en_travaux: "parkUnavailable",
};
const PARK_DOT_CLASS: Record<(typeof PARK_ORDER)[number], string> = {
  occupe: "bg-status-success-fg",
  disponible: "bg-[#a1a1aa]",
  en_preparation_sortie: "bg-status-warning-fg",
  en_travaux: "bg-[#a1a1aa]",
};

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
  const [
    alerts,
    stats,
    properties,
    organization,
    closurePropertyIds,
    upcomingEndLeases,
    upcomingRentCount,
    pendingDepositRefunds,
    recentActivity,
  ] = await Promise.all([
    getDashboardAlerts(profile.organization_id, permissions),
    getDashboardStats(profile.organization_id),
    getPropertiesWithEffectiveStatus(),
    getOrganization(profile.organization_id),
    getClosurePendingPropertyIds(profile.organization_id),
    getLeasesWithUpcomingEndDate(profile.organization_id),
    getUpcomingScheduleCountThisWeek(profile.organization_id),
    getLeasesWithPendingDepositRefund(profile.organization_id),
    getRecentActivity(profile.organization_id),
  ]);
  // "Espace propriétaire" (maquette) : même vue, seule l'accroche change
  // selon organization_type -- voir (dashboard)/layout.tsx pour la même
  // logique côté tagline sidebar.
  const isOwnerOrg = organization?.organization_type === "proprietaire";
  const oldestOverdueDays = daysSince(stats.oldestOverdueDueDate);

  const t = await getTranslations("dashboard");
  const tdep = await getTranslations("deposits");

  // Tri par sévérité (alertSeverity, components/dashboard/alert-mapping.ts
  // -- même source que la couleur des badges, jamais un second classement)
  // : la carte tronque aux 5 plus urgentes, /dashboard/alertes affiche la
  // liste complète triée pareil.
  const sortedAlerts = sortAlertsBySeverity(alerts);
  const visibleAlerts = sortedAlerts.slice(0, 5);

  // resolvePropertyParkStatus (data/lease-closure.ts) est la même fonction
  // utilisée par le filtre de /properties -- une seule définition de "en
  // préparation de sortie", jamais recalculée séparément ici.
  const parkByStatus = properties.reduce<Record<string, number>>((acc, p) => {
    const bucket = resolvePropertyParkStatus(p.id, p.effective_status, closurePropertyIds);
    acc[bucket] = (acc[bucket] ?? 0) + 1;
    return acc;
  }, {});


  function activityEventLabel(event: RecentActivityEvent): string {
    switch (event.kind) {
      case "payment_received":
        return t("activityPaymentReceived", { name: event.tenantName ?? event.propertyName });
      case "issue_reported":
        return event.reportedByTenant
          ? t("activityIssueReportedTenant", { property: event.propertyName })
          : t("activityIssueReportedStaff", { property: event.propertyName });
      case "lease_signed":
        return t("activityLeaseSigned", { name: event.tenantName ?? event.propertyName });
      case "notice_filed":
        return t("activityNoticeFiled", { name: event.tenantName ?? event.propertyName });
    }
  }

  // Couleur de puce volontaire par catégorie, pas un warning générique
  // dupliqué trois fois -- ne pas "harmoniser" par erreur plus tard :
  // - baux à échéance / garanties à restituer : orange, une action est à
  //   prévoir par nature (renouveler/clôturer, rembourser), qu'il y ait
  //   urgence immédiate ou non.
  // - loyers dus cette semaine : gris, simple information -- ce n'est un
  //   problème que si l'échéance passe en retard, déjà couvert séparément
  //   par la catégorie "loyer en retard" de "À traiter aujourd'hui"
  //   (badge rouge, sévérité 0). Ne pas dupliquer ce signal ici.
  // groupKey correspond aux id des cartes de /dashboard/echeances (même
  // clé "leaseEnd"/"rentDue"/"depositRefund" que les groupes de cette
  // page) -- chaque ligne renvoie vers son ancre précise, pas le haut de
  // la page.
  const upcomingItems = [
    {
      groupKey: "leaseEnd",
      count: upcomingEndLeases.length,
      label: t("upcomingLeaseEnd", { count: upcomingEndLeases.length }),
      dotClass: "bg-status-warning-fg",
    },
    {
      groupKey: "rentDue",
      count: upcomingRentCount,
      label: t("upcomingRentDue", { count: upcomingRentCount }),
      dotClass: "bg-[#a1a1aa]",
    },
    {
      groupKey: "depositRefund",
      count: pendingDepositRefunds.length,
      label: t("upcomingDepositRefund", { count: pendingDepositRefunds.length }),
      dotClass: "bg-status-warning-fg",
    },
  ].filter((item) => item.count > 0);

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
        <StatTile
          label={t("statProperties")}
          value={String(stats.propertiesCount)}
          meta={t("statPropertiesMeta", { count: stats.buildingsCount })}
        />
        <StatTile
          label={t("statOccupancy")}
          value={`${stats.occupancyRate} %`}
          progress={stats.occupancyRate}
        />
        <StatTile
          label={t("statRent")}
          value={formatCompactCurrency(stats.rentThisMonth, locale)}
          meta={t("statRentMeta", {
            amount: formatCompactCurrency(stats.collectedThisMonth, locale),
            rate: stats.collectedRate,
          })}
        />
        <StatTile
          label={t("statDue")}
          value={formatCompactCurrency(stats.overdueAmount, locale)}
          meta={
            stats.overdueLeasesCount > 0
              ? t("statDueMeta", {
                  count: stats.overdueLeasesCount,
                  days: oldestOverdueDays ?? 0,
                })
              : undefined
          }
          valueClassName="text-status-danger-fg"
        />
      </div>

      {Object.keys(parkByStatus).length > 0 ? (
        <Card className="flex-row flex-wrap items-center gap-2 px-[18px] py-4">
          <span className="text-[11px] font-semibold tracking-wide text-muted-foreground uppercase">
            {t("parkTitle")}
          </span>
          {PARK_ORDER.filter((status) => (parkByStatus[status] ?? 0) > 0).map((status) => (
            <Link key={status} href={`/properties?status=${status}`}>
              <Badge
                variant="secondary"
                className="gap-1.5 px-2.5 py-1 text-[12px] hover:bg-muted"
              >
                <span className={cn("size-[7px] shrink-0 rounded-full", PARK_DOT_CLASS[status])} />
                {t(PARK_LABEL_KEY[status], { count: parkByStatus[status] })}
              </Badge>
            </Link>
          ))}
        </Card>
      ) : null}

      <div className="grid grid-cols-1 items-start gap-4 lg:grid-cols-[1.7fr_1fr]">
        <Card className="p-0">
          <div className="flex items-center justify-between px-[22px] pt-4 pb-1">
            <div className="flex items-center gap-2">
              <span className="size-[7px] shrink-0 rounded-full bg-status-danger-fg" />
              <span className="text-[15px] font-bold">{t("todoTitle")}</span>
            </div>
            {alerts.length > 0 ? (
              <Link
                href="/dashboard/alertes"
                className="text-[12.5px] font-medium text-primary hover:text-primary/80 hover:underline"
              >
                {t("todoViewAll", { count: alerts.length })}
              </Link>
            ) : null}
          </div>
          {alerts.length === 0 ? (
            <p className="px-[22px] py-6 text-sm text-muted-foreground">{t("todoEmpty")}</p>
          ) : (
            <div className="flex flex-col">
              {visibleAlerts.map((alert, i) => (
                <AlertRow
                  key={`${alert.kind}-${alert.leaseId}-${i}`}
                  {...alertToRowProps(alert, { t, tdep, locale })}
                />
              ))}
            </div>
          )}
        </Card>

        <div className="flex flex-col gap-4">
          <Card className="p-0">
            <div className="flex items-center justify-between px-[18px] pt-4 pb-1">
              <span className="text-[13px] font-bold">{t("upcomingTitle")}</span>
              {upcomingItems.length > 0 ? (
                <Link
                  href="/dashboard/echeances"
                  className="text-[12px] font-medium text-primary hover:text-primary/80 hover:underline"
                >
                  {t("upcomingViewAll")}
                </Link>
              ) : null}
            </div>
            {upcomingItems.length === 0 ? (
              <p className="px-[18px] py-4 text-[13px] text-muted-foreground">{t("upcomingEmpty")}</p>
            ) : (
              <div className="flex flex-col">
                {upcomingItems.map((item, i) => (
                  <Link
                    key={i}
                    href={`/dashboard/echeances#${item.groupKey}`}
                    className="flex items-center gap-2 border-t border-[#f2f2f4] px-[18px] py-3 text-[13px] first:border-t-0 hover:bg-[#fafafa]"
                  >
                    <span className="font-bold tabular-nums">{item.count}</span>
                    <span className="flex-1 text-muted-foreground">{item.label}</span>
                    <span className={cn("size-[7px] shrink-0 rounded-full", item.dotClass)} />
                  </Link>
                ))}
              </div>
            )}
          </Card>

          <Card className="gap-2 p-0">
            <div className="px-[18px] pt-4 pb-1 text-[13px] font-bold">{t("recentActivityTitle")}</div>
            {recentActivity.length === 0 ? (
              <p className="px-[18px] py-4 text-[13px] text-muted-foreground">{t("activityEmpty")}</p>
            ) : (
              <div className="flex flex-col gap-3 px-[18px] pb-4">
                {recentActivity.map((event, i) => (
                  <div key={i} className="flex items-baseline justify-between gap-3 text-[12.5px]">
                    <span className="text-foreground">{activityEventLabel(event)}</span>
                    <span className="shrink-0 text-muted-foreground">
                      {formatDateTime(event.at, locale)}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      </div>
    </div>
  );
}
