import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getInspection, getInspectionItemsWithPhotos } from "@/data/inspections";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { formatDate, formatDateTime } from "@/lib/format-date";
import { InspectionItemForm } from "@/components/inspections/inspection-item-form";
import { InspectionItemCard } from "@/components/inspections/inspection-item-card";
import { FinalizeInspectionForm } from "@/components/inspections/finalize-inspection-form";
import { ObservationsForm } from "@/components/inspections/observations-form";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const TYPE_KEY: Record<string, string> = { entree: "typeEntree", sortie: "typeSortie" };
const DOCUMENT_STATUS_KEY: Record<string, string> = {
  brouillon: "documentStatusBrouillon",
  finalise: "documentStatusFinalise",
};

export default async function InspectionDetailPage({
  params,
}: PageProps<"/[locale]/leases/[leaseId]/inspections/[inspectionId]">) {
  const { locale, leaseId, inspectionId } = await params;
  const [lease, inspection, permissions] = await Promise.all([
    getLease(leaseId),
    getInspection(inspectionId),
    getCurrentUserPermissions(),
  ]);

  if (!lease || !inspection) notFound();

  const items = await getInspectionItemsWithPhotos(inspectionId);
  const t = await getTranslations("inspections");

  const isDraft = inspection.document_status === "brouillon";
  const canManage = can(permissions, "property_inspections", "update");

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/leases/${leaseId}/inspections`}
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {t("title")}
      </Link>

      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>
            {t(TYPE_KEY[inspection.inspection_type ?? ""] ?? "typeEntree")} — {formatDate(inspection.inspection_date, locale)}
          </CardTitle>
          <Badge variant="secondary">
            {t(DOCUMENT_STATUS_KEY[inspection.document_status ?? ""] ?? "documentStatusBrouillon")}
          </Badge>
        </CardHeader>
        {inspection.document_status === "finalise" && (
          <CardContent className="text-sm text-muted-foreground">
            {t("finalizedOn", { date: formatDateTime(inspection.finalized_at, locale) })}
          </CardContent>
        )}
      </Card>

      {canManage && isDraft ? (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle className="text-base">{t("observations")}</CardTitle>
          </CardHeader>
          <CardContent>
            <ObservationsForm
              inspectionId={inspectionId}
              leaseId={leaseId}
              observations={inspection.observations}
            />
          </CardContent>
        </Card>
      ) : (
        inspection.observations && (
          <Card className="max-w-md">
            <CardHeader>
              <CardTitle className="text-base">{t("observations")}</CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-sm whitespace-pre-wrap">{inspection.observations}</p>
            </CardContent>
          </Card>
        )
      )}

      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("items")}</h2>
        {items.length === 0 && (
          <p className="text-sm text-muted-foreground">{t("empty")}</p>
        )}
        <div className="grid gap-3 sm:grid-cols-2">
          {items.map((item) => (
            <InspectionItemCard
              key={item.id}
              item={item}
              organizationId={lease.organization_id}
              inspectionId={inspection.id ?? inspectionId}
              leaseId={leaseId}
              canUpload={canManage && isDraft}
            />
          ))}
        </div>
      </div>

      {canManage && isDraft && (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle className="text-base">{t("addItem")}</CardTitle>
          </CardHeader>
          <CardContent>
            <InspectionItemForm inspectionId={inspectionId} leaseId={leaseId} />
          </CardContent>
        </Card>
      )}

      {canManage && isDraft && (
        <FinalizeInspectionForm inspectionId={inspectionId} leaseId={leaseId} />
      )}
    </div>
  );
}
