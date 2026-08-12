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
  MaintenanceTicketWithProperty,
  MaintenanceTicketPriority,
  MaintenanceTicketStatus,
} from "@/data/maintenance";

type BadgeVariant = VariantProps<typeof badgeVariants>["variant"];

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
const PRIORITY_VARIANT: Record<MaintenanceTicketPriority, BadgeVariant> = {
  basse: "outline",
  normale: "secondary",
  haute: "default",
  urgente: "destructive",
};

export async function TicketList({
  tickets,
}: {
  tickets: MaintenanceTicketWithProperty[];
}) {
  const t = await getTranslations("maintenance");

  if (tickets.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (ticket: MaintenanceTicketWithProperty) => ({
    property: ticket.properties?.name ?? "—",
    statusLabel: t(STATUS_KEY[ticket.status]),
    statusVariant: STATUS_VARIANT[ticket.status],
    priorityLabel: t(PRIORITY_KEY[ticket.priority]),
    priorityVariant: PRIORITY_VARIANT[ticket.priority],
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
              <TableHead>{t("status")}</TableHead>
              <TableHead>{t("priority")}</TableHead>
              <TableHead>{t("actualCost")}</TableHead>
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
                      href={`/maintenance/${ticket.id}`}
                      className="font-medium hover:underline"
                    >
                      {ticket.title}
                    </Link>
                  </TableCell>
                  <TableCell>{r.property}</TableCell>
                  <TableCell>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant={r.priorityVariant}>{r.priorityLabel}</Badge>
                  </TableCell>
                  <TableCell>{ticket.actual_cost ?? "—"}</TableCell>
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
            <Link key={ticket.id} href={`/maintenance/${ticket.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{ticket.title}</span>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">{r.property}</span>
                  <div className="flex items-center gap-2">
                    <Badge variant={r.priorityVariant}>{r.priorityLabel}</Badge>
                    {ticket.actual_cost != null && (
                      <span className="text-sm text-muted-foreground">
                        {ticket.actual_cost}
                      </span>
                    )}
                  </div>
                  <span className="text-sm text-muted-foreground">{r.createdAt}</span>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}
