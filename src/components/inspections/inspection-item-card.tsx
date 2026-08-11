import { getTranslations } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { PhotoUploadField } from "@/components/inspections/photo-upload-field";
import type { InspectionItemWithPhotos } from "@/data/inspections";
import { getSignedPhotoUrls } from "@/data/inspections";

const CONDITION_KEY: Record<string, string> = {
  bon: "conditionBon",
  usage_normal: "conditionUsageNormal",
  degrade: "conditionDegrade",
  hors_service: "conditionHorsService",
};

export async function InspectionItemCard({
  item,
  organizationId,
  inspectionId,
  leaseId,
  canUpload,
}: {
  item: InspectionItemWithPhotos;
  organizationId: string;
  inspectionId: string;
  leaseId: string;
  canUpload: boolean;
}) {
  const t = await getTranslations("inspections");
  const signedUrls = await getSignedPhotoUrls(
    item.inspection_photos.map((photo) => photo.storage_path)
  );

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{item.zone}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        <p className="text-muted-foreground">
          {t("condition")}: {t(CONDITION_KEY[item.condition] ?? "conditionBon")}
        </p>
        {item.description && <p>{item.description}</p>}
        {item.estimated_repair_cost != null && (
          <p className="text-muted-foreground">
            {t("estimatedRepairCost")}: {item.estimated_repair_cost}
          </p>
        )}
        {item.inspection_photos.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {item.inspection_photos.map((photo) => {
              const url = signedUrls[photo.storage_path];
              return url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  key={photo.id}
                  src={url}
                  alt=""
                  className="h-24 w-24 rounded-md object-cover"
                />
              ) : null;
            })}
          </div>
        )}
        {canUpload && (
          <PhotoUploadField
            organizationId={organizationId}
            inspectionId={inspectionId}
            inspectionItemId={item.id}
            leaseId={leaseId}
          />
        )}
      </CardContent>
    </Card>
  );
}
