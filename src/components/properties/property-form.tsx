"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createPropertyAction } from "@/actions/properties";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { PropertyTypeSelect } from "./property-type-select";
import type { PropertyType } from "@/data/property-types";
import type { Country } from "@/data/countries";

export function PropertyForm({
  propertyTypes,
  countries,
  defaultCountryCode,
}: {
  propertyTypes: PropertyType[];
  countries: Country[];
  // Pays hérité de l'organisation à l'ouverture du formulaire, modifiable
  // par bien (décision Module 12, conception adresse structurée) — repli
  // sur le premier pays du catalogue si l'organisation n'en a
  // exceptionnellement aucun (ne devrait pas arriver, country_code est
  // NOT NULL sur organizations depuis le Module 12b).
  defaultCountryCode?: string;
}) {
  const t = useTranslations("properties");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createPropertyAction, null);

  return (
    <form action={formAction} className="flex max-w-md flex-col gap-4">
      <input type="hidden" name="locale" value={locale} />
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
      <PropertyTypeSelect propertyTypes={propertyTypes} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="price">{t("price")}</Label>
        <Input id="price" name="price" type="number" min="0" step="0.01" required />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{tc("create")}</SubmitButton>
    </form>
  );
}
