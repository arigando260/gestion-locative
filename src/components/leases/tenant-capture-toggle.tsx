"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateLeaseTenantCaptureAction } from "@/actions/leases";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

// null = hérite du réglage organisation (leases.tenant_capture_enabled,
// Module 6) — 3 états distincts, pas un simple booléen : "hérite" n'est PAS
// équivalent à "non autorisé", même si le résultat effectif peut coïncider
// selon le réglage organisation courant.
export function TenantCaptureToggle({
  leaseId,
  leaseValue,
  organizationDefault,
}: {
  leaseId: string;
  leaseValue: boolean | null;
  organizationDefault: boolean;
}) {
  const t = useTranslations("leases");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateLeaseTenantCaptureAction, null);

  const isInherited = leaseValue === null;
  const effective = leaseValue ?? organizationDefault;

  return (
    <form action={formAction} className="flex flex-col gap-2">
      <input type="hidden" name="lease_id" value={leaseId} />
      <SelectField
        name="tenant_capture_enabled"
        label={t("tenantCaptureLabel")}
        defaultValue={leaseValue === null ? "inherit" : String(leaseValue)}
        options={[
          { value: "inherit", label: t("tenantCaptureInherit") },
          { value: "true", label: t("tenantCaptureAllowed") },
          { value: "false", label: t("tenantCaptureNotAllowed") },
        ]}
      />
      <p className="text-sm text-muted-foreground">
        {t("tenantCaptureEffective")}:{" "}
        {t(effective ? "tenantCaptureAllowed" : "tenantCaptureNotAllowed")}
        {isInherited && ` (${t("tenantCaptureInheritedHint")})`}
      </p>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")} variant="outline" className="w-fit">
        {tc("save")}
      </SubmitButton>
    </form>
  );
}
