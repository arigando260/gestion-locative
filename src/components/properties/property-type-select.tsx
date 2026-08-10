"use client";

import { useTranslations } from "next-intl";
import { SelectField } from "@/components/forms/select-field";
import { getPropertyTypeLabel, type PropertyType } from "@/lib/property-type-labels";

export function PropertyTypeSelect({
  propertyTypes,
  defaultValue,
}: {
  propertyTypes: PropertyType[];
  defaultValue?: string;
}) {
  const t = useTranslations("properties");

  return (
    <SelectField
      name="location_type"
      label={t("locationType")}
      defaultValue={defaultValue}
      options={propertyTypes.map((type) => ({
        value: type.code,
        label: getPropertyTypeLabel(propertyTypes, type.code, t),
      }))}
    />
  );
}
