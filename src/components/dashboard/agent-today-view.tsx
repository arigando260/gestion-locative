import { getTranslations } from "next-intl/server";
import { CheckCircle2 } from "lucide-react";
import { getLeasesNeedingEntryInspection } from "@/data/lease-closure";
import { getLeasesWithOverduePayments } from "@/data/schedules";
import { getMaintenanceTickets } from "@/data/maintenance";
import { formatDate } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import { AlertRow } from "@/components/dashboard/alert-row";
import { Card } from "@/components/ui/card";

type Task = React.ComponentProps<typeof AlertRow>;

export async function AgentTodayView({
  organizationId,
  profileName,
  locale,
}: {
  organizationId: string;
  profileName: string;
  locale: string;
}) {
  const t = await getTranslations("dashboard");

  const [needingInspection, overduePayments, tickets] = await Promise.all([
    getLeasesNeedingEntryInspection(organizationId),
    getLeasesWithOverduePayments(organizationId),
    getMaintenanceTickets({}),
  ]);

  const openTickets = tickets.filter(
    (ticket) => ticket.status === "signale" || ticket.status === "en_cours"
  );

  const tasks: Task[] = [
    ...needingInspection.map((lease) => ({
      name: lease.tenant_full_name ?? lease.property_name,
      subtitle: lease.property_name,
      badgeLabel: t("kindEtatDesLieux"),
      badgeVariant: "warning" as const,
      actionLabel: t("startInspection"),
      actionHref: `/leases/${lease.lease_id}/inspections/new`,
    })),
    ...overduePayments.map((lease) => ({
      name: lease.tenant_full_name ?? lease.property_name,
      subtitle: lease.property_name,
      meta: formatCurrency(lease.amount_due, locale),
      metaCaption: formatDate(lease.due_date, locale),
      badgeLabel: t("kindRelance"),
      badgeVariant: "danger" as const,
      actionLabel: t("viewDetails"),
      actionHref: `/leases/${lease.lease_id}`,
    })),
    ...openTickets.map((ticket) => ({
      name: ticket.title,
      subtitle: ticket.properties?.name ?? "—",
      badgeLabel: t("kindIntervention"),
      badgeVariant: "warning" as const,
      actionLabel: t("viewDetails"),
      actionHref: `/maintenance/${ticket.id}`,
    })),
  ];

  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">
          {t("greeting", { name: profileName })}
        </h1>
        <p className="mt-1 text-[13.5px] text-muted-foreground">
          {t("agentSubtitle", { count: tasks.length })}
        </p>
      </div>

      {tasks.length === 0 ? (
        <Card className="flex-row items-center gap-3 border-l-[3px] border-l-status-success-fg p-5">
          <CheckCircle2 className="size-5 shrink-0 text-status-success-fg" />
          <div>
            <div className="text-[15px] font-bold">{t("agentAllClearTitle")}</div>
            <div className="text-[13px] text-muted-foreground">{t("agentAllClearBody")}</div>
          </div>
        </Card>
      ) : (
        <Card className="p-0">
          <div className="px-[22px] pt-4 pb-1 text-[15px] font-bold">{t("todoTitle")}</div>
          <div className="flex flex-col">
            {tasks.map((task, i) => (
              <AlertRow key={`${task.actionHref}-${i}`} {...task} />
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
