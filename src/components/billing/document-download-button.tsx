"use client";

import { useState, useTransition } from "react";
import { useTranslations } from "next-intl";
import { Button } from "@/components/ui/button";
import { FormMessage } from "@/components/forms/form-message";
import type { DocumentUrlResult } from "@/actions/payment-receipts";

// Générique : partagée entre reçus (staff — génère à la volée si besoin —
// et locataire — jamais de génération) et factures (les deux, jamais de
// génération, storage_path toujours déjà connu) — les 3 cas exposent la
// même forme d'action (aucun argument, {success, message?, url?}), liée
// côté serveur (Server Action .bind()), voir les composants appelants.
export function DocumentDownloadButton({
  action,
  label,
  pendingLabel,
}: {
  action: () => Promise<DocumentUrlResult>;
  label: string;
  pendingLabel: string;
}) {
  const tc = useTranslations("common");
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);

  const handleClick = () => {
    setError(null);
    startTransition(async () => {
      const result = await action();
      if (result.success && result.url) {
        window.open(result.url, "_blank", "noopener,noreferrer");
      } else {
        setError(result.message ?? tc("loading"));
      }
    });
  };

  return (
    <div className="flex flex-col items-start gap-1">
      <Button type="button" variant="outline" size="sm" onClick={handleClick} disabled={pending}>
        {pending ? pendingLabel : label}
      </Button>
      {error && <FormMessage state={{ success: false, message: error }} />}
    </div>
  );
}
