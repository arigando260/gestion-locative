import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge, type badgeVariants } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { VariantProps } from "class-variance-authority";
import type {
  MaintenanceTicketWithOrgAndProperty,
  MaintenanceTicketPriority,
  MaintenanceTicketStatus,
} from "@/data/maintenance";

type BadgeVariant = VariantProps<typeof badgeVariants>["variant"];

// Mêmes libellés/variantes que components/maintenance/ticket-list.tsx (côté
// staff) : redéfinis localement plutôt que partagés, comme le reste du
// projet le fait déjà pour ces petits dictionnaires (property-list.tsx,
// reservation-list.tsx...).
const STATUS_KEY: Record<MaintenanceTicketStatus, string> = {
  signale: "statusSignale",
  en_cours: "statusEnCours",
  resolu: "statusResolu",
  ferme: "statusFerme",
};
const STATUS_VARIANT: Record<MaintenanceTicketStatus, BadgeVariant> = {
  signale: "secondary",
  en_cours: "default",
  resolu: "outline",
  ferme: "ghost",
};
const PRIORITY_KEY: Record<MaintenanceTicketPriority, string> = {
  basse: "priorityBasse",
  normale: "priorityNormale",
  haute: "priorityHaute",
  urgente: "priorityUrgente",
};

export async function TenantTicketList({
  tickets,
}: {
  tickets: MaintenanceTicketWithOrgAndProperty[];
}) {
  const t = await getTranslations("maintenance");

  if (tickets.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("tenantEmpty")}</p>;
  }

  const row = (ticket: MaintenanceTicketWithOrgAndProperty) => ({
    property: ticket.properties?.name ?? "—",
    organization: ticket.organizations?.name ?? "—",
    statusLabel: t(STATUS_KEY[ticket.status]),
    statusVariant: STATUS_VARIANT[ticket.status],
    priorityLabel: t(PRIORITY_KEY[ticket.priority]),
    createdAt: ticket.created_at.slice(0, 10),
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("ticketTitle")}</TableHead>
              <TableHead>{t("property")}</TableHead>
              <TableHead>{t("organization")}</TableHead>
              <TableHead>{t("status")}</TableHead>
              <TableHead>{t("priority")}</TableHead>
              <TableHead>{t("createdAt")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {tickets.map((ticket) => {
              const r = row(ticket);
              return (
                <TableRow key={ticket.id}>
                  <TableCell>
                    <Link
                      href={`/tenant/maintenance/${ticket.id}`}
                      className="font-medium hover:underline"
                    >
                      {ticket.title}
                    </Link>
                  </TableCell>
                  <TableCell>{r.property}</TableCell>
                  <TableCell>{r.organization}</TableCell>
                  <TableCell>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </TableCell>
                  <TableCell>{r.priorityLabel}</TableCell>
                  <TableCell>{r.createdAt}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {tickets.map((ticket) => {
          const r = row(ticket);
          return (
            <Link key={ticket.id} href={`/tenant/maintenance/${ticket.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{ticket.title}</span>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">{r.organization}</span>
                  <span className="text-sm text-muted-foreground">{r.property}</span>
                  <span className="text-sm text-muted-foreground">
                    {r.priorityLabel} · {r.createdAt}
                  </span>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}
