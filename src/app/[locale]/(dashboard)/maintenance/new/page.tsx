import { getTranslations } from "next-intl/server";
import { getProperties } from "@/data/properties";
import { getLeasesForOrg } from "@/data/leases";
import { TicketForm } from "@/components/maintenance/ticket-form";

export default async function NewMaintenanceTicketPage() {
  const [properties, leases] = await Promise.all([getProperties(), getLeasesForOrg()]);
  const t = await getTranslations("maintenance");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <TicketForm properties={properties} leases={leases} />
    </div>
  );
}
