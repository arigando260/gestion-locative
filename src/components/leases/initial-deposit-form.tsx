"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { recordInitialDepositAction } from "@/actions/deposits";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { Lease } from "@/data/leases";
import type { DepositBalance, DepositType } from "@/data/deposits";

const TYPE_KEY: Record<DepositType, string> = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
};

// Montant cible par type de caution (security_deposit_amount /
// utility_deposit_amount, saisis à la création du bail, jamais lus ailleurs
// jusqu'ici) — sert uniquement à suggérer un "reste à verser".
const TARGET_FIELD: Record<DepositType, "security_deposit_amount" | "utility_deposit_amount"> = {
  avance_garantie: "security_deposit_amount",
  caution_utilities: "utility_deposit_amount",
};

const DEPOSIT_TYPES: DepositType[] = ["avance_garantie", "caution_utilities"];

// Deux cartes fixes, une par type — jamais masquées (contrairement à
// RefundForm, qui ne propose que les soldes réellement disponibles) :
// verser un dépôt initial reste pertinent même à cible nulle ou déjà
// atteinte, le staff peut toujours enregistrer un montant.
export function InitialDepositForm({
  leaseId,
  lease,
  balances,
}: {
  leaseId: string;
  lease: Pick<Lease, "security_deposit_amount" | "utility_deposit_amount">;
  balances: DepositBalance[];
}) {
  return (
    <div className="flex flex-col gap-3">
      {DEPOSIT_TYPES.map((depositType) => {
        const target = lease[TARGET_FIELD[depositType]];
        const held = balances.find((b) => b.deposit_type === depositType)?.amount_held ?? 0;
        // target null = aucune cible connue pour ce type -> champ vide, pas
        // de suggestion ; sinon reste à verser, jamais négatif (0 si déjà
        // entièrement versé, toujours modifiable ensuite).
        const suggestedAmount = target === null ? "" : Math.max(target - held, 0);

        return (
          <InitialDepositCard
            key={depositType}
            leaseId={leaseId}
            depositType={depositType}
            suggestedAmount={suggestedAmount}
          />
        );
      })}
    </div>
  );
}

// Formulaire indépendant par carte, même principe que RefundBalanceRow
// (refund-form.tsx) : chaque carte a son propre useActionState.
// Contrairement au remboursement, le montant reste MODIFIABLE (pas de champ
// caché) — suggestedAmount n'est qu'une valeur de départ.
function InitialDepositCard({
  leaseId,
  depositType,
  suggestedAmount,
}: {
  leaseId: string;
  depositType: DepositType;
  suggestedAmount: number | "";
}) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(recordInitialDepositAction, null);

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">{t(TYPE_KEY[depositType])}</CardTitle>
      </CardHeader>
      <CardContent>
        <form action={formAction} className="flex flex-col gap-3">
          <input type="hidden" name="lease_id" value={leaseId} />
          <input type="hidden" name="deposit_type" value={depositType} />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor={`initial_deposit_amount_${depositType}`}>{t("amount")}</Label>
            <Input
              id={`initial_deposit_amount_${depositType}`}
              name="amount"
              type="number"
              min="0"
              step="0.01"
              defaultValue={suggestedAmount}
              required
            />
          </div>
          <FormMessage state={state} />
          <SubmitButton pendingText={tc("loading")}>
            {t("recordInitialDeposit")}
          </SubmitButton>
        </form>
      </CardContent>
    </Card>
  );
}
