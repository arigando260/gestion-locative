"use client";

import { useActionState, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createMaintenanceTicketAction } from "@/actions/maintenance";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { Property } from "@/data/properties";
import type { LeaseOption } from "@/data/leases";

const NO_LEASE = "";

export function TicketForm({
  properties,
  leases,
}: {
  properties: Property[];
  leases: LeaseOption[];
}) {
  const t = useTranslations("maintenance");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createMaintenanceTicketAction, null);
  const [propertyId, setPropertyId] = useState(properties[0]?.id ?? "");

  // Bail optionnel, filtré selon le bien choisi — un ticket peut aussi
  // concerner un bien sans bail actif (ticket sans bail, cf. Module 7b).
  const leaseOptions = [
    { value: NO_LEASE, label: t("noLeaseOption") },
    ...leases
      .filter((lease) => lease.property_id === propertyId)
      .map((lease) => ({
        value: lease.id,
        label: `${t(`leaseStatus${capitalize(lease.status)}`)} — ${lease.start_date}`,
      })),
  ];

  if (properties.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("noProperties")}</p>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="locale" value={locale} />
      <SelectField
        name="property_id"
        label={t("property")}
        defaultValue={propertyId}
        onValueChange={setPropertyId}
        options={properties.map((property) => ({
          value: property.id,
          label: property.name,
        }))}
      />
      <SelectField
        key={propertyId}
        name="lease_id"
        label={t("lease")}
        options={leaseOptions}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="title">{t("ticketTitle")}</Label>
        <Input id="title" name="title" required />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="description">{t("description")}</Label>
        <Input id="description" name="description" />
      </div>
      <SelectField
        name="priority"
        label={t("priority")}
        defaultValue="normale"
        options={[
          { value: "basse", label: t("priorityBasse") },
          { value: "normale", label: t("priorityNormale") },
          { value: "haute", label: t("priorityHaute") },
          { value: "urgente", label: t("priorityUrgente") },
        ]}
      />
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("create")}</SubmitButton>
    </form>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
