"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { recordRefundAction } from "@/actions/deposits";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export function RefundForm({ leaseId }: { leaseId: string }) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(recordRefundAction, null);

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
        <Label htmlFor="refund_amount">{t("amount")}</Label>
        <Input id="refund_amount" name="amount" type="number" min="0" step="0.01" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="refund_reason">{t("reason")}</Label>
        <Input id="refund_reason" name="reason" />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("recordRefund")}</SubmitButton>
    </form>
  );
}
