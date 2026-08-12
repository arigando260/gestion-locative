"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { respondLeaseTerminationRequestAction } from "@/actions/lease-terminations";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/forms/form-message";

// Deux boutons de soumission distincts sur un même formulaire, comme
// components/inspections/tenant-validation-form.tsx : chacun porte sa propre
// valeur `status` via l'attribut `value` du bouton.
//
// Rendu UNIQUEMENT côté appelant pour la partie qui n'a PAS initié la
// demande (requirement 1) — jamais à son auteur, même si la base bloquerait
// de toute façon la tentative (trigger validate_lease_termination_request_transition,
// Module 8) : l'interface ne doit même pas proposer le bouton. Voir les
// pages staff/locataire, qui calculent `canRespond` avant de rendre ce
// composant.
export function RespondForm({ requestId }: { requestId: string }) {
  const t = useTranslations("leaseTerminations");
  const [state, formAction] = useActionState(respondLeaseTerminationRequestAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="id" value={requestId} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="response_note">{t("responseNote")}</Label>
        <Input id="response_note" name="response_note" />
      </div>
      <FormMessage state={state} />
      <div className="flex gap-2">
        <Button type="submit" name="status" value="validee">
          {t("accept")}
        </Button>
        <Button type="submit" name="status" value="refusee" variant="outline">
          {t("refuse")}
        </Button>
      </div>
    </form>
  );
}
