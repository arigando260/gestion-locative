import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLease } from "@/data/leases";
import { getInspection, getInspectionItemsWithPhotos } from "@/data/inspections";
import { InspectionItemCard } from "@/components/inspections/inspection-item-card";
import { TenantValidationForm } from "@/components/inspections/tenant-validation-form";
import { formatDateTime } from "@/lib/format-date";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

const TYPE_KEY: Record<string, string> = { entree: "typeEntree", sortie: "typeSortie" };
const VALIDATION_KEY: Record<string, string> = {
  en_attente: "validationEnAttente",
  valide: "validationValide",
  conteste: "validationConteste",
  accepte_tacitement: "validationAccepteTacitement",
};

export default async function TenantInspectionDetailPage({
  params,
}: PageProps<"/[locale]/tenant/leases/[leaseId]/inspections/[inspectionId]">) {
  const { locale, leaseId, inspectionId } = await params;
  const lease = await getMyLease(leaseId);
  const inspection = await getInspection(inspectionId);
  if (!lease || !inspection) notFound();

  const items = await getInspectionItemsWithPhotos(inspectionId);
  const t = await getTranslations("inspections");
  const tc = await getTranslations("common");

  // Défense en profondeur : RLS (Module 6k) empêche déjà la lecture d'un
  // brouillon par le locataire (getInspection renverrait null, notFound()
  // ci-dessus) et bloque l'écriture de tenant_validation_status avant
  // finalisation — cette condition ne devrait donc jamais être atteinte
  // par un brouillon, mais le formulaire ne doit pas en dépendre seul.
  const isPending =
    inspection.document_status === "finalise" &&
    inspection.effective_validation_status === "en_attente";

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/tenant/leases/${leaseId}/inspections`}
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {tc("back")}
      </Link>

      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>
            {t(TYPE_KEY[inspection.inspection_type ?? ""] ?? "typeEntree")} — {inspection.inspection_date}
          </CardTitle>
          <Badge variant="secondary">
            {t(VALIDATION_KEY[inspection.effective_validation_status ?? ""] ?? "validationEnAttente")}
          </Badge>
        </CardHeader>
        <CardContent className="flex flex-col gap-1 text-sm text-muted-foreground">
          {inspection.document_status === "finalise" && (
            <p>{t("finalizedOn", { date: formatDateTime(inspection.finalized_at, locale) })}</p>
          )}
          {inspection.tenant_validation_status === "valide" && (
            <p>{t("validatedOn", { date: formatDateTime(inspection.tenant_validation_at, locale) })}</p>
          )}
          {inspection.tenant_validation_status === "conteste" && (
            <p>{t("contestedOn", { date: formatDateTime(inspection.tenant_validation_at, locale) })}</p>
          )}
          {inspection.tenant_comments && (
            <p>
              {t("tenantComments")}: {inspection.tenant_comments}
            </p>
          )}
        </CardContent>
      </Card>

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
              canUpload={false}
            />
          ))}
        </div>
      </div>

      {isPending && (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle className="text-base">
              {t("validate")} / {t("contest")}
            </CardTitle>
          </CardHeader>
          <CardContent>
            <TenantValidationForm inspectionId={inspectionId} leaseId={leaseId} />
          </CardContent>
        </Card>
      )}
    </div>
  );
}
