import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getBuilding } from "@/data/buildings";
import { formatBuildingAddress } from "@/components/buildings/building-list";
import { getBuildingInvoicingSummary } from "@/data/building-invoicing";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { BuildingInvoicingSummaryView } from "@/components/billing/building-invoicing-summary";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// "YYYY-MM" -- valeur native d'un <input type="month">. new Date() ici sert
// uniquement à obtenir "maintenant" (pas à parser une date stockée), même
// usage déjà accepté ailleurs dans le projet (issuedDate dans
// actions/schedule-invoices.tsx, scheduleCoverageThresholdDate).
function currentMonth(): string {
  return new Date().toISOString().slice(0, 7);
}

const MONTH_RE = /^\d{4}-\d{2}$/;

// Fiche immeuble volontairement minimale (nom + adresse + facturation
// groupée) : ce chantier ne demande pas un écran de gestion complet des
// logements de l'immeuble, seulement un point d'entrée pour la
// facturation par mois -- pas de liste de logements ici pour l'instant.
export default async function BuildingDetailPage({
  params,
  searchParams,
}: PageProps<"/[locale]/buildings/[buildingId]">) {
  const { buildingId } = await params;
  const sp = await searchParams;
  const monthParam = typeof sp.month === "string" ? sp.month : undefined;
  const month = monthParam && MONTH_RE.test(monthParam) ? monthParam : currentMonth();

  const [building, permissions] = await Promise.all([
    getBuilding(buildingId),
    getCurrentUserPermissions(),
  ]);

  // Pas de gating explicite ici au-delà de RLS (comme la fiche bien,
  // properties/[propertyId]/page.tsx) : buildings_select renvoie déjà null
  // pour un immeuble hors organisation ou hors permission -- notFound()
  // suffit, pas besoin de dupliquer la policy en can().
  if (!building) notFound();

  const t = await getTranslations("buildings");
  const tb = await getTranslations("billing");

  // Génération de facture réservée à has_permission('schedule_invoices','create')
  // (agent/admin) -- réutilise le catalogue de permissions existant, aucune
  // nouvelle entrée nécessaire (Règle 1 : pas de migration).
  const canGenerateInvoices = can(permissions, "schedule_invoices", "create");
  const summary = canGenerateInvoices
    ? await getBuildingInvoicingSummary(buildingId, month)
    : null;

  return (
    <div className="flex flex-col gap-6">
      <Link href="/buildings" className="text-sm text-muted-foreground hover:underline">
        ← {t("backToList")}
      </Link>
      <Card className="max-w-md">
        <CardHeader>
          <CardTitle>{building.name}</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          {formatBuildingAddress(building)}
        </CardContent>
      </Card>

      {canGenerateInvoices && summary && (
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{tb("buildingInvoicingTitle")}</h2>
          <BuildingInvoicingSummaryView buildingId={buildingId} month={month} summary={summary} />
        </div>
      )}
    </div>
  );
}
