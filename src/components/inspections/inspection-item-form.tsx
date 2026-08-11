"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { addInspectionItemAction } from "@/actions/inspections";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";

export function InspectionItemForm({
  inspectionId,
  leaseId,
}: {
  inspectionId: string;
  leaseId: string;
}) {
  const t = useTranslations("inspections");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(addInspectionItemAction, null);

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="inspection_id" value={inspectionId} />
      <input type="hidden" name="lease_id" value={leaseId} />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="zone">{t("zone")}</Label>
        <Input id="zone" name="zone" required />
      </div>
      <SelectField
        name="condition"
        label={t("condition")}
        options={[
          { value: "bon", label: t("conditionBon") },
          { value: "usage_normal", label: t("conditionUsageNormal") },
          { value: "degrade", label: t("conditionDegrade") },
          { value: "hors_service", label: t("conditionHorsService") },
        ]}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="description">{t("description")}</Label>
        <Input id="description" name="description" />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="estimated_repair_cost">{t("estimatedRepairCost")}</Label>
        <Input
          id="estimated_repair_cost"
          name="estimated_repair_cost"
          type="number"
          min="0"
          step="0.01"
        />
      </div>
      <FormMessage state={state} />
      <SubmitButton pendingText={tc("loading")}>{t("addItem")}</SubmitButton>
    </form>
  );
}
