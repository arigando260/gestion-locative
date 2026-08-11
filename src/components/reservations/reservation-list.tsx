import { getTranslations } from "next-intl/server";
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
import type { ReservationWithProperty } from "@/data/reservations";

const STATUS_KEY: Record<string, string> = {
  confirmee: "statusConfirmee",
  annulee: "statusAnnulee",
  terminee: "statusTerminee",
};

export async function ReservationList({
  reservations,
}: {
  reservations: ReservationWithProperty[];
}) {
  const t = await getTranslations("reservations");

  if (reservations.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (reservation: ReservationWithProperty) => ({
    property: reservation.properties?.name ?? "—",
    checkIn: reservation.check_in_date,
    checkOut: reservation.check_out_date,
    total: reservation.total_amount,
    statusLabel: t(STATUS_KEY[reservation.status] ?? "statusConfirmee"),
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("property")}</TableHead>
              <TableHead>{t("checkIn")}</TableHead>
              <TableHead>{t("checkOut")}</TableHead>
              <TableHead>{t("totalAmount")}</TableHead>
              <TableHead>{t("status")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {reservations.map((reservation) => {
              const r = row(reservation);
              return (
                <TableRow key={reservation.id}>
                  <TableCell className="font-medium">{r.property}</TableCell>
                  <TableCell>{r.checkIn}</TableCell>
                  <TableCell>{r.checkOut}</TableCell>
                  <TableCell>{r.total}</TableCell>
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
        {reservations.map((reservation) => {
          const r = row(reservation);
          return (
            <Card key={reservation.id}>
              <CardContent className="flex flex-col gap-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium">{r.property}</span>
                  <Badge variant="secondary">{r.statusLabel}</Badge>
                </div>
                <span className="text-sm text-muted-foreground">
                  {r.checkIn} → {r.checkOut}
                </span>
                <span className="text-sm text-muted-foreground">{r.total}</span>
              </CardContent>
            </Card>
          );
        })}
      </div>
    </>
  );
}
