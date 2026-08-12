import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyMaintenanceTickets } from "@/data/maintenance";
import { TenantTicketList } from "@/components/maintenance/tenant-ticket-list";
import { Button } from "@/components/ui/button";

export default async function TenantMaintenancePage() {
  const tickets = await getMyMaintenanceTickets();
  const t = await getTranslations("maintenance");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <Button render={<Link href="/tenant/maintenance/new" />} nativeButton={false}>
          {t("reportSubmit")}
        </Button>
      </div>
      <TenantTicketList tickets={tickets} />
    </div>
  );
}
