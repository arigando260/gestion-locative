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
import type { DepositLedgerEntry } from "@/data/deposits";

const TYPE_KEY: Record<string, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};
const ENTRY_KEY: Record<string, string> = {
  depot_initial: "entryDepotInitial",
  imputation: "entryImputation",
  remboursement: "entryRemboursement",
};
const CATEGORY_KEY: Record<string, string> = {
  loyer: "categoryLoyer",
  degats: "categoryDegats",
  impayes_utilities: "categoryImpayesUtilities",
};

export async function DepositLedgerTable({
  entries,
}: {
  entries: DepositLedgerEntry[];
}) {
  const t = await getTranslations("deposits");

  if (entries.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (entry: DepositLedgerEntry) => ({
    date: entry.created_at?.slice(0, 10) ?? "",
    type: t(TYPE_KEY[entry.deposit_type] ?? "typeAvanceGarantie"),
    entryType: t(ENTRY_KEY[entry.entry_type] ?? "entryDepotInitial"),
    category: entry.imputation_category
      ? t(CATEGORY_KEY[entry.imputation_category] ?? "categoryLoyer")
      : null,
    reason: entry.reason,
    amount: entry.amount,
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("date")}</TableHead>
              <TableHead>{t("depositTypeLabel")}</TableHead>
              <TableHead>{t("entryType")}</TableHead>
              <TableHead>{t("category")}</TableHead>
              <TableHead>{t("reason")}</TableHead>
              <TableHead>{t("amount")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {entries.map((entry) => {
              const r = row(entry);
              return (
                <TableRow key={entry.id}>
                  <TableCell>{r.date}</TableCell>
                  <TableCell>{r.type}</TableCell>
                  <TableCell>
                    <Badge variant="secondary">{r.entryType}</Badge>
                  </TableCell>
                  <TableCell>{r.category ?? "—"}</TableCell>
                  <TableCell>{r.reason ?? "—"}</TableCell>
                  <TableCell>{r.amount}</TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {entries.map((entry) => {
          const r = row(entry);
          return (
            <Card key={entry.id}>
              <CardContent className="flex flex-col gap-1">
                <div className="flex items-center justify-between gap-2">
                  <Badge variant="secondary">{r.entryType}</Badge>
                  <span className="font-medium">{r.amount}</span>
                </div>
                <span className="text-sm text-muted-foreground">
                  {r.date} · {r.type}
                </span>
                {r.category && (
                  <span className="text-sm text-muted-foreground">{r.category}</span>
                )}
                {r.reason && (
                  <span className="text-sm text-muted-foreground">{r.reason}</span>
                )}
              </CardContent>
            </Card>
          );
        })}
      </div>
    </>
  );
}
