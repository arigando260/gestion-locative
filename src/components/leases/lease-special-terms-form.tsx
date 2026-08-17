"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateLeaseSpecialTermsAction } from "@/actions/leases";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// Override par bail des clauses particulières par défaut de l'organisation
// (Module 10d) — vide = retour à l'héritage, résolu uniquement côté rendu
// PDF (lib/pdf/lease-contract-document.tsx), jamais ici. Toujours
// modifiable quel que soit le statut du bail (même principe que
// TenantCaptureToggle) : rien n'impose de figer ce champ après activation.
export function LeaseSpecialTermsForm({
  leaseId,
  specialTerms,
}: {
  leaseId: string;
  specialTerms: string | null;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateLeaseSpecialTermsAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-2">
      <input type="hidden" name="lease_id" value={leaseId} />
      <Label htmlFor="special_terms">{t("specialTermsLabel")}</Label>
      <Textarea
        id="special_terms"
        name="special_terms"
        rows={4}
        defaultValue={specialTerms ?? ""}
      />
      <p className="text-sm text-muted-foreground">{t("specialTermsHint")}</p>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} variant="outline" className="w-fit">
        {tc("save")}
      </SubmitButton>
    </form>
  );
}
