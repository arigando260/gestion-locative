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
import type { ScheduleWithEffectiveStatus } from "@/data/schedules";

const STATUS_KEY: Record<string, string> = {
  en_attente: "statusEnAttente",
  payee: "statusPayee",
  partiellement_payee: "statusPartiellementPayee",
  en_retard: "statusEnRetard",
  annulee: "statusAnnulee",
};

const STATUS_VARIANT: Record<string, "secondary" | "destructive" | "default"> = {
  payee: "default",
  en_retard: "destructive",
};

export async function ScheduleTable({
  schedules,
}: {
  schedules: ScheduleWithEffectiveStatus[];
}) {
  const t = await getTranslations("schedules");

  if (schedules.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (schedule: ScheduleWithEffectiveStatus) => {
    const statusKey = STATUS_KEY[schedule.effective_status ?? ""] ?? "statusEnAttente";
    return {
      period: `${schedule.period_start_date} → ${schedule.period_end_date}`,
      due: schedule.due_date,
      amount: schedule.amount_due,
      statusLabel: t(statusKey),
      variant: STATUS_VARIANT[schedule.effective_status ?? ""] ?? "secondary",
      partial: schedule.is_partial_period,
    };
  };

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("period")}</TableHead>
              <TableHead>{t("dueDate")}</TableHead>
              <TableHead>{t("amountDue")}</TableHead>
              <TableHead>{t("status")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {schedules.map((schedule) => {
              const r = row(schedule);
              return (
                <TableRow key={schedule.id}>
                  <TableCell>
                    {r.period}
                    {r.partial && (
                      <Badge variant="outline" className="ml-2">
                        {t("partialBadge")}
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell>{r.due}</TableCell>
                  <TableCell>{r.amount}</TableCell>
                  <TableCell>
                    <Badge variant={r.variant}>{r.statusLabel}</Badge>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {schedules.map((schedule) => {
          const r = row(schedule);
          return (
            <Card key={schedule.id}>
              <CardContent className="flex flex-col gap-1">
                <div className="flex items-center justify-between gap-2">
                  <span className="font-medium">{r.period}</span>
                  <Badge variant={r.variant}>{r.statusLabel}</Badge>
                </div>
                <span className="text-sm text-muted-foreground">
                  {t("dueDate")}: {r.due}
                </span>
                <span className="text-sm text-muted-foreground">
                  {t("amountDue")}: {r.amount}
                </span>
                {r.partial && (
                  <Badge variant="outline" className="w-fit">
                    {t("partialBadge")}
                  </Badge>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>
    </>
  );
}
