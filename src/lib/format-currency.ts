// Aucune abstraction devise dans le projet à ce jour (montants affichés
// bruts partout ailleurs) — formatage minimal pour les nouveaux écrans
// habillés (tuiles stat, carte "prochaine échéance"), FCFA en dur comme
// dans les maquettes, pas de gestion multi-devise ici.
export function formatCurrency(amount: number, locale: string): string {
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(amount)} FCFA`;
}

export function formatCompactCurrency(amount: number, locale: string): string {
  const formatted = new Intl.NumberFormat(locale, {
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(amount);
  return `${formatted} FCFA`;
}
