import { getTranslations } from "next-intl/server";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { LeaseContractApprovalPanel } from "./lease-contract-approval-panel";
import type { LeaseActivationReadiness } from "@/data/lease-contracts";

// Affichée uniquement sur la fiche d'un bail 'brouillon' (voir
// app/[locale]/tenant/leases/[leaseId]/page.tsx). Une fois approuvé, le bail
// passe à 'actif' (trigger security definer, Module 10) et cette section
// disparaît naturellement au prochain rendu — l'écran normal du bail actif
// prend le relais, rien à gérer explicitement ici pour ce cas.
export async function LeaseContractApproval({
  leaseId,
  readiness,
}: {
  leaseId: string;
  readiness: LeaseActivationReadiness | null;
}) {
  const t = await getTranslations("leases");

  // Ne fait jamais confiance à l'affichage seul : deposits_complete vient
  // de leases_activation_readiness (calculée à la volée côté base), la
  // vraie vérification au moment de l'approbation reste le trigger
  // security definer — ce booléen ne fait que décider si le bouton
  // apparaît, jamais s'il fonctionne.
  const depositsComplete = readiness?.deposits_complete ?? false;

  return (
    <Card className="max-w-md">
      <CardHeader>
        <CardTitle>{t("myContractTitle")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <LeaseContractApprovalPanel
          leaseId={leaseId}
          depositsComplete={depositsComplete}
          initiallyViewed={readiness?.contract_first_viewed_at != null}
        />
      </CardContent>
    </Card>
  );
}
