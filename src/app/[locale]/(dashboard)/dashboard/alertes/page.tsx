import { getTranslations } from "next-intl/server";
import { redirect, Link } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentStaffRole } from "@/data/session";
import { getCurrentUserPermissions } from "@/data/permissions";
import { getDashboardAlerts } from "@/data/dashboard-alerts";
import { AlertRow } from "@/components/dashboard/alert-row";
import { alertToRowProps, sortAlertsBySeverity } from "@/components/dashboard/alert-mapping";
import { Card } from "@/components/ui/card";

// Liste complète (non tronquée) des mêmes alertes que la carte "À traiter
// aujourd'hui" du tableau de bord -- même source (getDashboardAlerts),
// même tri (sortAlertsBySeverity), même mapping (alertToRowProps) : jamais
// un second calcul qui pourrait diverger. Réservée au staff, même gating
// que /dashboard (hérité du layout (dashboard), rien de nouveau à poser
// ici) -- pas d'entrée sidebar, atteinte seulement via le lien "Voir les N
// situations" du tableau de bord.
export default async function DashboardAlertsPage({
  params,
}: PageProps<"/[locale]/dashboard/alertes">) {
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

  const permissions = await getCurrentUserPermissions();
  const alerts = await getDashboardAlerts(profile.organization_id, permissions);
  const sortedAlerts = sortAlertsBySeverity(alerts);

  const t = await getTranslations("dashboard");
  const tdep = await getTranslations("deposits");
  const tc = await getTranslations("common");

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href="/dashboard" className="text-sm text-muted-foreground hover:underline">
          ← {tc("back")}
        </Link>
        <h1 className="mt-2 text-2xl font-bold tracking-tight">{t("alertsPageTitle")}</h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">
          {t("alertsPageSubtitle", { count: sortedAlerts.length })}
        </p>
      </div>

      <Card className="p-0">
        {sortedAlerts.length === 0 ? (
          <p className="px-[22px] py-6 text-sm text-muted-foreground">{t("todoEmpty")}</p>
        ) : (
          <div className="flex flex-col">
            {sortedAlerts.map((alert, i) => (
              <AlertRow
                key={`${alert.kind}-${alert.leaseId}-${i}`}
                {...alertToRowProps(alert, { t, tdep, locale })}
              />
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}
