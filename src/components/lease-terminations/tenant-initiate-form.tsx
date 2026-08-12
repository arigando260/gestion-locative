"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { Link } from "@/i18n/navigation";
import { createTenantLeaseTerminationAction } from "@/actions/lease-terminations";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type {
  LeaseTerminationLeaseOption,
  BlockedLeaseOption,
} from "@/components/lease-terminations/staff-initiate-form";

// Même garde-fou côté locataire que StaffInitiateForm (requirement 2) : les
// baux ayant déjà une demande en_attente sont exclus du sélecteur, signalés
// à part avec un lien vers la demande existante.
export function TenantInitiateForm({
  eligibleLeases,
  blockedLeases,
}: {
  eligibleLeases: LeaseTerminationLeaseOption[];
  blockedLeases: BlockedLeaseOption[];
}) {
  const t = useTranslations("leaseTerminations");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createTenantLeaseTerminationAction, null);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <div className="flex flex-col gap-4">
      {blockedLeases.length > 0 && (
        <div className="flex flex-col gap-2 rounded-lg bg-muted/50 p-3 text-sm">
          <p>{t("alreadyPendingTitle")}</p>
          {blockedLeases.map((lease) => (
            <div key={lease.id} className="flex items-center justify-between gap-2">
              <span>{lease.label}</span>
              <Link
                href={`/tenant/lease-terminations/${lease.requestId}`}
                className="hover:underline"
              >
                {t("viewPendingRequest")}
              </Link>
            </div>
          ))}
        </div>
      )}

      {eligibleLeases.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("noActiveLease")}</p>
      ) : (
        <form action={formAction} className="flex flex-col gap-4">
          <input type="hidden" name="locale" value={locale} />
          <SelectField
            name="lease_id"
            label={t("lease")}
            options={eligibleLeases.map((lease) => ({ value: lease.id, label: lease.label }))}
          />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="requested_end_date">{t("requestedEndDate")}</Label>
            <Input
              id="requested_end_date"
              name="requested_end_date"
              type="date"
              min={today}
              required
            />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="reason">{t("reason")}</Label>
            <Input id="reason" name="reason" required />
          </div>
          <FormMessage state={state} />
          <SubmitButton pendingText={tc("loading")}>{t("create")}</SubmitButton>
        </form>
      )}
    </div>
  );
}
