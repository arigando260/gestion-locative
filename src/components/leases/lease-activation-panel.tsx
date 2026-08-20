import { getTranslations, getLocale } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { getOrGenerateLeaseContractUrlAction } from "@/actions/lease-contracts";
import { formatDateTime } from "@/lib/format-date";
import type { LeaseActivationReadiness } from "@/data/lease-contracts";
import type { DepositBalance } from "@/data/deposits";
import type { Lease } from "@/data/leases";

const TARGET_FIELD = {
  avance_garantie: "security_deposit_amount",
  caution_utilities: "utility_deposit_amount",
} as const;
const TYPE_KEY = {
  avance_garantie: "typeAvanceGarantie",
  caution_utilities: "typeCautionUtilities",
} as const;

// Affichée uniquement pour un bail 'brouillon' (voir app/[locale]/(dashboard)/
// leases/[leaseId]/page.tsx) — résumé de progression des dépôts (source
// d'éligibilité : leases_activation_readiness, jamais recalculée ici) +
// génération du contrat. Ne remplace pas la page /leases/{id}/deposits
// (InitialDepositForm y reste le seul endroit où enregistrer un dépôt) :
// ce panneau ne fait que lire, jamais écrire de dépôt.
export async function LeaseActivationPanel({
  leaseId,
  lease,
  readiness,
  balances,
  canGenerate,
}: {
  leaseId: string;
  lease: Pick<Lease, "security_deposit_amount" | "utility_deposit_amount">;
  readiness: LeaseActivationReadiness | null;
  balances: DepositBalance[];
  canGenerate: boolean;
}) {
  const t = await getTranslations("leases");
  const td = await getTranslations("deposits");
  const locale = await getLocale();

  const depositsComplete = readiness?.deposits_complete ?? false;
  const contractGenerated = readiness?.contract_id != null;

  const depositTypes: Array<keyof typeof TARGET_FIELD> = lease.utility_deposit_amount
    ? ["avance_garantie", "caution_utilities"]
    : ["avance_garantie"];

  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle>{t("activationTitle")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <div className="flex flex-col gap-1 text-sm text-muted-foreground">
          {depositTypes.map((type) => {
            const target = lease[TARGET_FIELD[type]] ?? 0;
            const held = balances.find((b) => b.deposit_type === type)?.amount_held ?? 0;
            return (
              <p key={type}>
                {td(TYPE_KEY[type])}: {held} / {target}
              </p>
            );
          })}
        </div>

        <p className={`text-sm ${depositsComplete ? "font-medium" : "text-muted-foreground"}`}>
          {depositsComplete ? t("depositsComplete") : t("depositsIncomplete")}
        </p>

        <Button
          variant="outline"
          className="w-fit"
          render={<Link href={`/leases/${leaseId}/deposits`} />}
          nativeButton={false}
        >
          {td("recordDeposit")}
        </Button>

        {!contractGenerated && canGenerate && (
          <DocumentDownloadButton
            action={getOrGenerateLeaseContractUrlAction.bind(null, leaseId)}
            label={t("generateContract")}
            pendingLabel={t("generatingContract")}
          />
        )}

        {contractGenerated && (
          <>
            <DocumentDownloadButton
              action={getOrGenerateLeaseContractUrlAction.bind(null, leaseId)}
              label={t("viewContract")}
              pendingLabel={t("generatingContract")}
            />
            <p className="text-sm text-muted-foreground">
              {t("contractGeneratedOn", { date: formatDateTime(readiness?.contract_generated_at, locale) })}
            </p>
            <p className="text-sm text-muted-foreground">
              {readiness?.contract_first_viewed_at
                ? t("contractViewedOn", { date: formatDateTime(readiness.contract_first_viewed_at, locale) })
                : t("contractNotYetViewed")}
            </p>
            <p className="text-sm text-muted-foreground">{t("awaitingTenantApproval")}</p>
          </>
        )}
      </CardContent>
    </Card>
  );
}
