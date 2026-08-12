"use client";

import { useActionState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { Link } from "@/i18n/navigation";
import { createStaffLeaseTerminationAction } from "@/actions/lease-terminations";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export type LeaseTerminationLeaseOption = { id: string; label: string };
export type BlockedLeaseOption = LeaseTerminationLeaseOption & { requestId: string };

// Requirement 2 : les baux ayant déjà une demande en_attente (index partiel
// unique en base, Module 8) ne sont volontairement PAS proposés dans le
// sélecteur — signalés à part avec un lien direct, plutôt que de laisser
// l'utilisateur choisir un bail dont la tentative échouerait silencieusement
// (23505) une fois soumise.
export function StaffInitiateForm({
  eligibleLeases,
  blockedLeases,
}: {
  eligibleLeases: LeaseTerminationLeaseOption[];
  blockedLeases: BlockedLeaseOption[];
}) {
  const t = useTranslations("leaseTerminations");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createStaffLeaseTerminationAction, null);
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
                href={`/lease-terminations/${lease.requestId}`}
                className="hover:underline"
              >
                {t("viewPendingRequest")}
              </Link>
            </div>
          ))}
        </div>
      )}

      {eligibleLeases.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("noEligibleLease")}</p>
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
