// Compose "Quartier, Ville" à partir des champs structurés (Module 12c),
// avec le complément ajouté s'il existe. Pour les biens dev existants
// (city/neighborhood encore NULL, non complétés manuellement) : repli sur
// address_complement seul -- c'est justement l'ancien texte libre préservé
// par le RENAME de la migration, pas une valeur perdue.
export function formatPropertyAddress(property: {
  city: string | null;
  neighborhood: string | null;
  address_complement: string | null;
}): string {
  const location = [property.neighborhood, property.city].filter(Boolean).join(", ");

  if (location && property.address_complement) {
    return `${location} — ${property.address_complement}`;
  }
  return location || property.address_complement || "—";
}
