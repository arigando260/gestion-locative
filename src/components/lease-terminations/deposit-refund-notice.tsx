import { getTranslations } from "next-intl/server";

// Requirement 6 : rappel explicite, identique côté staff et locataire, que
// la résiliation n'affecte pas automatiquement le calcul du remboursement de
// caution — ce calcul dépend de l'état des lieux de sortie et des
// imputations enregistrées sur deposit_ledger (Modules 5/6/7), des étapes
// séparées et postérieures à la résiliation elle-même. Même style visuel que
// les bannières d'information existantes (ex: costsLockedMessage).
export async function DepositRefundNotice() {
  const t = await getTranslations("leaseTerminations");

  return (
    <div className="rounded-lg bg-muted/50 p-3 text-sm text-muted-foreground">
      <p className="font-medium text-foreground">{t("depositDisclaimerTitle")}</p>
      <p>{t("depositDisclaimer")}</p>
    </div>
  );
}
