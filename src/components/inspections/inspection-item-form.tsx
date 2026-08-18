"use client";

import { useActionState, useState } from "react";
import { useTranslations } from "next-intl";
import { addInspectionItemAction, updateInspectionItemAction } from "@/actions/inspections";
import type { InspectionItem } from "@/data/inspections";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { Button } from "@/components/ui/button";

// Conditions pour lesquelles la description devient obligatoire — même
// liste que le trigger private.validate_inspection_item_description_
// required (Module 6h). Ce contrôle client n'est qu'un guide, la vraie
// autorité reste le trigger.
const DESCRIPTION_REQUIRED_CONDITIONS = ["degrade", "hors_service"];

export function InspectionItemForm({
  inspectionId,
  leaseId,
  item,
  onCancel,
}: {
  inspectionId: string;
  leaseId: string;
  // Présent = mode édition (formulaire pré-rempli, updateInspectionItemAction) ;
  // absent = mode ajout (addInspectionItemAction). Un seul composant pour les
  // deux plutôt que de dupliquer la structure du formulaire (Module 6j).
  item?: Pick<InspectionItem, "id" | "zone" | "condition" | "description" | "estimated_repair_cost">;
  // Bouton "Annuler" affiché uniquement en mode édition. Pas de fermeture
  // automatique après un succès (testé en navigateur : ça démontait le
  // formulaire — et son FormMessage — avant que l'utilisateur ait pu voir
  // le message de confirmation, contrairement à toutes les autres actions
  // de l'appli qui restent affichées après succès) : l'utilisateur referme
  // lui-même une fois le message vu.
  onCancel?: () => void;
}) {
  const t = useTranslations("inspections");
  const tc = useTranslations("common");
  const isEdit = item != null;
  const [state, formAction] = useActionState(
    isEdit ? updateInspectionItemAction : addInspectionItemAction,
    null
  );
  const [condition, setCondition] = useState(item?.condition ?? "bon");
  const descriptionRequired = DESCRIPTION_REQUIRED_CONDITIONS.includes(condition);

  // Plusieurs instances de ce formulaire peuvent coexister sur la même page
  // (une par item en édition + le formulaire d'ajout) : les id de champs
  // doivent rester uniques dans le DOM.
  const suffix = item?.id ?? "new";

  return (
    <form action={formAction} className="flex flex-col gap-4">
      <input type="hidden" name="inspection_id" value={inspectionId} />
      <input type="hidden" name="lease_id" value={leaseId} />
      {isEdit && <input type="hidden" name="item_id" value={item.id} />}
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`zone-${suffix}`}>{t("zone")}</Label>
        <Input id={`zone-${suffix}`} name="zone" defaultValue={item?.zone} required />
      </div>
      <SelectField
        name="condition"
        id={`condition-${suffix}`}
        label={t("condition")}
        defaultValue={item?.condition}
        onValueChange={setCondition}
        options={[
          { value: "bon", label: t("conditionBon") },
          { value: "usage_normal", label: t("conditionUsageNormal") },
          { value: "degrade", label: t("conditionDegrade") },
          { value: "hors_service", label: t("conditionHorsService") },
        ]}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`description-${suffix}`}>
          {t("description")}
          {descriptionRequired && <span className="text-destructive"> *</span>}
        </Label>
        <Input
          id={`description-${suffix}`}
          name="description"
          defaultValue={item?.description ?? undefined}
          required={descriptionRequired}
        />
        {descriptionRequired && (
          <p className="text-xs text-muted-foreground">{t("descriptionRequiredHint")}</p>
        )}
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor={`estimated_repair_cost-${suffix}`}>{t("estimatedRepairCost")}</Label>
        <Input
          id={`estimated_repair_cost-${suffix}`}
          name="estimated_repair_cost"
          type="number"
          min="0"
          step="0.01"
          defaultValue={item?.estimated_repair_cost ?? undefined}
        />
      </div>
      <FormMessage state={state} />
      <div className="flex gap-2">
        <SubmitButton pendingText={tc("loading")}>{isEdit ? tc("save") : t("addItem")}</SubmitButton>
        {isEdit && onCancel && (
          <Button type="button" variant="outline" onClick={onCancel}>
            {tc("cancel")}
          </Button>
        )}
      </div>
    </form>
  );
}
