import { getTranslations } from "next-intl/server";
import type { LeaseTerminationFilters as Filters } from "@/data/lease-terminations";

// Formulaire GET natif, sans JS — même principe que
// components/maintenance/ticket-filters.tsx (pas de composant Select pensé
// pour une Server Action, juste un <select> HTML qui fait varier l'URL).
const SELECT_CLASS =
  "h-8 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";

export async function LeaseTerminationFilters({ filters }: { filters: Filters }) {
  const t = await getTranslations("leaseTerminations");

  return (
    <form className="flex flex-wrap items-end gap-3">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="status" className="text-sm font-medium">
          {t("filterStatus")}
        </label>
        <select
          id="status"
          name="status"
          defaultValue={filters.status ?? ""}
          className={SELECT_CLASS}
        >
          <option value="">{t("allStatuses")}</option>
          <option value="en_attente">{t("statusEnAttente")}</option>
          <option value="validee">{t("statusValidee")}</option>
          <option value="refusee">{t("statusRefusee")}</option>
          <option value="annulee">{t("statusAnnulee")}</option>
        </select>
      </div>
      <button
        type="submit"
        className="h-8 rounded-lg border border-input bg-background px-2.5 text-sm font-medium hover:bg-muted"
      >
        {t("applyFilters")}
      </button>
      {filters.status && (
        <a href="?" className="text-sm text-muted-foreground hover:underline">
          {t("clearFilters")}
        </a>
      )}
    </form>
  );
}
