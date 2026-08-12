"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { recordRefundAction } from "@/actions/deposits";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { DepositBalance } from "@/data/deposits";

const TYPE_KEY: Record<string, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};

// Une carte par type de caution ayant un solde disponible
// (deposit_ledger_balances, calculé à la volée, Module 5 — déjà chargé par
// la page parente, transmis ici plutôt que refetché). Un solde épuisé ou
// négatif n'est jamais proposé : pas de risque de rembourser au-delà du
// solde réel depuis cet écran.
export function RefundForm({
  leaseId,
  balances,
}: {
  leaseId: string;
  balances: DepositBalance[];
}) {
  const t = useTranslations("deposits");
  const eligible = balances.filter((b) => (b.balance ?? 0) > 0);

  if (eligible.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("noBalanceAvailable")}</p>;
  }

  return (
    <div className="flex flex-col gap-3">
      {eligible.map((balance) => (
        <RefundBalanceRow key={balance.deposit_type} leaseId={leaseId} balance={balance} />
      ))}
    </div>
  );
}

// Formulaire indépendant par ligne : chaque solde a son propre
// useActionState (même principe que StatusButton dans
// ticket-status-control.tsx) — amount est fixé au solde exact (champ
// caché, jamais saisi), le staff ne renseigne que le motif.
function RefundBalanceRow({
  leaseId,
  balance,
}: {
  leaseId: string;
  balance: DepositBalance;
}) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(recordRefundAction, null);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">
          {t(TYPE_KEY[balance.deposit_type ?? ""] ?? "typeAvanceGarantie")}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="flex flex-col gap-3">
          <input type="hidden" name="lease_id" value={leaseId} />
          <input type="hidden" name="deposit_type" value={balance.deposit_type ?? ""} />
          <input type="hidden" name="amount" value={balance.balance ?? 0} />
          <p className="text-sm text-muted-foreground">
            {t("balance")}: {balance.balance}
          </p>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`refund_reason_${balance.deposit_type}`}>{t("reason")}</Label>
            <Input id={`refund_reason_${balance.deposit_type}`} name="reason" />
          </div>
          <FormMessage state={state} />
          <SubmitButton pendingText={tc("loading")}>{t("recordRefund")}</SubmitButton>
        </form>
      </CardContent>
    </Card>
  );
}
