"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateTenantMaintenanceTicketAction } from "@/actions/maintenance";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { MaintenanceTicket } from "@/data/maintenance";

// Actif UNIQUEMENT si status = 'signale' (RLS + restrict_tenant_maintenance_
// ticket_update_fields, Module 7) : au-delà, lecture seule avec message
// explicite plutôt qu'un formulaire qui échouerait silencieusement à la
// soumission — même principe que ticket-cost-fields.tsx côté staff.
export function TenantTicketEditForm({ ticket }: { ticket: MaintenanceTicket }) {
  const t = useTranslations("maintenance");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateTenantMaintenanceTicketAction, null);
  const editable = ticket.status === "signale";

  if (!editable) {
    return (
      <div className="flex flex-col gap-2 rounded-lg bg-muted/50 p-3 text-sm">
        <p className="text-muted-foreground">{t("editLockedMessage")}</p>
        <p className="font-medium">{ticket.title}</p>
        {ticket.description && <p>{ticket.description}</p>}
      </div>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="id" value={ticket.id} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="title">{t("ticketTitle")}</Label>
        {/* Remonte (non contrôlé) quand ticket.updated_at change après un
            revalidatePath réussi — même correctif que
            ticket-cost-fields.tsx côté staff : Base UI avertit sinon qu'un
            FieldControl non contrôlé ne peut pas accepter un nouveau
            defaultValue une fois initialisé. */}
        <Input
          key={`title-${ticket.updated_at}`}
          id="title"
          name="title"
          defaultValue={ticket.title}
          required
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="description">{t("description")}</Label>
        <Input
          key={`description-${ticket.updated_at}`}
          id="description"
          name="description"
          defaultValue={ticket.description ?? ""}
        />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{tc("save")}</SubmitButton>
    </form>
  );
}
