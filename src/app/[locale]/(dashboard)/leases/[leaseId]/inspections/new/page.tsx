import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { getLease } from "@/data/leases";
import { InspectionForm } from "@/components/inspections/inspection-form";

export default async function NewInspectionPage({
  params,
  searchParams,
}: PageProps<"/[locale]/leases/[leaseId]/inspections/new">) {
  const { leaseId } = await params;
  const raw = await searchParams;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const t = await getTranslations("inspections");
  const defaultType = raw.type === "entree" || raw.type === "sortie" ? raw.type : undefined;

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <InspectionForm leaseId={lease.id} defaultType={defaultType} />
    </div>
  );
}
