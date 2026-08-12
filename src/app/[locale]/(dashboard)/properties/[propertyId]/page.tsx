import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getPropertyWithEffectiveStatus, type PropertyStatus } from "@/data/properties";
import { getActiveLeaseForProperty } from "@/data/leases";
import { getPropertyTypes } from "@/data/property-types";
import { getPropertyTypeLabel } from "@/lib/property-type-labels";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

// Un bail (Lease) n'a de sens que sur un bien loué à long terme — les biens
// courte_duree passent par les Réservations (Module 4), pas par cette page.
// Le trigger validate_lease_property_location_type le refuserait de toute
// façon ; on évite juste de proposer une action vouée à échouer.
const LEASE_ELIGIBLE_TYPES = ["longue_duree", "meuble_simple"];
const RESERVATION_ELIGIBLE_TYPES = ["courte_duree"];

const STATUS_KEY: Record<PropertyStatus, string> = {
  disponible: "statusAvailable",
  occupe: "statusOccupied",
  en_travaux: "statusMaintenance",
};

export default async function PropertyPage({
  params,
}: PageProps<"/[locale]/properties/[propertyId]">) {
  const { propertyId } = await params;
  const [property, propertyTypes, permissions, activeLease] = await Promise.all([
    getPropertyWithEffectiveStatus(propertyId),
    getPropertyTypes(),
    getCurrentUserPermissions(),
    getActiveLeaseForProperty(propertyId),
  ]);

  if (!property) notFound();

  const t = await getTranslations("properties");
  const tr = await getTranslations("reservations");
  const canCreateLease =
    can(permissions, "leases", "create") &&
    LEASE_ELIGIBLE_TYPES.includes(property.location_type);
  const canCreateReservation =
    can(permissions, "reservations", "create") &&
    RESERVATION_ELIGIBLE_TYPES.includes(property.location_type);

  return (
    <div className="flex flex-col gap-6">
      <Link href="/properties" className="text-sm text-muted-foreground hover:underline">
        ← {t("backToList")}
      </Link>
      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>{property.name}</CardTitle>
          <Badge variant="secondary">
            {t(STATUS_KEY[property.effective_status as PropertyStatus] ?? "status")}
          </Badge>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          <p className="text-muted-foreground">{property.address}</p>
          <p>
            {t("locationType")}:{" "}
            {getPropertyTypeLabel(propertyTypes, property.location_type, t)}
          </p>
          <p>
            {t("price")}: {property.price}
          </p>
        </CardContent>
      </Card>
      <div className="flex flex-wrap gap-2">
        {activeLease && (
          <Button
            className="w-fit"
            variant="outline"
            render={<Link href={`/leases/${activeLease.id}`} />}
            nativeButton={false}
          >
            {t("viewActiveLease")}
          </Button>
        )}
        {canCreateLease && (
          <Button
            className="w-fit"
            render={<Link href={`/properties/${property.id}/leases/new`} />}
            nativeButton={false}
          >
            {t("createNewLease")}
          </Button>
        )}
        {canCreateReservation && (
          <Button
            className="w-fit"
            variant="outline"
            render={<Link href={`/properties/${property.id}/reservations/new`} />}
            nativeButton={false}
          >
            {tr("create")}
          </Button>
        )}
      </div>
    </div>
  );
}
