"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateInspectionObservationsAction } from "@/actions/inspections";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// Seul point de saisie/édition des observations (Module 6g) — affiché
// uniquement sur la page de détail d'un brouillon (canManage && isDraft,
// voir la page appelante), jamais à la création. Redevient lecture seule
// une fois finalisé, la page appelante bascule alors sur un simple
// affichage plutôt que ce formulaire.
export function ObservationsForm({
  inspectionId,
  leaseId,
  observations,
}: {
  inspectionId: string;
  leaseId: string;
  observations: string | null;
}) {
  const t = useTranslations("inspections");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateInspectionObservationsAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-2">
      <input type="hidden" name="id" value={inspectionId} />
      <input type="hidden" name="lease_id" value={leaseId} />
      <Label htmlFor="observations">{t("observations")}</Label>
      <Textarea id="observations" name="observations" rows={4} defaultValue={observations ?? ""} />
      <p className="text-xs text-muted-foreground">{t("observationsHint")}</p>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} variant="outline" className="w-fit">
        {tc("save")}
      </SubmitButton>
    </form>
  );
}
