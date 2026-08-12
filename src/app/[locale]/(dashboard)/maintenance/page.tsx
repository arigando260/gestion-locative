import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMaintenanceTickets } from "@/data/maintenance";
import { getProperties } from "@/data/properties";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { TicketList } from "@/components/maintenance/ticket-list";
import { TicketFilters } from "@/components/maintenance/ticket-filters";
import { Button } from "@/components/ui/button";
import type {
  MaintenanceTicketPriority,
  MaintenanceTicketStatus,
} from "@/data/maintenance";

const VALID_STATUSES: MaintenanceTicketStatus[] = ["signale", "en_cours", "resolu", "ferme"];
const VALID_PRIORITIES: MaintenanceTicketPriority[] = ["basse", "normale", "haute", "urgente"];

export default async function MaintenancePage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string; priority?: string; property_id?: string }>;
}) {
  const raw = await searchParams;
  const filters = {
    status: VALID_STATUSES.find((s) => s === raw.status),
    priority: VALID_PRIORITIES.find((p) => p === raw.priority),
    propertyId: raw.property_id || undefined,
  };

  const [tickets, properties, permissions] = await Promise.all([
    getMaintenanceTickets(filters),
    getProperties(),
    getCurrentUserPermissions(),
  ]);

  const t = await getTranslations("maintenance");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        {/* Aide à l'ergonomie uniquement : la policy RLS sur l'INSERT reste
            la seule autorité réelle, voir ARCHITECTURE.md. */}
        {can(permissions, "maintenance_tickets", "create") && (
          <Button render={<Link href="/maintenance/new" />} nativeButton={false}>
            {t("create")}
          </Button>
        )}
      </div>
      <TicketFilters filters={filters} properties={properties} />
      <TicketList tickets={tickets} />
    </div>
  );
}
