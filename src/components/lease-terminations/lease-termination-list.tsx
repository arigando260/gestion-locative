import { getTranslations, getLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { formatDate, formatDateTime } from "@/lib/format-date";
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
  LeaseTerminationRequestWithContext,
  LeaseTerminationStatus,
} from "@/data/lease-terminations";

type BadgeVariant = VariantProps<typeof badgeVariants>["variant"];

// Dictionnaires redéfinis localement plutôt que partagés — même convention
// que components/maintenance/ticket-list.tsx et tenant-ticket-list.tsx.
const STATUS_KEY: Record<LeaseTerminationStatus, string> = {
  en_attente: "statusEnAttente",
  validee: "statusValidee",
  refusee: "statusRefusee",
  annulee: "statusAnnulee",
};
const STATUS_VARIANT: Record<LeaseTerminationStatus, BadgeVariant> = {
  en_attente: "secondary",
  validee: "default",
  refusee: "destructive",
  annulee: "outline",
};

export async function LeaseTerminationList({
  requests,
}: {
  requests: LeaseTerminationRequestWithContext[];
}) {
  const t = await getTranslations("leaseTerminations");
  const locale = await getLocale();

  if (requests.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (request: LeaseTerminationRequestWithContext) => ({
    property: request.leases?.properties?.name ?? "—",
    initiator: t(request.initiated_by_tenant_id ? "initiatorTenant" : "initiatorStaff"),
    statusLabel: t(STATUS_KEY[request.status]),
    statusVariant: STATUS_VARIANT[request.status],
    createdAt: formatDateTime(request.created_at, locale),
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("property")}</TableHead>
              <TableHead>{t("initiatedBy")}</TableHead>
              <TableHead>{t("requestedEndDate")}</TableHead>
              <TableHead>{t("status")}</TableHead>
              <TableHead>{t("createdAt")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {requests.map((request) => {
              const r = row(request);
              return (
                <TableRow key={request.id}>
                  <TableCell>
                    <Link
                      href={`/lease-terminations/${request.id}`}
                      className="font-medium hover:underline"
                    >
                      {r.property}
                    </Link>
                  </TableCell>
                  <TableCell>{r.initiator}</TableCell>
                  <TableCell>{formatDate(request.requested_end_date, locale)}</TableCell>
                  <TableCell>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </TableCell>
                  <TableCell>{r.createdAt}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {requests.map((request) => {
          const r = row(request);
          return (
            <Link key={request.id} href={`/lease-terminations/${request.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{r.property}</span>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">
                    {t("initiatedBy")}: {r.initiator}
                  </span>
                  <span className="text-sm text-muted-foreground">
                    {t("requestedEndDate")}: {formatDate(request.requested_end_date, locale)}
                  </span>
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
