import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { getProperty } from "@/data/properties";
import { getTenantsForOrg } from "@/data/leases";
import { ReservationForm } from "@/components/reservations/reservation-form";

export default async function NewReservationPage({
  params,
}: PageProps<"/[locale]/properties/[propertyId]/reservations/new">) {
  const { propertyId } = await params;
  const [property, tenants] = await Promise.all([
    getProperty(propertyId),
    getTenantsForOrg(),
  ]);

  if (!property || property.location_type !== "courte_duree") notFound();

  const t = await getTranslations("reservations");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">
        {t("createTitle")} — {property.name}
      </h1>
      <ReservationForm propertyId={property.id} tenants={tenants} />
    </div>
  );
}
