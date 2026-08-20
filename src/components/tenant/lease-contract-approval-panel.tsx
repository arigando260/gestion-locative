"use client";

import { useActionState, useRef, useState, type FormEvent } from "react";
import { useTranslations, useLocale } from "next-intl";
import { getOrGenerateLeaseContractUrlAction, approveLeaseContractAction } from "@/actions/lease-contracts";
import { DocumentDownloadButton } from "@/components/billing/document-download-button";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { formatDateTime } from "@/lib/format-date";

// Remplace le duo DocumentDownloadButton + ApproveLeaseContractForm
// (rendus côté à côté, sans lien entre eux) par un seul composant qui
// partage l'état "consulté" entre les deux boutons — nécessaire pour
// bloquer côté client une approbation avant consultation réelle (Module
// 10f). La vraie garantie reste le trigger private.activate_lease_on_
// contract_approval (refuse si first_viewed_at est NULL) : ce blocage
// client n'évite qu'un aller-retour serveur inutile dans le cas normal.
export function LeaseContractApprovalPanel({
  leaseId,
  depositsComplete,
  initiallyViewed,
  firstViewedAt,
}: {
  leaseId: string;
  depositsComplete: boolean;
  // Depuis leases_activation_readiness.contract_first_viewed_at : évite de
  // rebloquer à tort un locataire déjà passé par "Consulter" lors d'une
  // session précédente (l'état local viewed serait sinon toujours
  // remis à false au rendu initial).
  initiallyViewed: boolean;
  // Même colonne, valeur brute cette fois (affichage), en plus du booléen
  // ci-dessus qui reste la seule source pour la logique de blocage.
  firstViewedAt: string | null;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(approveLeaseContractAction, null);
  const [viewed, setViewed] = useState(initiallyViewed);
  const [acknowledged, setAcknowledged] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);
  const messageRef = useRef<HTMLDivElement>(null);

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    if (!viewed || !acknowledged) {
      event.preventDefault();
      setValidationError(t("mustViewContractBeforeApprove"));
      messageRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  }

  return (
    <div className="flex flex-col gap-3">
      {firstViewedAt && (
        <p className="text-sm text-muted-foreground">
          {t("contractViewedOn", { date: formatDateTime(firstViewedAt, locale) })}
        </p>
      )}
      <DocumentDownloadButton
        action={getOrGenerateLeaseContractUrlAction.bind(null, leaseId)}
        label={t("viewContract")}
        pendingLabel={t("generatingContract")}
        onSuccess={() => {
          setViewed(true);
          setValidationError(null);
        }}
      />
      {depositsComplete ? (
        // noValidate : la validation native du navigateur pour la case à
        // cocher (required) afficherait sa propre bulle AVANT que ce
        // handler ne s'exécute, empêchant le message unique demandé pour
        // les deux cas (jamais consulté / case non cochée) de jamais
        // s'afficher pour ce second cas. required reste posé sur l'input
        // pour la sémantique/l'accessibilité (lecteurs d'écran), la
        // validation réelle est entièrement portée par handleSubmit.
        <form action={formAction} onSubmit={handleSubmit} noValidate className="flex flex-col gap-3">
          <input type="hidden" name="lease_id" value={leaseId} />
          <div className="flex items-start gap-2">
            <input
              id="acknowledge_contract"
              type="checkbox"
              required
              checked={acknowledged}
              onChange={(event) => {
                setAcknowledged(event.target.checked);
                setValidationError(null);
              }}
              className="mt-1"
            />
            <Label htmlFor="acknowledge_contract" className="font-normal">
              {t("acknowledgeContractLabel")}
            </Label>
          </div>
          <div ref={messageRef}>
            <FormMessage state={validationError ? { success: false, message: validationError } : state} />
          </div>
          <SubmitButton pendingText={tc("loading")}>{t("approveContract")}</SubmitButton>
        </form>
      ) : (
        <p className="text-sm text-muted-foreground">{t("depositsIncompleteTenantHint")}</p>
      )}
    </div>
  );
}
