import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getPropertiesWithEffectiveStatus, resolvePropertyAddresses } from "@/data/properties";
import { getPropertyTypes } from "@/data/property-types";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getCurrentProfile } from "@/data/session";
import {
  getClosurePendingPropertyIds,
  resolvePropertyParkStatus,
  type PropertyParkStatus,
} from "@/data/lease-closure";
import { PropertyList } from "@/components/properties/property-list";
import { Button } from "@/components/ui/button";

const VALID_PARK_STATUSES: PropertyParkStatus[] = [
  "occupe",
  "disponible",
  "en_travaux",
  "en_preparation_sortie",
];

export default async function PropertiesPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const profile = await getCurrentProfile();
  if (!profile) return null;

  const raw = await searchParams;
  const statusFilter = VALID_PARK_STATUSES.find((s) => s === raw.status);

  // Même correspondance que la puce "État du parc" du tableau de bord
  // (resolvePropertyParkStatus, data/lease-closure.ts) -- jamais un second
  // calcul qui pourrait diverger des totaux déjà vérifiés là-bas.
  const [allProperties, propertyTypes, permissions, closurePropertyIds] = await Promise.all([
    getPropertiesWithEffectiveStatus(),
    getPropertyTypes(),
    getCurrentUserPermissions(),
    statusFilter
      ? getClosurePendingPropertyIds(profile.organization_id)
      : Promise.resolve(new Set<string>()),
  ]);

  const properties = statusFilter
    ? allProperties.filter(
        (p) => resolvePropertyParkStatus(p.id, p.effective_status, closurePropertyIds) === statusFilter
      )
    : allProperties;

  const addresses = await resolvePropertyAddresses(properties.map((p) => p.id));
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
      <PropertyList properties={properties} propertyTypes={propertyTypes} addresses={addresses} />
    </div>
  );
}
