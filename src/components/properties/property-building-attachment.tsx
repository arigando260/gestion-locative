"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { attachPropertyToBuildingAction } from "@/actions/properties";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import type { BuildingWithUnitsCount } from "@/data/buildings";

// Visible seulement pour un bien SANS building_id (le rattachement se fait
// via cette action ciblée, pas un formulaire d'édition générique — Module
// 13, point 1 du périmètre écran) et gating côté page via
// can(permissions, 'properties', 'update') (même mécanisme que le reste de
// l'écran, pas de nouvelle infrastructure). Pas de bouton de détachement :
// hors périmètre de ce chantier.
export function PropertyBuildingAttachment({
  propertyId,
  availableBuildings,
}: {
  propertyId: string;
  availableBuildings: BuildingWithUnitsCount[];
}) {
  const t = useTranslations("properties");
  const [state, formAction] = useActionState(attachPropertyToBuildingAction, null);

  if (availableBuildings.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("attachBuildingNoneAvailable")}</p>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-3">
      <input type="hidden" name="property_id" value={propertyId} />
      <SelectField
        name="building_id"
        label={t("attachBuildingSelectLabel")}
        defaultValue={availableBuildings[0]?.id}
        options={availableBuildings.map((b) => ({ value: b.id, label: b.name }))}
      />
      {state && !state.success ? (
        <p className="text-sm text-destructive" role="alert">
          {state.message}
        </p>
      ) : null}
      <SubmitButton pendingText={t("attachBuildingSubmitting")} className="w-fit">
        {t("attachBuildingSubmit")}
      </SubmitButton>
    </form>
  );
}
