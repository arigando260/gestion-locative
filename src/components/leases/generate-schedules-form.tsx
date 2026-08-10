"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { generateSchedulesAction } from "@/actions/schedules";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export function GenerateSchedulesForm({ leaseId }: { leaseId: string }) {
  const t = useTranslations("schedules");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(generateSchedulesAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <input type="hidden" name="lease_id" value={leaseId} />
      <SubmitButton pendingText={tc("loading")} variant="outline">
        {t("generate")}
      </SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
