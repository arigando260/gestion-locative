"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createLeaseAction } from "@/actions/leases";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

type Tenant = { id: string; full_name: string | null; email: string };

export function LeaseForm({
  propertyId,
  tenants,
}: {
  propertyId: string;
  tenants: Tenant[];
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createLeaseAction, null);

  return (
    <form action={formAction} className="flex max-w-md flex-col gap-4">
      <input type="hidden" name="locale" value={locale} />
      <input type="hidden" name="property_id" value={propertyId} />

      {tenants.length === 0 ? (
        <p className="text-sm text-destructive">{t("noTenants")}</p>
      ) : (
        <SelectField
          name="tenant_account_id"
          label={t("tenant")}
          options={tenants.map((tenant) => ({
            value: tenant.id,
            label: tenant.full_name ?? tenant.email,
          }))}
        />
      )}

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="start_date">{t("startDate")}</Label>
        <Input id="start_date" name="start_date" type="date" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="end_date">{t("endDate")}</Label>
        <Input id="end_date" name="end_date" type="date" />
        <p className="text-xs text-muted-foreground">{t("endDateHint")}</p>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="rent_amount">{t("rentAmount")}</Label>
        <Input
          id="rent_amount"
          name="rent_amount"
          type="number"
          min="0"
          step="0.01"
          required
        />
      </div>
      <SelectField
        name="payment_frequency"
        label={t("paymentFrequency")}
        options={[
          { value: "mensuel", label: t("frequencyMensuel") },
          { value: "trimestriel", label: t("frequencyTrimestriel") },
          { value: "semestriel", label: t("frequencySemestriel") },
          { value: "annuel", label: t("frequencyAnnuel") },
        ]}
      />
      <SelectField
        name="payment_timing"
        label={t("paymentTiming")}
        options={[
          { value: "postpaye", label: t("timingPostpaye") },
          { value: "prepaye", label: t("timingPrepaye") },
        ]}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="security_deposit_amount">{t("securityDeposit")}</Label>
        <Input
          id="security_deposit_amount"
          name="security_deposit_amount"
          type="number"
          min="0"
          step="0.01"
          required
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="utility_deposit_amount">{t("utilityDeposit")}</Label>
        <Input
          id="utility_deposit_amount"
          name="utility_deposit_amount"
          type="number"
          min="0"
          step="0.01"
        />
        <p className="text-xs text-muted-foreground">{t("utilityDepositHint")}</p>
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="billing_day">{t("billingDay")}</Label>
        <Input
          id="billing_day"
          name="billing_day"
          type="number"
          min="1"
          max="31"
        />
        <p className="text-xs text-muted-foreground">{t("billingDayHint")}</p>
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} disabled={tenants.length === 0}>
        {tc("create")}
      </SubmitButton>
    </form>
  );
}
