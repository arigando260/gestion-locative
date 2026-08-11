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
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { LeaseWithContext } from "@/data/leases";

const STATUS_KEY: Record<string, string> = {
  actif: "statusActif",
  termine: "statusTermine",
  resilie: "statusResilie",
};

export async function TenantLeaseList({
  leases,
}: {
  leases: LeaseWithContext[];
}) {
  const t = await getTranslations("tenant");

  if (leases.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("noLeases")}</p>;
  }

  const row = (lease: LeaseWithContext) => ({
    property: lease.properties?.name ?? "—",
    address: lease.properties?.address ?? "",
    organization: lease.organizations?.name ?? "—",
    statusLabel: t(STATUS_KEY[lease.status] ?? "statusActif"),
    rent: lease.rent_amount,
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("organization")}</TableHead>
              <TableHead>{t("property")}</TableHead>
              <TableHead>{t("status")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {leases.map((lease) => {
              const r = row(lease);
              return (
                <TableRow key={lease.id}>
                  <TableCell>{r.organization}</TableCell>
                  <TableCell>
                    <Link
                      href={`/tenant/leases/${lease.id}`}
                      className="font-medium hover:underline"
                    >
                      {r.property}
                    </Link>
                    <div className="text-sm text-muted-foreground">{r.address}</div>
                  </TableCell>
                  <TableCell>
                    <Badge variant="secondary">{r.statusLabel}</Badge>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {leases.map((lease) => {
          const r = row(lease);
          return (
            <Link key={lease.id} href={`/tenant/leases/${lease.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{r.property}</span>
                    <Badge variant="secondary">{r.statusLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">{r.organization}</span>
                  <span className="text-sm text-muted-foreground">{r.address}</span>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}
