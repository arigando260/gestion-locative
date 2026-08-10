import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getProperties } from "@/data/properties";
import { getPropertyTypes } from "@/data/property-types";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { PropertyList } from "@/components/properties/property-list";
import { Button } from "@/components/ui/button";

export default async function PropertiesPage() {
  const [properties, propertyTypes, permissions] = await Promise.all([
    getProperties(),
    getPropertyTypes(),
    getCurrentUserPermissions(),
  ]);
  const t = await getTranslations("properties");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        {/* Aide à l'ergonomie uniquement : la policy RLS sur l'INSERT reste
            la seule autorité réelle, voir ARCHITECTURE.md. */}
        {can(permissions, "properties", "create") && (
          <Button render={<Link href="/properties/new" />} nativeButton={false}>
            {t("create")}
          </Button>
        )}
      </div>
      <PropertyList properties={properties} propertyTypes={propertyTypes} />
    </div>
  );
}
