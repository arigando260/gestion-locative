import "server-only";
import { getTranslations } from "next-intl/server";

type PostgrestLikeError = {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
} | null;

const KNOWN_CODE_KEYS: Record<string, string> = {
  "23505": "uniqueViolation",
  "23503": "foreignKeyViolation",
  "23514": "checkViolation",
  "42501": "permissionDenied",
};

/**
 * Traduit une erreur Supabase/Postgres en message affichable.
 *
 * P0001 (RAISE EXCEPTION sans code explicite) est toujours un message qu'on
 * a nous-mêmes rédigé en français dans un trigger — affiché tel quel, sans
 * traduction (voir ARCHITECTURE.md pour la convention et sa limite connue).
 * Tout autre code renvoie un message générique traduit (fr/en).
 */
export async function toUserMessage(error: PostgrestLikeError): Promise<string> {
  const t = await getTranslations("errors");

  if (!error) return t("generic");
  if (error.code === "P0001" && error.message) return error.message;

  const key = error.code ? KNOWN_CODE_KEYS[error.code] : undefined;
  if (key) return t(key);

  console.error("toUserMessage: code non reconnu", {
    code: error.code,
    message: error.message,
    details: error.details,
    hint: error.hint,
  });
  return t("generic");
}
