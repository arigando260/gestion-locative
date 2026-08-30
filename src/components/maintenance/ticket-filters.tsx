import { getTranslations } from "next-intl/server";
import type { Property } from "@/data/properties";
import type { MaintenanceTicketFilters } from "@/data/maintenance";

// Formulaire GET natif, sans JS : pas de composant Select (pensé pour un
// FormData de Server Action, voir components/forms/select-field.tsx) — de
// simples <select> HTML suffisent à faire varier l'URL via les paramètres de
// recherche, lus côté page (app/[locale]/(dashboard)/maintenance/page.tsx).
// Pas de `action` explicite : soumis vers l'URL courante, locale comprise.
const SELECT_CLASS =
  "h-8 w-full min-w-0 rounded-lg border border-input bg-card px-2.5 text-[13px] font-medium outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";
const LABEL_CLASS = "text-[11px] font-semibold tracking-wide text-muted-foreground uppercase";

export async function TicketFilters({
  filters,
  properties,
}: {
  filters: MaintenanceTicketFilters;
  properties: Property[];
}) {
  const t = await getTranslations("maintenance");

  return (
    <form className="flex flex-wrap items-end gap-3">
      <div className="flex flex-col gap-1.5">
        <label htmlFor="status" className={LABEL_CLASS}>
          {t("filterStatus")}
        </label>
        <select
          id="status"
          name="status"
          defaultValue={filters.status ?? ""}
          className={SELECT_CLASS}
        >
          <option value="">{t("allStatuses")}</option>
          <option value="signale">{t("statusSignale")}</option>
          <option value="en_cours">{t("statusEnCours")}</option>
          <option value="resolu">{t("statusResolu")}</option>
          <option value="ferme">{t("statusFerme")}</option>
        </select>
      </div>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="priority" className={LABEL_CLASS}>
          {t("filterPriority")}
        </label>
        <select
          id="priority"
          name="priority"
          defaultValue={filters.priority ?? ""}
          className={SELECT_CLASS}
        >
          <option value="">{t("allPriorities")}</option>
          <option value="basse">{t("priorityBasse")}</option>
          <option value="normale">{t("priorityNormale")}</option>
          <option value="haute">{t("priorityHaute")}</option>
          <option value="urgente">{t("priorityUrgente")}</option>
        </select>
      </div>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="property_id" className={LABEL_CLASS}>
          {t("filterProperty")}
        </label>
        <select
          id="property_id"
          name="property_id"
          defaultValue={filters.propertyId ?? ""}
          className={SELECT_CLASS}
        >
          <option value="">{t("allProperties")}</option>
          {properties.map((property) => (
            <option key={property.id} value={property.id}>
              {property.name}
            </option>
          ))}
        </select>
      </div>
      <button
        type="submit"
        className="h-8 rounded-lg border border-input bg-card px-3 text-[13px] font-semibold hover:bg-muted"
      >
        {t("applyFilters")}
      </button>
      {(filters.status || filters.priority || filters.propertyId) && (
        <a href="?" className="text-sm text-muted-foreground hover:underline">
          {t("clearFilters")}
        </a>
      )}
    </form>
  );
}
