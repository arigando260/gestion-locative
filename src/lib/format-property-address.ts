// Formatage désormais calculé côté base par private.resolve_property_address
// (Module 13, exposée via le wrapper public.resolve_property_address —
// Module 13b) : gère à la fois un bien autonome et un bien rattaché à un
// immeuble (adresse héritée + identifiant d'unité), jamais reconstruit ici.
// Ne reste qu'un repli d'affichage si la résolution n'a rien renvoyé.
export function formatPropertyAddress(resolved: { formatted_address: string | null }): string {
  return resolved.formatted_address || "—";
}
