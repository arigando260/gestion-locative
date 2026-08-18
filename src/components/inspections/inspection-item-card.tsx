import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { PhotoUploadField } from "@/components/inspections/photo-upload-field";
import { InspectionItemBody } from "@/components/inspections/inspection-item-body";
import type { InspectionItemWithPhotos } from "@/data/inspections";
import { getSignedPhotoUrls } from "@/data/inspections";

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
  const signedUrls = await getSignedPhotoUrls(
    item.inspection_photos.map((photo) => photo.storage_path)
  );
  const photos = item.inspection_photos.map((photo) => ({
    id: photo.id,
    storage_path: photo.storage_path,
    url: signedUrls[photo.storage_path] ?? null,
  }));

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{item.zone}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3 text-sm">
        <InspectionItemBody
          item={item}
          inspectionId={inspectionId}
          leaseId={leaseId}
          canManage={canUpload}
        />
        <PhotoUploadField
          organizationId={organizationId}
          inspectionId={inspectionId}
          inspectionItemId={item.id}
          leaseId={leaseId}
          photos={photos}
          canUpload={canUpload}
        />
      </CardContent>
    </Card>
  );
}
