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

export function InspectionForm({
  leaseId,
  defaultType,
  availableTypes,
}: {
  leaseId: string;
  // Présélection depuis un lien direct (ex: bandeau de clôture, Module 10
  // Volet C — "?type=sortie") — une valeur absente/invalide laisse le
  // champ sur son comportement normal (voir SelectField, premier
  // élément par défaut). Si absent des types disponibles, SelectField se
  // recale de lui-même sur le premier type disponible (useEffect existant).
  defaultType?: "entree" | "sortie";
  // Voir data/inspections.ts getAvailableInspectionTypes — n'inclut que
  // les types que la base accepterait réellement à la soumission.
  availableTypes: ("entree" | "sortie")[];
}) {
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
        defaultValue={defaultType}
        options={[
          { value: "entree", label: t("typeEntree") },
          { value: "sortie", label: t("typeSortie") },
        ].filter((option) => availableTypes.includes(option.value as "entree" | "sortie"))}
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
