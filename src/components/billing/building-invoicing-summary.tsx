"use client";

import { useActionState, useState } from "react";
import { useTranslations } from "next-intl";
import { generateBuildingInvoicesAction } from "@/actions/building-invoicing";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { BuildingInvoicingCustomForm } from "./building-invoicing-custom-form";
import type { BuildingInvoicingSummary } from "@/data/building-invoicing";

// Résumé + déclenchement (points 2 et 3 du module facturation groupée par
// immeuble) : le mois se choisit via un simple <form method="GET"> (pas de
// fetch client) -- changer le mois recharge la page serveur avec la
// nouvelle query string, même patron que le reste du projet qui préfère
// les Server Components aux allers-retours client.
export function BuildingInvoicingSummaryView({
  buildingId,
  month,
  summary,
}: {
  buildingId: string;
  month: string;
  summary: BuildingInvoicingSummary;
}) {
  const t = useTranslations("billing");
  const [state, formAction] = useActionState(generateBuildingInvoicesAction, null);
  const [customizing, setCustomizing] = useState(false);

  return (
    <div className="flex flex-col gap-4">
      <form method="GET" className="flex flex-wrap items-end gap-2">
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="month">{t("monthLabel")}</Label>
          <input
            id="month"
            name="month"
            type="month"
            defaultValue={month}
            className="h-8 rounded-lg border border-border bg-background px-2.5 text-sm"
          />
        </div>
        <Button type="submit" variant="outline">
          {t("applyMonth")}
        </Button>
      </form>

      <dl className="grid grid-cols-2 gap-4 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-muted-foreground">{t("summaryTotalProperties")}</dt>
          <dd className="text-lg font-semibold">{summary.totalProperties}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">{t("summaryToInvoice")}</dt>
          <dd className="text-lg font-semibold">{summary.toInvoice.length}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">{t("summaryVacant")}</dt>
          <dd className="text-lg font-semibold">{summary.vacantCount}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">{t("summaryAlreadyInvoiced")}</dt>
          <dd className="text-lg font-semibold">{summary.alreadyInvoicedCount}</dd>
        </div>
      </dl>
      {summary.noScheduleThisMonthCount > 0 && (
        <p className="text-sm text-muted-foreground">
          {t("summaryNoSchedule", { count: summary.noScheduleThisMonthCount })}
        </p>
      )}

      {summary.toInvoice.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("noLeasesToInvoice")}</p>
      ) : customizing ? (
        <BuildingInvoicingCustomForm
          buildingId={buildingId}
          leases={summary.toInvoice}
          onCancel={() => setCustomizing(false)}
        />
      ) : (
        <div className="flex flex-wrap items-center gap-3">
          <form action={formAction} className="flex items-center gap-3">
            <input type="hidden" name="building_id" value={buildingId} />
            <input type="hidden" name="month" value={month} />
            <SubmitButton pendingText={t("generatingBuildingInvoices")}>
              {t("generateBuildingInvoices", { count: summary.toInvoice.length })}
            </SubmitButton>
          </form>
          <Button type="button" variant="outline" onClick={() => setCustomizing(true)}>
            {t("customizeSelection")}
          </Button>
        </div>
      )}

      {state?.results && (
        <div className="flex flex-col gap-2 border-t border-border pt-3">
          <p className="text-sm font-medium">{state.message}</p>
          <ul className="flex flex-col gap-1 text-sm">
            {state.results.map((r) => (
              <li key={r.leaseId} className={r.success ? "text-foreground" : "text-destructive"}>
                {r.propertyName} — {r.success ? t("resultSuccess") : r.message ?? t("resultFailure")}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
