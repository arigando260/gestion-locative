import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLease } from "@/data/leases";
import { getInspectionsForLease } from "@/data/inspections";
import { InspectionList } from "@/components/inspections/inspection-list";

export default async function TenantLeaseInspectionsPage({
  params,
}: PageProps<"/[locale]/tenant/leases/[leaseId]/inspections">) {
  const { leaseId } = await params;
  const lease = await getMyLease(leaseId);
  if (!lease) notFound();

  const inspections = await getInspectionsForLease(leaseId);
  const t = await getTranslations("inspections");
  const tc = await getTranslations("common");

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/tenant/leases/${leaseId}`}
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {tc("back")}
      </Link>
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <InspectionList
        inspections={inspections}
        basePath={`/tenant/leases/${leaseId}/inspections`}
      />
    </div>
  );
}
