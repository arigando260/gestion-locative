import { getTranslations } from "next-intl/server";
import { getPropertyTypes } from "@/data/property-types";
import { getCountries } from "@/data/countries";
import { getCurrentProfile } from "@/data/session";
import { getOrganization } from "@/data/organizations";
import { PropertyForm } from "@/components/properties/property-form";

export default async function NewPropertyPage() {
  const propertyTypes = await getPropertyTypes();
  const countries = await getCountries();
  const t = await getTranslations("properties");

  // Pays hérité de l'organisation par défaut, modifiable par bien (décision
  // Module 12, conception adresse structurée) — profile ne porte que
  // organization_id, un aller supplémentaire est nécessaire pour son
  // country_code.
  const profile = await getCurrentProfile();
  const organization = profile ? await getOrganization(profile.organization_id) : null;

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <PropertyForm
        propertyTypes={propertyTypes}
        countries={countries}
        defaultCountryCode={organization?.country_code}
      />
    </div>
  );
}
