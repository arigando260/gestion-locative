import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getInspectionsForLease, getAvailableInspectionTypes } from "@/data/inspections";
import { isLeaseClosureEngaged } from "@/data/lease-closure";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { InspectionList } from "@/components/inspections/inspection-list";
import { Button } from "@/components/ui/button";

export default async function LeaseInspectionsPage({
  params,
}: PageProps<"/[locale]/leases/[leaseId]/inspections">) {
  const { leaseId } = await params;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const closureEngaged = isLeaseClosureEngaged({
    status: lease.status,
    keys_returned_at: lease.keys_returned_at,
  });

  const [inspections, permissions, availableTypes] = await Promise.all([
    getInspectionsForLease(leaseId),
    getCurrentUserPermissions(),
    getAvailableInspectionTypes(leaseId, closureEngaged),
  ]);

  const t = await getTranslations("inspections");
  const tc = await getTranslations("common");

  return (
    <div className="flex flex-col gap-6">
      <Link
        href={`/leases/${leaseId}`}
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {tc("back")}
      </Link>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        {can(permissions, "property_inspections", "create") &&
          (availableTypes.length > 0 ? (
            <Button render={<Link href={`/leases/${leaseId}/inspections/new`} />} nativeButton={false}>
              {t("create")}
            </Button>
          ) : (
            <p className="text-sm text-muted-foreground">{t("noAvailableTypes")}</p>
          ))}
      </div>
      <InspectionList
        inspections={inspections}
        basePath={`/leases/${leaseId}/inspections`}
      />
    </div>
  );
}
