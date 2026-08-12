"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { updateMaintenanceTicketCostAction } from "@/actions/maintenance";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { MaintenanceTicket, MaintenanceTicketImputation } from "@/data/maintenance";

// Le gel (trigger prevent_maintenance_ticket_cost_change_after_imputation,
// Module 7b) est vérifié ICI en amont, via l'existence réelle d'une ligne
// deposit_ledger — jamais déduit d'un échec d'écriture après coup (try/catch
// sur l'erreur serveur) : imputations est déjà chargé par la page avant tout
// rendu, l'écran reflète un fait connu, pas une supposition optimiste.
export function TicketCostFields({
  ticketId,
  ticket,
  imputations,
}: {
  ticketId: string;
  ticket: MaintenanceTicket;
  imputations: MaintenanceTicketImputation[];
}) {
  const t = useTranslations("maintenance");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateMaintenanceTicketCostAction, null);
  const locked = imputations.length > 0;

  return (
    <div className="flex flex-col gap-3">
      {locked && (
        <div className="flex flex-col gap-2 rounded-lg bg-muted/50 p-3 text-sm">
          <p>{t("costsLockedMessage")}</p>
          {imputations.map((imputation) => (
            <div key={imputation.id} className="flex items-center justify-between gap-2">
              <span>
                {imputation.reason ?? t("costSectionTitle")} — {imputation.amount}
              </span>
              {imputation.lease_id && (
                <Link
                  href={`/leases/${imputation.lease_id}/deposits`}
                  className="text-sm hover:underline"
                >
                  {t("viewImputation")}
                </Link>
              )}
            </div>
          ))}
        </div>
      )}

      <form action={formAction} className="flex flex-col gap-4">
        <input type="hidden" name="id" value={ticketId} />
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="estimated_cost">{t("estimatedCost")}</Label>
          <Input
            // Remonte le champ (non contrôlé, comme le reste du projet)
            // quand ticket.updated_at change après un revalidatePath réussi
            // — sinon Base UI avertit qu'un FieldControl non contrôlé déjà
            // initialisé ne peut pas accepter un nouveau defaultValue.
            key={`estimated-${ticket.updated_at}`}
            id="estimated_cost"
            name="estimated_cost"
            type="number"
            min="0"
            step="0.01"
            defaultValue={ticket.estimated_cost ?? ""}
            disabled={locked}
          />
        </div>
        <div className="flex flex-col gap-1.5">
          <Label htmlFor="actual_cost">{t("actualCost")}</Label>
          <Input
            key={`actual-${ticket.updated_at}`}
            id="actual_cost"
            name="actual_cost"
            type="number"
            min="0"
            step="0.01"
            defaultValue={ticket.actual_cost ?? ""}
            disabled={locked}
          />
        </div>
        <FormMessage state={state} />
        {!locked && (
          <SubmitButton pendingText={tc("loading")} variant="outline">
            {t("saveCosts")}
          </SubmitButton>
        )}
      </form>
    </div>
  );
}
