"use client";

// Doit définir ses propres balises html/body (remplace le layout racine),
// et reste hors de [locale] — vrai même avec l'i18n en place (doc Next.js).
// Pas de traduction ici : ce filet de sécurité doit fonctionner même si le
// système d'i18n lui-même est en cause.
export default function GlobalError({
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  return (
    <html lang="fr">
      <body>
        <div className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-4 p-6 text-center">
          <h1 className="text-lg font-semibold">Une erreur est survenue</h1>
          <button
            type="button"
            onClick={() => retry()}
            className="rounded-lg border px-4 py-2 text-sm"
          >
            Réessayer
          </button>
        </div>
      </body>
    </html>
  );
}
