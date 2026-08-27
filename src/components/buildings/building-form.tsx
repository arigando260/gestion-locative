"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { createBuildingAction } from "@/actions/buildings";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { Country } from "@/data/countries";

export function BuildingForm({
  countries,
  defaultCountryCode,
}: {
  countries: Country[];
  defaultCountryCode?: string;
}) {
  const t = useTranslations("buildings");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(createBuildingAction, null);

  return (
    <form action={formAction} className="flex max-w-md flex-col gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="name">{t("name")}</Label>
        <Input id="name" name="name" required />
      </div>
      <SelectField
        name="country_code"
        label={t("country")}
        defaultValue={defaultCountryCode ?? countries[0]?.code}
        options={countries.map((c) => ({ value: c.code, label: c.name }))}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="city">{t("city")}</Label>
        <Input id="city" name="city" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="neighborhood">{t("neighborhood")}</Label>
        <Input id="neighborhood" name="neighborhood" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="address_complement">{t("addressComplement")}</Label>
        <Input id="address_complement" name="address_complement" />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="floors_count">{t("floorsCount")}</Label>
        <Input id="floors_count" name="floors_count" type="number" min="0" step="1" />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{tc("create")}</SubmitButton>
    </form>
  );
}
