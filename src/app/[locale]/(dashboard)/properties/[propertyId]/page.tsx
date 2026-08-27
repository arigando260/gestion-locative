import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  getPropertyWithEffectiveStatus,
  resolvePropertyAddress,
  type PropertyStatus,
} from "@/data/properties";
import { getPendingOrActiveLeaseForProperty } from "@/data/leases";
import { getPropertyTypes } from "@/data/property-types";
import { getPropertyTypeLabel } from "@/lib/property-type-labels";
import { formatPropertyAddress } from "@/lib/format-property-address";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import {
  getPropertyAgentAssignments,
  getAvailableAgentsForAssignment,
} from "@/data/property-agent-assignments";
import { listBuildings } from "@/data/buildings";
import { PropertyAgentAssignments } from "@/components/properties/property-agent-assignments";
import { PropertyBuildingAttachment } from "@/components/properties/property-building-attachment";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

// Un bail (Lease) n'a de sens que sur un bien loué à long terme. Le trigger
// validate_lease_property_location_type le refuserait de toute façon ; on
// évite juste de proposer une action vouée à échouer.
const LEASE_ELIGIBLE_TYPES = ["longue_duree"];

const STATUS_KEY: Record<PropertyStatus, string> = {
  disponible: "statusAvailable",
  occupe: "statusOccupied",
  en_travaux: "statusMaintenance",
};

export default async function PropertyPage({
  params,
}: PageProps<"/[locale]/properties/[propertyId]">) {
  const { propertyId } = await params;
  const [property, propertyTypes, permissions, pendingOrActiveLease, profile, resolvedAddress] =
    await Promise.all([
      getPropertyWithEffectiveStatus(propertyId),
      getPropertyTypes(),
      getCurrentUserPermissions(),
      getPendingOrActiveLeaseForProperty(propertyId),
      getCurrentProfile(),
      resolvePropertyAddress(propertyId),
    ]);

  if (!property) notFound();

  const t = await getTranslations("properties");
  const canCreateLease =
    can(permissions, "leases", "create") &&
    LEASE_ELIGIBLE_TYPES.includes(property.location_type) &&
    !pendingOrActiveLease;

  // Section "Agents assignés" : visible seulement pour un admin (seul rôle
  // détenant property_agent_assignments:create/delete, Module 12o) --
  // requêtes évitées pour tout autre rôle plutôt que récupérées puis
  // masquées.
  const canManageAgentAssignments = can(permissions, "property_agent_assignments", "create");
  const [agentAssignments, availableAgents] = canManageAgentAssignments && profile
    ? await Promise.all([
        getPropertyAgentAssignments(propertyId),
        getAvailableAgentsForAssignment(profile.organization_id, propertyId),
      ])
    : [[], []];

  // Rattachement à un immeuble (Module 13, point 4 du périmètre écran) :
  // proposé seulement si le bien n'en a pas déjà un et que l'appelant a le
  // droit de le modifier -- la vraie garantie reste properties_update, ce
  // gating n'est qu'ergonomique. Liste des immeubles récupérée seulement
  // dans ce cas, jamais pour un bien déjà rattaché.
  const canAttachBuilding = can(permissions, "properties", "update") && !property.building_id;
  const availableBuildings =
    canAttachBuilding && profile ? await listBuildings(profile.organization_id) : [];

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
          <p className="text-muted-foreground">{formatPropertyAddress(resolvedAddress)}</p>
          {resolvedAddress.building_name && (
            <p>
              {t("buildingLabel")}: {resolvedAddress.building_name}
            </p>
          )}
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
        {pendingOrActiveLease && (
          <Button
            className="w-fit"
            variant="outline"
            render={<Link href={`/leases/${pendingOrActiveLease.id}`} />}
            nativeButton={false}
          >
            {pendingOrActiveLease.status === "actif" ? t("viewActiveLease") : t("viewPendingLease")}
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
      </div>
      {canAttachBuilding && (
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{t("attachBuildingTitle")}</h2>
          <PropertyBuildingAttachment
            propertyId={property.id}
            availableBuildings={availableBuildings}
          />
        </div>
      )}
      {canManageAgentAssignments && (
        <PropertyAgentAssignments
          propertyId={property.id}
          assignments={agentAssignments}
          availableAgents={availableAgents}
        />
      )}
    </div>
  );
}
