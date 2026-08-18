import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getDraftInspectionForLease } from "@/data/inspections";
import { InspectionForm } from "@/components/inspections/inspection-form";

export default async function NewInspectionPage({
  params,
  searchParams,
}: PageProps<"/[locale]/leases/[leaseId]/inspections/new">) {
  const { locale, leaseId } = await params;
  const raw = await searchParams;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const defaultType = raw.type === "entree" || raw.type === "sortie" ? raw.type : undefined;

  // Un brouillon existant (même type si précisé via ?type=, sinon tout
  // type) est repris plutôt que dupliqué — voir getDraftInspectionForLease.
  const draft = await getDraftInspectionForLease(leaseId, defaultType);
  if (draft) {
    redirect({ href: `/leases/${leaseId}/inspections/${draft.id}`, locale });
  }

  const t = await getTranslations("inspections");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <InspectionForm leaseId={lease.id} defaultType={defaultType} />
    </div>
  );
}
