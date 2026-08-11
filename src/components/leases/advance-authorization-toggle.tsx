"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { toggleAdvanceAuthorizationAction } from "@/actions/deposits";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { Badge } from "@/components/ui/badge";

export function AdvanceAuthorizationToggle({
  leaseId,
  authorized,
}: {
  leaseId: string;
  authorized: boolean;
}) {
  const t = useTranslations("deposits");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(toggleAdvanceAuthorizationAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-2">
      <div className="flex items-center gap-2">
        <span className="text-sm text-muted-foreground">{t("advanceAuthorization")}:</span>
        <Badge variant={authorized ? "default" : "secondary"}>
          {authorized ? t("advanceAuthorized") : t("advanceNotAuthorized")}
        </Badge>
      </div>
      <input type="hidden" name="lease_id" value={leaseId} />
      <input type="hidden" name="authorized" value={(!authorized).toString()} />
      <SubmitButton pendingText={tc("loading")} variant="outline">
        {authorized ? t("revoke") : t("authorize")}
      </SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
