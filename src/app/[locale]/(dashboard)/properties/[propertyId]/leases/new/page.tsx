import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { getProperty } from "@/data/properties";
import { getTenantsForOrg } from "@/data/leases";
import { LeaseForm } from "@/components/leases/lease-form";

export default async function NewLeasePage({
  params,
}: PageProps<"/[locale]/properties/[propertyId]/leases/new">) {
  const { propertyId } = await params;
  const [property, tenants] = await Promise.all([
    getProperty(propertyId),
    getTenantsForOrg(),
  ]);

  if (!property) notFound();

  const t = await getTranslations("leases");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">
        {t("createTitle")} — {property.name}
      </h1>
      <LeaseForm propertyId={property.id} tenants={tenants} />
    </div>
  );
}
