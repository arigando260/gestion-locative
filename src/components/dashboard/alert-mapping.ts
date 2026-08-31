import type { DashboardAlert } from "@/data/dashboard-alerts";
import { formatDate } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import type { AlertRow } from "./alert-row";

export type AlertRowProps = React.ComponentProps<typeof AlertRow>;

type Translator = (key: string, values?: Record<string, string | number>) => string;

const DEPOSIT_TYPE_KEY: Record<string, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};

// Sévérité 0 (danger) → 2 (success) : SEULE source de tri ET de couleur de
// badge -- alertToRowProps ci-dessous dérive badgeVariant de cette même
// fonction, jamais un second classement qui pourrait diverger. Utilisée à
// la fois pour tronquer la carte du tableau de bord (top 5) et pour
// classer la page complète /dashboard/alertes.
export function alertSeverity(alert: DashboardAlert): 0 | 1 | 2 {
  switch (alert.kind) {
    case "rent_overdue":
    case "deposit_refund_pending":
      return 0;
    case "lease_closure_pending":
      return alert.subKind === "ready" ? 2 : alert.subKind === "keys_needed" ? 0 : 1;
    case "entry_inspection_needed":
    case "lease_end_approaching":
    case "low_coverage":
      return 1;
  }
}

const SEVERITY_VARIANT = ["danger", "warning", "success"] as const;

export function sortAlertsBySeverity(alerts: DashboardAlert[]): DashboardAlert[] {
  return [...alerts].sort((a, b) => alertSeverity(a) - alertSeverity(b));
}

// Badges d'urgence ("Obligatoire"/"Prêt"/"En retard") plutôt que de
// catégorie, montant/date séparés (meta/metaCaption, jamais fusionnés en
// une phrase), aucune valeur inventée pour les catégories sans montant
// réel (low_coverage/entry_inspection_needed/lease_end_approaching/
// lease_closure_pending -- seules deposit_refund_pending et rent_overdue
// portent un vrai montant, vérifié sur DashboardAlert).
export function alertToRowProps(
  alert: DashboardAlert,
  { t, tdep, locale }: { t: Translator; tdep: Translator; locale: string }
): AlertRowProps {
  const name = alert.tenantName ?? alert.propertyName;
  const base = {
    name,
    subtitle: alert.propertyName,
    actionLabel: t("viewDetails"),
    actionHref: `/leases/${alert.leaseId}`,
    badgeVariant: SEVERITY_VARIANT[alertSeverity(alert)],
  };

  switch (alert.kind) {
    case "rent_overdue":
      // "Relancer" reste toujours le libellé (validé avec Gabriel) -- seule
      // la destination change selon la présence d'un numéro : tel: si
      // connu, sinon la fiche bail (jamais un repli sur "Voir le détail").
      return {
        ...base,
        badgeLabel: t("badgeOverdue"),
        meta: formatCurrency(alert.amount, locale),
        metaCaption: t("dueOn", { date: formatDate(alert.dueDate, locale) }),
        actionLabel: t("relanceAction"),
        actionHref: alert.tenantPhone ? `tel:${alert.tenantPhone}` : `/leases/${alert.leaseId}`,
      };
    case "low_coverage":
      return {
        ...base,
        badgeLabel: t("badgeCoverage"),
        meta: alert.coverageEndDate ? formatDate(alert.coverageEndDate, locale) : undefined,
        metaCaption: alert.coverageEndDate ? undefined : t("lowCoverageNoSchedule"),
        actionLabel: t("actionGenerateSchedules"),
      };
    case "entry_inspection_needed":
      return {
        ...base,
        badgeLabel: t("badgeMandatory"),
        actionLabel: t("actionPlanInspection"),
        actionHref: `/leases/${alert.leaseId}/inspections/new`,
      };
    case "lease_end_approaching":
      return {
        ...base,
        badgeLabel: t("badgeEndApproaching"),
        meta: formatDate(alert.endDate, locale),
        actionLabel: t("actionRenewOrClose"),
      };
    case "lease_closure_pending":
      return {
        ...base,
        badgeLabel: alert.subKind === "ready" ? t("badgeReady") : t("badgeMandatory"),
        meta: alert.dueDate ? formatDate(alert.dueDate, locale) : undefined,
        actionLabel:
          alert.subKind === "keys_needed"
            ? t("actionRegisterKeys")
            : alert.subKind === "inspection_needed"
              ? t("actionFinalizeExitInspection")
              : t("actionCloseLease"),
      };
    case "deposit_refund_pending": {
      const total = alert.balances.reduce((sum, b) => sum + b.balance, 0);
      return {
        ...base,
        badgeLabel: t("badgeDeposit"),
        meta: formatCurrency(total, locale),
        metaCaption: alert.balances
          .map((b) => tdep(DEPOSIT_TYPE_KEY[b.depositType] ?? "typeAvanceGarantie"))
          .join(" · "),
        actionLabel: t("actionRefund"),
        actionHref: `/leases/${alert.leaseId}/deposits`,
      };
    }
  }
}
