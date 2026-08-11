import { getTranslations } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { DepositBalance } from "@/data/deposits";

const TYPE_KEY: Record<string, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};

export async function DepositBalanceCards({
  balances,
}: {
  balances: DepositBalance[];
}) {
  const t = await getTranslations("deposits");

  if (balances.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {balances.map((balance) => (
        <Card key={balance.deposit_type}>
          <CardHeader>
            <CardTitle className="text-base">
              {t(TYPE_KEY[balance.deposit_type ?? ""] ?? "typeAvanceGarantie")}
            </CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-1 text-sm">
            <p className="text-muted-foreground">
              {t("amountHeld")}: {balance.amount_held}
            </p>
            <p className="text-muted-foreground">
              {t("totalImputed")}: {balance.total_imputed}
            </p>
            <p className="text-muted-foreground">
              {t("totalRefunded")}: {balance.total_refunded}
            </p>
            <p className="font-medium">
              {t("balance")}: {balance.balance}
            </p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
