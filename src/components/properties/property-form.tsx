"use client";

import { useActionState, useState } from "react";
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
import type { BuildingWithUnitsCount } from "@/data/buildings";

// Marqueur "créer un nouvel immeuble" — doit rester identique à
// NEW_BUILDING_MARKER (actions/properties.ts), pas d'export partagé pour
// éviter d'importer une Server Action dans une constante côté client, la
// valeur elle-même ("__new__") n'a aucune signification propre.
const NEW_BUILDING_VALUE = "__new__";
const NO_BUILDING_VALUE = "";

export function PropertyForm({
  propertyTypes,
  countries,
  buildings,
  defaultCountryCode,
}: {
  propertyTypes: PropertyType[];
  countries: Country[];
  buildings: BuildingWithUnitsCount[];
  // Pays hérité de l'organisation à l'ouverture du formulaire, modifiable
  // par bien (décision Module 12, conception adresse structurée) — repli
  // sur le premier pays du catalogue si l'organisation n'en a
  // exceptionnellement aucun (ne devrait pas arriver, country_code est
  // NOT NULL sur organizations depuis le Module 12b).
  defaultCountryCode?: string;
}) {
  const t = useTranslations("properties");
  const tb = useTranslations("buildings");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createPropertyAction, null);
  const [buildingSelection, setBuildingSelection] = useState(NO_BUILDING_VALUE);

  const hasBuilding = buildingSelection !== NO_BUILDING_VALUE;
  const isNewBuilding = buildingSelection === NEW_BUILDING_VALUE;

  return (
    <form action={formAction} className="flex max-w-md flex-col gap-4">
      <input type="hidden" name="locale" value={locale} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="name">{t("name")}</Label>
        <Input id="name" name="name" required />
      </div>

      <SelectField
        name="building_id"
        label={t("buildingLabel")}
        defaultValue={NO_BUILDING_VALUE}
        onValueChange={setBuildingSelection}
        options={[
          { value: NO_BUILDING_VALUE, label: t("noBuilding") },
          ...buildings.map((b) => ({ value: b.id, label: b.name })),
          { value: NEW_BUILDING_VALUE, label: t("createNewBuilding") },
        ]}
      />

      {!hasBuilding && (
        <>
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
        </>
      )}

      {isNewBuilding && (
        <div className="flex flex-col gap-4 rounded-md border border-border p-3">
          <p className="text-sm font-medium">{tb("createNewInlineTitle")}</p>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new_building_name">{tb("name")}</Label>
            <Input id="new_building_name" name="new_building_name" required />
          </div>
          <SelectField
            name="new_building_country_code"
            label={tb("country")}
            defaultValue={defaultCountryCode ?? countries[0]?.code}
            options={countries.map((c) => ({ value: c.code, label: c.name }))}
          />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new_building_city">{tb("city")}</Label>
            <Input id="new_building_city" name="new_building_city" required />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new_building_neighborhood">{tb("neighborhood")}</Label>
            <Input id="new_building_neighborhood" name="new_building_neighborhood" required />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="new_building_floors_count">{tb("floorsCount")}</Label>
            <Input
              id="new_building_floors_count"
              name="new_building_floors_count"
              type="number"
              min="0"
              step="1"
            />
          </div>
        </div>
      )}

      <div className="flex flex-col gap-1.5">
        <Label htmlFor="address_complement">
          {hasBuilding ? t("unitIdentifier") : t("addressComplement")}
        </Label>
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
