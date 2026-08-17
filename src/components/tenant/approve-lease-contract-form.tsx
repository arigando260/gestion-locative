"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { approveLeaseContractAction } from "@/actions/lease-contracts";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// Un seul bouton, pas de refus symétrique (décision Module 10 : en cas de
// désaccord, le staff gère hors système — édition ou suppression du bail
// brouillon). La vraie vérification (dépôts complets, bail encore brouillon)
// reste le trigger security definer côté base ; l'absence conditionnelle de
// ce formulaire (voir lease-contract-approval.tsx) n'est qu'une aide à
// l'ergonomie.
export function ApproveLeaseContractForm({ leaseId }: { leaseId: string }) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(approveLeaseContractAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-2">
      <input type="hidden" name="lease_id" value={leaseId} />
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("approveContract")}</SubmitButton>
    </form>
  );
}
