import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { PropertyWithEffectiveStatus, PropertyStatus } from "@/data/properties";
import { getPropertyTypeLabel, type PropertyType } from "@/lib/property-type-labels";
import { formatPropertyAddress } from "@/lib/format-property-address";

const STATUS_KEY: Record<PropertyStatus, string> = {
  disponible: "statusAvailable",
  occupe: "statusOccupied",
  en_travaux: "statusMaintenance",
};

export async function PropertyList({
  properties,
  propertyTypes,
}: {
  properties: PropertyWithEffectiveStatus[];
  propertyTypes: PropertyType[];
}) {
  const t = await getTranslations("properties");

  if (properties.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  return (
    <>
      {/* Table à partir de sm : liste de cartes empilées en dessous — la
          contrainte "mobile et ordinateur à parts égales" exclut de se
          contenter d'un simple défilement horizontal de tableau sur petit
          écran. */}
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("name")}</TableHead>
              <TableHead>{t("address")}</TableHead>
              <TableHead>{t("locationType")}</TableHead>
              <TableHead>{t("price")}</TableHead>
              <TableHead>{t("status")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {properties.map((property) => (
              <TableRow key={property.id}>
                <TableCell>
                  <Link
                    href={`/properties/${property.id}`}
                    className="font-medium hover:underline"
                  >
                    {property.name}
                  </Link>
                </TableCell>
                <TableCell>{formatPropertyAddress(property)}</TableCell>
                <TableCell>
                  {getPropertyTypeLabel(propertyTypes, property.location_type, t)}
                </TableCell>
                <TableCell>{property.price}</TableCell>
                <TableCell>
                  <Badge variant="secondary">
                    {t(STATUS_KEY[property.effective_status as PropertyStatus] ?? "status")}
                  </Badge>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {properties.map((property) => (
          <Link key={property.id} href={`/properties/${property.id}`}>
            <Card>
              <CardContent className="flex flex-col gap-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium">{property.name}</span>
                  <Badge variant="secondary">
                    {t(STATUS_KEY[property.effective_status as PropertyStatus] ?? "status")}
                  </Badge>
                </div>
                <span className="text-sm text-muted-foreground">
                  {formatPropertyAddress(property)}
                </span>
                <span className="text-sm text-muted-foreground">
                  {getPropertyTypeLabel(propertyTypes, property.location_type, t)}{" "}
                  · {property.price}
                </span>
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </>
  );
}
