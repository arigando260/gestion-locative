export type PropertyType = {
  id: string;
  code: string;
  name: string;
  organization_id: string | null;
};

// Les 3 types "système" (organization_id null, semés au Module 2) ont une
// clé de traduction dédiée. Un type créé par une organisation (texte libre
// saisi par elle) n'a pas d'équivalent traduit possible : on affiche alors
// son nom tel quel, dans la langue où il a été saisi.
const SYSTEM_TYPE_KEYS: Record<string, string> = {
  longue_duree: "typeLongueDuree",
  meuble_simple: "typeMeubleSimple",
  courte_duree: "typeCourteDuree",
};

// Fonction pure (pas de "server-only") : contrairement à getPropertyTypes,
// elle doit rester importable depuis des Client Components (ex: le select
// de type de bien), qui ne peuvent pas dépendre d'un module chargeant
// next/headers.
export function getPropertyTypeLabel(
  types: PropertyType[],
  code: string,
  t: (key: string) => string
) {
  const type = types.find((x) => x.code === code);
  const key = SYSTEM_TYPE_KEYS[code];
  if (type?.organization_id === null && key) return t(key);
  return type?.name ?? code;
}
