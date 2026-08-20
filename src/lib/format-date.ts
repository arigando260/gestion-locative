// La locale reçue vient de useLocale()/getLocale() (next-intl), typés
// `string` dans ce projet — aucune augmentation de type n'y restreint le
// retour à Locale ("fr" | "en"). Élargir le paramètre à `string` évite un
// cast à chaque site d'appel ; le repli sur "fr" ci-dessous couvre le cas
// (normalement inatteignable) d'une valeur hors des locales configurées,
// sans jamais planter sur un accès de tableau undefined. Locales
// dupliquées ici en dur (pas d'import de @/i18n/routing) : ce module reste
// ainsi autonome, sans dépendance runtime au reste du projet.
const DEFAULT_LOCALE = "fr";

const MONTH_NAMES: Record<"fr" | "en", string[]> = {
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
export function formatDate(value: string | null | undefined, locale: string): string {
  if (!value) return "—";

  const match = DATE_RE.exec(value);
  if (!match) {
    console.error("formatDate: valeur inattendue", { value });
    return "—";
  }

  const [, year, month, day] = match;
  const months = MONTH_NAMES[locale as keyof typeof MONTH_NAMES] ?? MONTH_NAMES[DEFAULT_LOCALE];
  const monthName = months[Number(month) - 1];
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
export function formatDateTime(value: string | null | undefined, locale: string): string {
  if (!value) return "—";

  const match = DATETIME_RE.exec(value);
  if (!match) {
    console.error("formatDateTime: valeur inattendue", { value });
    return "—";
  }

  const [, year, month, day, hour, minute] = match;
  const months = MONTH_NAMES[locale as keyof typeof MONTH_NAMES] ?? MONTH_NAMES[DEFAULT_LOCALE];
  const monthName = months[Number(month) - 1];
  if (!monthName) {
    console.error("formatDateTime: mois hors plage", { value });
    return "—";
  }

  return `${Number(day)} ${monthName} ${year}, ${hour}:${minute}`;
}
