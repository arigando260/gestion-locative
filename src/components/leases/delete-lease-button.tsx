"use client";

import { useActionState } from "react";
import { useLocale, useTranslations } from "next-intl";
import { deleteLeaseAction } from "@/actions/leases";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// Visible uniquement pour un bail 'brouillon' (voir page) — la vraie garde
// reste le trigger côté base (deposit_ledger non vide -> refusé, message
// clair). Pas de confirmation JS supplémentaire : aucun autre geste
// destructif de ce projet n'en affiche (voir CloseLeaseButton), le message
// d'erreur explicite en cas de refus tient lieu de garde-fou visible.
export function DeleteLeaseButton({
  leaseId,
  propertyId,
}: {
  leaseId: string;
  propertyId: string;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(deleteLeaseAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="lease_id" value={leaseId} />
      <input type="hidden" name="property_id" value={propertyId} />
      <input type="hidden" name="locale" value={locale} />
      <SubmitButton pendingText={tc("loading")} variant="destructive">
        {t("deleteDraft")}
      </SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
