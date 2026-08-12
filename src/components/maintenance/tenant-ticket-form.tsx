"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createTenantMaintenanceTicketAction } from "@/actions/maintenance";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { LeaseWithContext } from "@/data/leases";

// Un seul champ pour "quel logement" : la sélection porte directement le
// lease_id (jamais property_id/organization_id séparément) — l'action
// serveur redérive le bien/l'organisation à partir du bail choisi, voir
// actions/maintenance.ts. Uniquement des baux actifs : le trigger
// validate_maintenance_ticket_tenant_lease (Module 7) exige un bail actif
// du locataire sur ce bien précis, un bail terminé/résilié serait de toute
// façon rejeté.
export function TenantTicketForm({ activeLeases }: { activeLeases: LeaseWithContext[] }) {
  const t = useTranslations("maintenance");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createTenantMaintenanceTicketAction, null);

  if (activeLeases.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("noActiveLease")}</p>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="locale" value={locale} />
      <SelectField
        name="lease_id"
        label={t("property")}
        options={activeLeases.map((lease) => ({
          value: lease.id,
          label: lease.organizations?.name
            ? `${lease.properties?.name ?? "—"} — ${lease.organizations.name}`
            : (lease.properties?.name ?? "—"),
        }))}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="title">{t("ticketTitle")}</Label>
        <Input id="title" name="title" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="description">{t("description")}</Label>
        <Input id="description" name="description" />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("reportSubmit")}</SubmitButton>
    </form>
  );
}
