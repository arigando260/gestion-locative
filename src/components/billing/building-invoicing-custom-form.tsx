"use client";

import { useActionState, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { generateCustomBuildingInvoicesAction } from "@/actions/building-invoicing";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { formatDate } from "@/lib/format-date";
import type { LeaseToInvoice } from "@/data/building-invoicing";

// Point 4 du module facturation groupée par immeuble : mêmes données que le
// résumé automatique (summary.toInvoice), sélection manuelle bail par bail
// / échéance par échéance -- même principe de case à cocher que
// InvoiceGenerateForm (un seul bail), répété pour chaque bail à facturer.
// Tout coché par défaut : décocher pour exclure, jamais l'inverse.
export function BuildingInvoicingCustomForm({
  buildingId,
  leases,
  onCancel,
}: {
  buildingId: string;
  leases: LeaseToInvoice[];
  onCancel: () => void;
}) {
  const t = useTranslations("billing");
  const locale = useLocale();
  const [state, formAction] = useActionState(generateCustomBuildingInvoicesAction, null);

  const [selected, setSelected] = useState<Record<string, Set<string>>>(() =>
    Object.fromEntries(leases.map((l) => [l.leaseId, new Set(l.schedules.map((s) => s.id))]))
  );

  function toggle(leaseId: string, scheduleId: string) {
    setSelected((prev) => {
      const next = new Set(prev[leaseId]);
      if (next.has(scheduleId)) next.delete(scheduleId);
      else next.add(scheduleId);
      return { ...prev, [leaseId]: next };
    });
  }

  // Recalculé à chaque rendu -- l'input caché reflète toujours la sélection
  // courante au moment du submit (React met à jour le DOM avant que le
  // navigateur ne lise le FormData de soumission).
  const selectionsJson = JSON.stringify(
    leases.map((l) => ({
      leaseId: l.leaseId,
      propertyName: l.propertyName,
      scheduleIds: [...(selected[l.leaseId] ?? [])],
    }))
  );

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="building_id" value={buildingId} />
      <input type="hidden" name="selections" value={selectionsJson} />

      {leases.map((lease) => (
        <div
          key={lease.leaseId}
          className="flex flex-col gap-2 border-b border-border pb-3 last:border-0"
        >
          <p className="text-sm font-medium">
            {lease.propertyName} — {lease.tenantName}
          </p>
          <div className="flex flex-col gap-1.5 pl-4">
            {lease.schedules.map((schedule) => (
              <Label
                key={schedule.id}
                htmlFor={`schedule-${schedule.id}`}
                className="flex items-center gap-2 font-normal"
              >
                <input
                  type="checkbox"
                  id={`schedule-${schedule.id}`}
                  checked={selected[lease.leaseId]?.has(schedule.id) ?? false}
                  onChange={() => toggle(lease.leaseId, schedule.id)}
                  className="size-4"
                />
                <span>
                  {formatDate(schedule.periodStartDate, locale)} → {formatDate(schedule.periodEndDate, locale)} — {schedule.amountDue}
                </span>
              </Label>
            ))}
          </div>
        </div>
      ))}

      <FormMessage state={state} />
      {state?.results && (
        <ul className="flex flex-col gap-1 text-sm">
          {state.results.map((r) => (
            <li key={r.leaseId} className={r.success ? "text-foreground" : "text-destructive"}>
              {r.propertyName} — {r.success ? t("resultSuccess") : r.message ?? t("resultFailure")}
            </li>
          ))}
        </ul>
      )}

      <div className="flex gap-2">
        <SubmitButton pendingText={t("generatingBuildingInvoices")}>
          {t("customFormSubmit")}
        </SubmitButton>
        <Button type="button" variant="outline" onClick={onCancel}>
          {t("backToSummary")}
        </Button>
      </div>
    </form>
  );
}
