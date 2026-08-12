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
  LeaseTerminationRequestWithOrgContext,
  LeaseTerminationStatus,
} from "@/data/lease-terminations";

type BadgeVariant = VariantProps<typeof badgeVariants>["variant"];

// Mêmes libellés/variantes que lease-termination-list.tsx (côté staff) :
// redéfinis localement, même convention que le module maintenance.
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

export async function TenantLeaseTerminationList({
  requests,
}: {
  requests: LeaseTerminationRequestWithOrgContext[];
}) {
  const t = await getTranslations("leaseTerminations");

  if (requests.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("tenantEmpty")}</p>;
  }

  const row = (request: LeaseTerminationRequestWithOrgContext) => ({
    property: request.leases?.properties?.name ?? "—",
    organization: request.leases?.organizations?.name ?? "—",
    initiator: t(request.initiated_by_tenant_id ? "initiatorTenant" : "initiatorStaff"),
    statusLabel: t(STATUS_KEY[request.status]),
    statusVariant: STATUS_VARIANT[request.status],
    createdAt: request.created_at.slice(0, 10),
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("property")}</TableHead>
              <TableHead>{t("organization")}</TableHead>
              <TableHead>{t("initiatedBy")}</TableHead>
              <TableHead>{t("requestedEndDate")}</TableHead>
              <TableHead>{t("status")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {requests.map((request) => {
              const r = row(request);
              return (
                <TableRow key={request.id}>
                  <TableCell>
                    <Link
                      href={`/tenant/lease-terminations/${request.id}`}
                      className="font-medium hover:underline"
                    >
                      {r.property}
                    </Link>
                  </TableCell>
                  <TableCell>{r.organization}</TableCell>
                  <TableCell>{r.initiator}</TableCell>
                  <TableCell>{request.requested_end_date}</TableCell>
                  <TableCell>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </TableCell>
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
            <Link key={request.id} href={`/tenant/lease-terminations/${request.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{r.property}</span>
                    <Badge variant={r.statusVariant}>{r.statusLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">{r.organization}</span>
                  <span className="text-sm text-muted-foreground">
                    {t("initiatedBy")}: {r.initiator}
                  </span>
                  <span className="text-sm text-muted-foreground">
                    {t("requestedEndDate")}: {request.requested_end_date}
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
