"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createReservationAction } from "@/actions/reservations";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

type TenantOption = { id: string; full_name: string | null; email: string };

export function ReservationForm({
  propertyId,
  tenants,
}: {
  propertyId: string;
  tenants: TenantOption[];
}) {
  const t = useTranslations("reservations");
  const tl = useTranslations("leases");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createReservationAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="property_id" value={propertyId} />
      <input type="hidden" name="locale" value={locale} />
      {tenants.length === 0 ? (
        <p className="text-sm text-muted-foreground">{tl("noTenants")}</p>
      ) : (
        <SelectField
          name="tenant_account_id"
          label={tl("tenant")}
          options={tenants.map((tenant) => ({
            value: tenant.id,
            label: tenant.full_name ?? tenant.email,
          }))}
        />
      )}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="check_in_date">{t("checkIn")}</Label>
        <Input id="check_in_date" name="check_in_date" type="date" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="check_out_date">{t("checkOut")}</Label>
        <Input id="check_out_date" name="check_out_date" type="date" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="nightly_rate">{t("nightlyRate")}</Label>
        <Input id="nightly_rate" name="nightly_rate" type="number" min="0" step="0.01" required />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} disabled={tenants.length === 0}>
        {t("create")}
      </SubmitButton>
    </form>
  );
}
