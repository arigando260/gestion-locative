"use client";

import { useEffect, useState } from "react";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";

// Réutilisable pour tout champ à choix fixe (fréquence, mode de paiement,
// méthode...) : le composant Select de Base UI ne rend pas de <select>
// natif avec un attribut "name", donc un input caché contrôlé porte la
// valeur réelle dans le FormData soumis à la Server Action.
export function SelectField({
  name,
  label,
  options,
  defaultValue,
  onValueChange,
  id,
}: {
  name: string;
  label: string;
  options: { value: string; label: string }[];
  defaultValue?: string;
  // Optionnel : pour les formulaires où un champ conditionne l'affichage
  // d'un autre (ex: catégorie d'imputation -> échéance à solder).
  onValueChange?: (value: string) => void;
  // Optionnel, distinct de `name` : nécessaire quand plusieurs instances du
  // même champ (même `name`, pour le FormData) coexistent sur une page —
  // sinon id DOM dupliqués. Par défaut égal à `name`, comportement inchangé
  // pour tous les appelants existants.
  id?: string;
}) {
  const fieldId = id ?? name;
  const [value, setValue] = useState(defaultValue ?? options[0]?.value ?? "");

  // Le formulaire parent peut faire vivre ce champ plus longtemps que sa
  // liste d'options (ex: échéances éligibles qui se réduit après un
  // paiement) — sans ce recalage, la valeur sélectionnée devient orpheline
  // et son libellé ne se résout plus (repli sur l'UUID brut).
  useEffect(() => {
    if (!options.some((o) => o.value === value)) {
      setValue(defaultValue ?? options[0]?.value ?? "");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [options]);

  // Notifie le parent à chaque changement (et au montage, pour la valeur
  // par défaut) — utile uniquement aux formulaires avec champs dépendants.
  useEffect(() => {
    onValueChange?.(value);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value]);

  return (
    <div className="flex flex-col gap-1.5">
      <Label htmlFor={fieldId}>{label}</Label>
      <input type="hidden" name={name} value={value} />
      <Select value={value} onValueChange={(next) => setValue(next ?? "")}>
        <SelectTrigger className="w-full" id={fieldId}>
          <SelectValue>
            {(val: string) => options.find((o) => o.value === val)?.label ?? val}
          </SelectValue>
        </SelectTrigger>
        <SelectContent>
          {options.map((option) => (
            <SelectItem key={option.value} value={option.value}>
              {option.label}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}
