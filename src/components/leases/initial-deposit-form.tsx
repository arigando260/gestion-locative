"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { recordInitialDepositAction } from "@/actions/deposits";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export function InitialDepositForm({ leaseId }: { leaseId: string }) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(recordInitialDepositAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="lease_id" value={leaseId} />
      <SelectField
        name="deposit_type"
        label={t("depositTypeLabel")}
        options={[
          { value: "avance_garantie", label: t("typeAvanceGarantie") },
          { value: "caution_utilities", label: t("typeCautionUtilities") },
        ]}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="amount">{t("amount")}</Label>
        <Input id="amount" name="amount" type="number" min="0" step="0.01" required />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>
        {t("recordInitialDeposit")}
      </SubmitButton>
    </form>
  );
}
