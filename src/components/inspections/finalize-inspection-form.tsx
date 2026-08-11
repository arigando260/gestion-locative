"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { finalizeInspectionAction } from "@/actions/inspections";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export function FinalizeInspectionForm({
  inspectionId,
  leaseId,
}: {
  inspectionId: string;
  leaseId: string;
}) {
  const t = useTranslations("inspections");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(finalizeInspectionAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="id" value={inspectionId} />
      <input type="hidden" name="lease_id" value={leaseId} />
      <SubmitButton pendingText={tc("loading")}>{t("finalize")}</SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
