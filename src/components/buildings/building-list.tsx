import { getTranslations } from "next-intl/server";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import type { BuildingWithUnitsCount } from "@/data/buildings";

// Formatage propre à l'immeuble lui-même (pas d'héritage/résolution comme
// pour un bien -- un immeuble EST la source de l'adresse, jamais rattaché à
// autre chose) : même convention visuelle que formatPropertyAddress
// ("Quartier, Ville — Complément"), mais pas la même fonction, ce n'est pas
// la logique de private.resolve_property_address qu'on dupliquerait ici.
function formatBuildingAddress(building: BuildingWithUnitsCount): string {
  const location = [building.neighborhood, building.city].filter(Boolean).join(", ");
  if (location && building.address_complement) {
    return `${location} — ${building.address_complement}`;
  }
  return location || building.address_complement || "—";
}

// Même patron responsive que PropertyList (Module 2) : table à partir de sm,
// cartes empilées en dessous.
export async function BuildingList({ buildings }: { buildings: BuildingWithUnitsCount[] }) {
  const t = await getTranslations("buildings");

  if (buildings.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("name")}</TableHead>
              <TableHead>{t("address")}</TableHead>
              <TableHead>{t("unitsCount")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {buildings.map((building) => (
              <TableRow key={building.id}>
                <TableCell className="font-medium">{building.name}</TableCell>
                <TableCell>{formatBuildingAddress(building)}</TableCell>
                <TableCell>{building.units_count}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {buildings.map((building) => (
          <Card key={building.id}>
            <CardContent className="flex flex-col gap-1">
              <span className="font-medium">{building.name}</span>
              <span className="text-sm text-muted-foreground">
                {formatBuildingAddress(building)}
              </span>
              <span className="text-sm text-muted-foreground">
                {t("unitsCount")}: {building.units_count}
              </span>
            </CardContent>
          </Card>
        ))}
      </div>
    </>
  );
}
