"use client";

import { useActionState, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { recordImputationAction } from "@/actions/deposits";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { formatDate } from "@/lib/format-date";
import type { ScheduleWithEffectiveStatus } from "@/data/schedules";

export function ImputationForm({
  leaseId,
  schedules,
  hasFinalizedEntryInspection,
}: {
  leaseId: string;
  schedules: ScheduleWithEffectiveStatus[];
  // Voir app/[locale]/(dashboard)/leases/[leaseId]/deposits/page.tsx —
  // calculé depuis getInspectionsForLease, pas depuis entry_inspection_done
  // (Module 10g/10k), scopé actif/resilie et donc peu fiable ici.
  hasFinalizedEntryInspection: boolean;
}) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(recordImputationAction, null);
  const [category, setCategory] = useState("loyer");

  // Une imputation de catégorie 'loyer' doit obligatoirement solder une
  // échéance précise (contrainte deposit_ledger_loyer_requires_schedule,
  // Module 5) — les autres catégories ne s'y rattachent pas.
  const eligibleSchedules = schedules.filter(
    (s) => s.effective_status !== "payee" && s.effective_status !== "annulee"
  );

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="lease_id" value={leaseId} />
      <SelectField
        name="imputation_category"
        label={t("category")}
        onValueChange={setCategory}
        options={[
          { value: "loyer", label: t("categoryLoyer") },
          { value: "degats", label: t("categoryDegats") },
          { value: "impayes_utilities", label: t("categoryImpayesUtilities") },
        ]}
      />
      {category === "degats" && !hasFinalizedEntryInspection && (
        <p className="text-sm text-amber-600">{t("degatsNoEntryInspectionWarning")}</p>
      )}
      {category === "loyer" && eligibleSchedules.length > 0 && (
        <SelectField
          name="payment_schedule_id"
          label={t("scheduleToSettle")}
          options={eligibleSchedules.map((s) => ({
            value: s.id!,
            label: `${formatDate(s.period_start_date, locale)} → ${formatDate(s.period_end_date, locale)} (${s.amount_due})`,
          }))}
        />
      )}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="amount">{t("amount")}</Label>
        <Input id="amount" name="amount" type="number" min="0" step="0.01" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="reason">{t("reason")}</Label>
        <Input id="reason" name="reason" required />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>
        {t("recordImputation")}
      </SubmitButton>
    </form>
  );
}
