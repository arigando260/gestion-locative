import { getTranslations } from "next-intl/server";
import type { Property } from "@/data/properties";
import type { MaintenanceTicketFilters } from "@/data/maintenance";

// Formulaire GET natif, sans JS : pas de composant Select (pensé pour un
// FormData de Server Action, voir components/forms/select-field.tsx) — de
// simples <select> HTML suffisent à faire varier l'URL via les paramètres de
// recherche, lus côté page (app/[locale]/(dashboard)/maintenance/page.tsx).
// Pas de `action` explicite : soumis vers l'URL courante, locale comprise.
const SELECT_CLASS =
  "h-8 w-full min-w-0 rounded-lg border border-input bg-transparent px-2.5 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30";

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
          <option value="signale">{t("statusSignale")}</option>
          <option value="en_cours">{t("statusEnCours")}</option>
          <option value="resolu">{t("statusResolu")}</option>
          <option value="ferme">{t("statusFerme")}</option>
        </select>
      </div>
      <div className="flex flex-col gap-1.5">
        <label htmlFor="priority" className="text-sm font-medium">
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
        <label htmlFor="property_id" className="text-sm font-medium">
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
        className="h-8 rounded-lg border border-input bg-background px-2.5 text-sm font-medium hover:bg-muted"
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
