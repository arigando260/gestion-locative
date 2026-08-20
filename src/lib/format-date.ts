import type { Locale } from "@/i18n/routing";

const MONTH_NAMES: Record<Locale, string[]> = {
  fr: [
    "janvier",
    "février",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "août",
    "septembre",
    "octobre",
    "novembre",
    "décembre",
  ],
  en: [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ],
};

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})/;
const DATETIME_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/;

// Jamais de `new Date(value)` ici : une colonne "date" ou "timestamptz" lue
// depuis la base est déjà le bon jour/la bonne heure à afficher tel quel —
// le projet n'applique aucune conversion de fuseau horaire nulle part
// (voir l'unique précédent d'affichage d'un timestamptz avant cette
// fonction : invoice.generated_at.slice(0, 16).replace("T", " ")).
// Construire un objet Date puis lire ses composants locaux réintroduirait
// ce risque selon le fuseau du runtime (serveur ou navigateur) qui
// l'exécute — on extrait donc les chiffres directement de la chaîne.
export function formatDate(value: string | null | undefined, locale: Locale): string {
  if (!value) return "—";

  const match = DATE_RE.exec(value);
  if (!match) {
    console.error("formatDate: valeur inattendue", { value });
    return "—";
  }

  const [, year, month, day] = match;
  const monthName = MONTH_NAMES[locale][Number(month) - 1];
  if (!monthName) {
    console.error("formatDate: mois hors plage", { value });
    return "—";
  }

  return `${Number(day)} ${monthName} ${year}`;
}

// Ignore volontairement les secondes, la fraction de seconde et le suffixe
// d'offset (`Z` ou `+00:00`) — même principe que l'ancien
// generated_at.slice(0, 16) qu'elle remplace : les chiffres heure/minute
// bruts de la chaîne sont affichés tels quels, jamais convertis.
export function formatDateTime(value: string | null | undefined, locale: Locale): string {
  if (!value) return "—";

  const match = DATETIME_RE.exec(value);
  if (!match) {
    console.error("formatDateTime: valeur inattendue", { value });
    return "—";
  }

  const [, year, month, day, hour, minute] = match;
  const monthName = MONTH_NAMES[locale][Number(month) - 1];
  if (!monthName) {
    console.error("formatDateTime: mois hors plage", { value });
    return "—";
  }

  return `${Number(day)} ${monthName} ${year}, ${hour}:${minute}`;
}
