import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link, redirect } from "@/i18n/navigation";
import { getLease } from "@/data/leases";
import { getDraftInspectionForLease, getAvailableInspectionTypes } from "@/data/inspections";
import {
  isLeaseClosureEngaged,
  leaseEndApproachingThresholdDate,
} from "@/data/lease-closure";
import { InspectionForm } from "@/components/inspections/inspection-form";

export default async function NewInspectionPage({
  params,
  searchParams,
}: PageProps<"/[locale]/leases/[leaseId]/inspections/new">) {
  const { locale, leaseId } = await params;
  const raw = await searchParams;
  const lease = await getLease(leaseId);
  if (!lease) notFound();

  const defaultType = raw.type === "entree" || raw.type === "sortie" ? raw.type : undefined;

  // Un brouillon existant (même type si précisé via ?type=, sinon tout
  // type) est repris plutôt que dupliqué — voir getDraftInspectionForLease.
  const draft = await getDraftInspectionForLease(leaseId, defaultType);
  if (draft) {
    redirect({ href: `/leases/${leaseId}/inspections/${draft.id}`, locale });
  }

  const closureEngaged = isLeaseClosureEngaged({
    status: lease.status,
    keys_returned_at: lease.keys_returned_at,
  });
  const t = await getTranslations("inspections");

  // Lien direct "?type=sortie" (ExitInspectionDueBanner) atteint alors que
  // la clôture n'est plus/pas enclenchée — cas défensif (lien obsolète ou
  // URL modifiée à la main), jamais produit par le parcours normal du
  // bandeau. availableTypes exclurait de toute façon "sortie" du sélecteur,
  // mais un message déterminé explique la cause plutôt que de basculer
  // silencieusement sur "Entrée".
  if (defaultType === "sortie" && !closureEngaged) {
    const endDateApproaching =
      lease.end_date !== null && lease.end_date <= leaseEndApproachingThresholdDate();

    return (
      <div className="flex flex-col gap-6">
        <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
        {endDateApproaching ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm text-muted-foreground">
              {t("exitClosureNotEngagedEndOfLease")}
            </p>
            <Link href={`/leases/${leaseId}`} className="text-sm hover:underline">
              {t("exitClosureNotEngagedEndOfLeaseLink")}
            </Link>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            <p className="text-sm text-muted-foreground">
              {t("exitClosureNotEngagedEarlyDeparture")}
            </p>
            <Link href="/lease-terminations/new" className="text-sm hover:underline">
              {t("exitClosureNotEngagedEarlyDepartureLink")}
            </Link>
          </div>
        )}
      </div>
    );
  }

  const availableTypes = await getAvailableInspectionTypes(leaseId, closureEngaged);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      {availableTypes.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("noAvailableTypes")}</p>
      ) : (
        <InspectionForm leaseId={lease.id} defaultType={defaultType} availableTypes={availableTypes} />
      )}
    </div>
  );
}
