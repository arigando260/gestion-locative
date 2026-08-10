import { getTranslations } from "next-intl/server";
import { getPropertyTypes } from "@/data/property-types";
import { PropertyForm } from "@/components/properties/property-form";

export default async function NewPropertyPage() {
  const propertyTypes = await getPropertyTypes();
  const t = await getTranslations("properties");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <PropertyForm propertyTypes={propertyTypes} />
    </div>
  );
}
