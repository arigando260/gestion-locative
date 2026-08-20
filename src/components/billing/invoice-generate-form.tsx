"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { generateScheduleInvoiceAction } from "@/actions/schedule-invoices";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { formatDate } from "@/lib/format-date";
import type { ScheduleWithEffectiveStatus } from "@/data/schedules";

// Facturation groupée (Module 9) : sélection libre parmi les échéances de
// CE bail uniquement (schedules déjà scopé au bail par l'appelant, voir
// app/[locale]/(dashboard)/leases/[leaseId]/page.tsx) — jamais de choix de
// bail ici, c'est justement ce qui rend le mélange entre locataires
// structurellement impossible (voir conception + trigger de cohérence).
export function InvoiceGenerateForm({
  leaseId,
  schedules,
}: {
  leaseId: string;
  schedules: ScheduleWithEffectiveStatus[];
}) {
  const t = useTranslations("billing");
  const ts = useTranslations("schedules");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(generateScheduleInvoiceAction, null);

  if (schedules.length === 0) {
    return <p className="text-sm text-muted-foreground">{ts("empty")}</p>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-3">
      <input type="hidden" name="lease_id" value={leaseId} />
      <div className="flex flex-col gap-2">
        {schedules.map((schedule) => (
          <Label
            key={schedule.id}
            htmlFor={`schedule-${schedule.id}`}
            className="flex items-center gap-2 font-normal"
          >
            <input
              type="checkbox"
              id={`schedule-${schedule.id}`}
              name="schedule_ids"
              value={schedule.id ?? ""}
              className="size-4"
            />
            <span>
              {formatDate(schedule.period_start_date, locale)} → {formatDate(schedule.period_end_date, locale)} — {schedule.amount_due}
            </span>
          </Label>
        ))}
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} variant="outline" className="w-fit">
        {t("generateInvoice")}
      </SubmitButton>
    </form>
  );
}
