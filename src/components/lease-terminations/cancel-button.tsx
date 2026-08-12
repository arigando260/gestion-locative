"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { cancelLeaseTerminationRequestAction } from "@/actions/lease-terminations";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// Rendu UNIQUEMENT côté auteur de la demande, tant qu'elle est en_attente
// (requirement 4/5) — voir les pages staff/locataire, qui calculent
// `canCancel` via data/lease-terminations.ts isLeaseTerminationInitiator()
// avant de rendre ce composant. La base (trigger validate_lease_termination_request_transition,
// Module 8) revérifie de toute façon que l'appelant est bien l'auteur exact.
export function CancelButton({ requestId }: { requestId: string }) {
  const t = useTranslations("leaseTerminations");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(cancelLeaseTerminationRequestAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="id" value={requestId} />
      <SubmitButton pendingText={tc("loading")} variant="outline">
        {t("cancel")}
      </SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
