"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { recordPaymentAction } from "@/actions/payments";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { formatDate } from "@/lib/format-date";
import type { ScheduleWithEffectiveStatus } from "@/data/schedules";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export function PaymentForm({
  leaseId,
  schedules,
}: {
  leaseId: string;
  schedules: ScheduleWithEffectiveStatus[];
}) {
  const t = useTranslations("payments");
  const ts = useTranslations("schedules");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(recordPaymentAction, null);

  // Une échéance déjà soldée ou annulée n'a pas de raison de recevoir un
  // nouveau paiement dans cette tranche (pas de remboursement/avoir ici).
  const eligible = schedules.filter(
    (s) => s.effective_status !== "payee" && s.effective_status !== "annulee"
  );

  if (eligible.length === 0) return null;

  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle>{t("formTitle")}</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="flex flex-col gap-4">
          <input type="hidden" name="lease_id" value={leaseId} />
          <SelectField
            name="payment_schedule_id"
            label={ts("title")}
            options={eligible.map((s) => ({
              value: s.id!,
              label: `${formatDate(s.period_start_date, locale)} → ${formatDate(s.period_end_date, locale)} (${s.amount_due})`,
            }))}
          />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="amount">{t("amount")}</Label>
            <Input
              id="amount"
              name="amount"
              type="number"
              min="0"
              step="0.01"
              required
            />
          </div>
          <SelectField
            name="method"
            label={t("method")}
            options={[
              { value: "mobile_money", label: t("methodMobileMoney") },
              { value: "carte", label: t("methodCarte") },
              { value: "especes", label: t("methodEspeces") },
              { value: "virement", label: t("methodVirement") },
            ]}
          />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="payment_date">{t("paymentDate")}</Label>
            <Input id="payment_date" name="payment_date" type="date" required />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="external_reference">{t("reference")}</Label>
            <Input id="external_reference" name="external_reference" />
          </div>
          <FormMessage state={state} />
          <SubmitButton pendingText={tc("loading")}>{t("submit")}</SubmitButton>
        </form>
      </CardContent>
    </Card>
  );
}
