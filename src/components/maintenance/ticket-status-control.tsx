"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateMaintenanceTicketStatusAction } from "@/actions/maintenance";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import type { MaintenanceTicketStatus } from "@/data/maintenance";

type Advanceable = Exclude<MaintenanceTicketStatus, "signale">;

// Suit le flux signale → en_cours → resolu/ferme déjà en place (Module 7) :
// la base n'impose pas cet ordre pour le staff (seul le verrou locataire est
// contraint par trigger), ce composant se contente de ne PROPOSER que les
// transitions attendues du flux de travail, pas de les faire respecter —
// RLS/les triggers restent seuls responsables de ce qui est réellement permis.
const NEXT_STATUSES: Record<MaintenanceTicketStatus, Advanceable[]> = {
  signale: ["en_cours"],
  en_cours: ["resolu", "ferme"],
  resolu: ["en_cours", "ferme"],
  ferme: [],
};

const ACTION_LABEL_KEY: Record<Advanceable, string> = {
  en_cours: "startProgress",
  resolu: "markResolved",
  ferme: "close",
};

export function TicketStatusControl({
  ticketId,
  status,
}: {
  ticketId: string;
  status: MaintenanceTicketStatus;
}) {
  const t = useTranslations("maintenance");
  const nextStatuses = NEXT_STATUSES[status];

  if (nextStatuses.length === 0) return null;

  return (
    <div className="flex flex-col gap-2">
      <div className="flex flex-wrap gap-2">
        {nextStatuses.map((next) => (
          <StatusButton
            key={next}
            ticketId={ticketId}
            nextStatus={next}
            // "Rouvrir" depuis resolu vers en_cours a un libellé dédié,
            // distinct de "Commencer le traitement" (même transition status,
            // sens différent selon l'origine).
            label={t(
              status === "resolu" && next === "en_cours"
                ? "reopen"
                : ACTION_LABEL_KEY[next]
            )}
          />
        ))}
      </div>
    </div>
  );
}

function StatusButton({
  ticketId,
  nextStatus,
  label,
}: {
  ticketId: string;
  nextStatus: Advanceable;
  label: string;
}) {
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateMaintenanceTicketStatusAction, null);

  return (
    <form action={formAction} className="flex flex-col items-start gap-1">
      <input type="hidden" name="id" value={ticketId} />
      <input type="hidden" name="status" value={nextStatus} />
      <SubmitButton
        pendingText={tc("loading")}
        variant={nextStatus === "ferme" ? "outline" : "default"}
      >
        {label}
      </SubmitButton>
      <FormMessage state={state} />
    </form>
  );
}
