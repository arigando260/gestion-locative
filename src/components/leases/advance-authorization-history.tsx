import { getTranslations, getLocale } from "next-intl/server";
import { formatDateTime } from "@/lib/format-date";
import type { LeaseAdvanceAuthorizationEvent } from "@/data/deposits";

const ACTION_KEY: Record<string, string> = {
  authorized: "advanceEventAuthorized",
  revoked: "advanceEventRevoked",
};

// Même patron que deposit-ledger-table.tsx : lecture seule, aucune écriture
// possible depuis ce composant (la table source est alimentée uniquement
// par trigger, voir data/deposits.ts getLeaseAdvanceAuthorizationEvents).
export async function AdvanceAuthorizationHistory({
  events,
}: {
  events: LeaseAdvanceAuthorizationEvent[];
}) {
  const t = await getTranslations("deposits");
  const locale = await getLocale();

  if (events.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("advanceAuthorizationHistoryEmpty")}</p>;
  }

  return (
    <div className="flex flex-col gap-1">
      <p className="text-sm font-medium">{t("advanceAuthorizationHistoryTitle")}</p>
      <ul className="flex flex-col gap-0.5 text-sm text-muted-foreground">
        {events.map((event) => (
          <li key={event.id}>
            {t(ACTION_KEY[event.action] ?? "advanceEventAuthorized")} — {formatDateTime(event.occurred_at, locale)}
          </li>
        ))}
      </ul>
    </div>
  );
}
