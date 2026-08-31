import { getTranslations } from "next-intl/server";
import { redirect, Link } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentStaffRole } from "@/data/session";
import { getLeasesWithUpcomingEndDate, LEASE_END_APPROACHING_DAYS } from "@/data/lease-closure";
import { getSchedulesDueThisWeek } from "@/data/schedules";
import { getLeasesWithPendingDepositRefund } from "@/data/deposits";
import { formatDate, daysSince } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";

// Fidèle à la maquette design/Clarisse V5 - Espace Agence.dc.html (écran
// "Échéances", isDeadlines) : cartes groupées (titre + compte), lignes
// "quand" coloré + titre/méta + puce d'action -- patron distinct
// d'AlertRow (pas de réutilisation forcée entre deux structures visuelles
// différentes).
//
// Filtre temporel "90j/30j/cette semaine" : s'applique UNIQUEMENT à "Baux à
// échéance" et "Loyers dus" (jamais "Garanties à restituer", qui n'a pas de
// notion de fenêtre temporelle). Sans paramètre ?range=, chaque groupe garde
// EXACTEMENT son seuil historique (30j / 7j) -- aucune puce n'est alors
// affichée comme sélectionnée : c'est le seul moyen de préserver les
// chiffres déjà validés (2+9+2=13), impossibles à reproduire avec une SEULE
// valeur commune (vérifié empiriquement : à 7j, baux=1 pas 2 ; à 30j,
// loyers=29 pas 9). Choisir une puce applique alors la MÊME valeur aux deux
// groupes, comme demandé -- les totaux changent alors légitimement.
const RANGE_DAYS = { "90": 90, "30": 30, "7": 7 } as const;
type RangeOption = keyof typeof RANGE_DAYS;
const RANGE_OPTIONS: RangeOption[] = ["90", "30", "7"];

function whenColorClass(daysUntil: number): string {
  if (daysUntil <= 0) return "text-status-danger-fg";
  if (daysUntil <= 7) return "text-status-warning-fg";
  return "text-muted-foreground";
}

