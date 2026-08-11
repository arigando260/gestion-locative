import { getTranslations } from "next-intl/server";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Card, CardContent } from "@/components/ui/card";
import type { Payment } from "@/data/payments";

const METHOD_KEY: Record<string, string> = {
  mobile_money: "methodMobileMoney",
  carte: "methodCarte",
  especes: "methodEspeces",
  virement: "methodVirement",
};

export async function PaymentHistoryTable({ payments }: { payments: Payment[] }) {
  const t = await getTranslations("payments");

  if (payments.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("paymentDate")}</TableHead>
              <TableHead>{t("amount")}</TableHead>
              <TableHead>{t("method")}</TableHead>
              <TableHead>{t("reference")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {payments.map((payment) => (
              <TableRow key={payment.id}>
                <TableCell>{payment.payment_date}</TableCell>
                <TableCell>{payment.amount}</TableCell>
                <TableCell>{t(METHOD_KEY[payment.method] ?? "methodEspeces")}</TableCell>
                <TableCell>{payment.external_reference ?? "—"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {payments.map((payment) => (
          <Card key={payment.id}>
            <CardContent className="flex flex-col gap-1">
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium">{payment.amount}</span>
                <span className="text-sm text-muted-foreground">{payment.payment_date}</span>
              </div>
              <span className="text-sm text-muted-foreground">
                {t(METHOD_KEY[payment.method] ?? "methodEspeces")}
              </span>
            </CardContent>
          </Card>
        ))}
      </div>
    </>
  );
}
