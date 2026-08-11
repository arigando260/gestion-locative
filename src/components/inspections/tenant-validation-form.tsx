"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { submitTenantValidationAction } from "@/actions/inspections";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/forms/form-message";

export function TenantValidationForm({
  inspectionId,
  leaseId,
}: {
  inspectionId: string;
  leaseId: string;
}) {
  const t = useTranslations("inspections");
  const [state, formAction] = useActionState(submitTenantValidationAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="id" value={inspectionId} />
      <input type="hidden" name="lease_id" value={leaseId} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="comments">{t("yourComments")}</Label>
        <Input id="comments" name="comments" />
      </div>
      <FormMessage state={state} />
      <div className="flex gap-2">
        <Button type="submit" name="status" value="valide">
          {t("validate")}
        </Button>
        <Button type="submit" name="status" value="conteste" variant="outline">
          {t("contest")}
        </Button>
      </div>
    </form>
  );
}