export default async function DashboardDeadlinesPage({
  params,
  searchParams,
}: PageProps<"/[locale]/dashboard/echeances">) {
  const { locale } = await params;
  const rawSearchParams = (await searchParams) as { range?: string };
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

  const selectedRange = RANGE_OPTIONS.find((option) => option === rawSearchParams.range);
  const leaseEndDays = selectedRange ? RANGE_DAYS[selectedRange] : LEASE_END_APPROACHING_DAYS;
  const rentDueDays = selectedRange ? RANGE_DAYS[selectedRange] : 7;

  const [upcomingEndLeases, dueThisWeek, pendingDepositRefunds] = await Promise.all([
    getLeasesWithUpcomingEndDate(profile.organization_id, leaseEndDays),
    getSchedulesDueThisWeek(profile.organization_id, rentDueDays),
    getLeasesWithPendingDepositRefund(profile.organization_id),
  ]);

  const t = await getTranslations("dashboard");
  const tc = await getTranslations("common");
  const tdep = await getTranslations("deposits");
  const DEPOSIT_TYPE_KEY: Record<string, string> = {
    avance_garantie: "typeAvanceGarantie",
    caution_utilities: "typeCautionUtilities",
  };

  const totalCount = upcomingEndLeases.length + dueThisWeek.length + pendingDepositRefunds.length;

  const rangeLabel = (days: number) =>
    days === 7 ? t("rangeChip7") : t("groupRangeLabel", { days });

  const groups = [
    {
      key: "leaseEnd",
      title: t("groupLeaseEnd"),
      subtitle: rangeLabel(leaseEndDays),
      items: upcomingEndLeases.map((lease) => {
        const daysUntil = -(daysSince(lease.lease_end_date) ?? 0);
        return {
          key: lease.lease_id,
          when: daysUntil <= 0 ? t("dueToday") : t("inDays", { days: daysUntil }),
          whenClass: whenColorClass(daysUntil),
          title: lease.tenant_full_name ?? lease.property_name,
          meta: t("leaseEndsOn", {
            property: lease.property_name,
            date: formatDate(lease.lease_end_date, locale),
          }),
          actionLabel: t("actionRenewOrClose"),
          actionHref: `/leases/${lease.lease_id}`,
        };
      }),
    },
    {
      key: "rentDue",
      title: t("groupRentDue"),
      subtitle: rangeLabel(rentDueDays),
      items: dueThisWeek.map((schedule) => {
        const daysUntil = -(daysSince(schedule.due_date) ?? 0);
        return {
          key: schedule.lease_id,
          when: daysUntil <= 0 ? t("dueToday") : t("inDays", { days: daysUntil }),
          whenClass: whenColorClass(daysUntil),
          title: schedule.tenant_full_name ?? schedule.property_name,
          meta: t("rentDueMeta", {
            property: schedule.property_name,
            amount: formatCurrency(schedule.amount_due, locale),
          }),
          actionLabel: t("viewDetails"),
          actionHref: `/leases/${schedule.lease_id}`,
        };
      }),
    },
    {
      key: "depositRefund",
      title: t("groupDepositRefund"),
      subtitle: null,
      items: pendingDepositRefunds.map((lease) => ({
        key: lease.lease_id,
        when: null,
        whenClass: "",
        title: lease.tenant_full_name ?? lease.property_name,
        meta: t("depositRefundMeta", {
          property: lease.property_name,
          breakdown: lease.balances
            .map((b) => tdep(DEPOSIT_TYPE_KEY[b.deposit_type] ?? "typeAvanceGarantie"))
            .join(" · "),
        }),
        actionLabel: t("actionRefund"),
        actionHref: `/leases/${lease.lease_id}/deposits`,
      })),
    },
  ].filter((group) => group.items.length > 0);

  return (
    <div className="flex flex-col gap-6">
      <div>
        <Link href="/dashboard" className="text-sm text-muted-foreground hover:underline">
          ← {tc("back")}
        </Link>
        <h1 className="mt-2 text-2xl font-bold tracking-tight">{t("echeancesPageTitle")}</h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">
          {t("echeancesPageSubtitle", { count: totalCount })}
        </p>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {RANGE_OPTIONS.map((option) => (
          <Link
            key={option}
            href={{ pathname: "/dashboard/echeances", query: { range: option } }}
            replace
            className={
              selectedRange === option
                ? "rounded-lg bg-[#18181b] px-3.5 py-[7px] text-[13px] font-semibold text-white"
                : "rounded-lg border border-[#e6e6e9] bg-card px-3.5 py-[7px] text-[13px] font-semibold text-[#52525b] hover:bg-[#fafafa]"
            }
          >
            {t(`rangeChip${option}` as "rangeChip90" | "rangeChip30" | "rangeChip7")}
          </Link>
        ))}
        {selectedRange ? (
          <Link
            href="/dashboard/echeances"
            replace
            className="text-[12.5px] font-medium text-muted-foreground hover:underline"
          >
            {t("echeancesResetRange")}
          </Link>
        ) : null}
      </div>

      {groups.length === 0 ? (
        <Card className="p-0">
          <p className="px-[22px] py-6 text-sm text-muted-foreground">{t("echeancesEmpty")}</p>
        </Card>
      ) : (
        groups.map((group) => (
          // Ancre depuis "À venir" (tableau de bord) : id = groupKey utilisé
          // là-bas, scroll-mt pour ne pas coller sous l'en-tête au défilement,
          // anneau visuel quand ce groupe est la cible de l'URL (:target,
          // natif, sans JS).
          <Card
            key={group.key}
            id={group.key}
            className="scroll-mt-6 p-0 target:ring-2 target:ring-primary target:ring-offset-2"
          >
            <div className="flex items-center justify-between gap-3 px-[22px] py-[15px]">
              <div>
                <div className="text-[15px] font-bold tracking-[-0.01em]">{group.title}</div>
                {group.subtitle ? (
                  <div className="mt-0.5 text-[12px] text-muted-foreground">{group.subtitle}</div>
                ) : null}
              </div>
              <div className="text-[12.5px] font-semibold text-muted-foreground">
                {t("groupItemCount", { count: group.items.length })}
              </div>
            </div>
            <div className="flex flex-col">
              {group.items.map((item) => (
                <div
                  key={item.key}
                  className="flex flex-wrap items-center gap-4 border-t border-[#f2f2f4] px-[22px] py-[14px] hover:bg-[#fafafa]"
                >
                  {item.when ? (
                    <div className={`w-[92px] shrink-0 text-[12.5px] font-bold ${item.whenClass}`}>
                      {item.when}
                    </div>
                  ) : null}
                  <div className="min-w-[220px] flex-1">
                    <div className="text-[13.5px] font-semibold tracking-[-0.01em]">{item.title}</div>
                    <div className="mt-0.5 text-[12.5px] text-[#8b8b93]">{item.meta}</div>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    render={<Link href={item.actionHref} />}
                    nativeButton={false}
                  >
                    {item.actionLabel}
                  </Button>
                </div>
              ))}
            </div>
          </Card>
        ))
      )}
    </div>
  );
}
