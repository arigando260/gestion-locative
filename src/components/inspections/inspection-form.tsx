"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { createInspectionAction } from "@/actions/inspections";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { useLocale } from "next-intl";

export function InspectionForm({ leaseId }: { leaseId: string }) {
  const t = useTranslations("inspections");
  const tc = useTranslations("common");
  const locale = useLocale();
  const [state, formAction] = useActionState(createInspectionAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="lease_id" value={leaseId} />
      <input type="hidden" name="locale" value={locale} />
      <SelectField
        name="inspection_type"
        label={t("type")}
        options={[
          { value: "entree", label: t("typeEntree") },
          { value: "sortie", label: t("typeSortie") },
        ]}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="inspection_date">{t("inspectionDate")}</Label>
        <Input id="inspection_date" name="inspection_date" type="date" required />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("create")}</SubmitButton>
    </form>
  );
}
