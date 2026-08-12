import { getTranslations } from "next-intl/server";
import { getMyLeases } from "@/data/leases";
import { TenantTicketForm } from "@/components/maintenance/tenant-ticket-form";

export default async function NewTenantMaintenanceTicketPage() {
  const leases = await getMyLeases();
  const activeLeases = leases.filter((lease) => lease.status === "actif");
  const t = await getTranslations("maintenance");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("reportTitle")}</h1>
      <TenantTicketForm activeLeases={activeLeases} />
    </div>
  );
}
