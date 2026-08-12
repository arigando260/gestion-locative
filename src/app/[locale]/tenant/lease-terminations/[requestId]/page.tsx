import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link, redirect } from "@/i18n/navigation";
import { getCurrentTenant } from "@/data/session";
import {
  getMyLeaseTerminationRequest,
  isLeaseTerminationInitiator,
} from "@/data/lease-terminations";
import { RespondForm } from "@/components/lease-terminations/respond-form";
import { CancelButton } from "@/components/lease-terminations/cancel-button";
import { DepositRefundNotice } from "@/components/lease-terminations/deposit-refund-notice";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { LeaseTerminationStatus } from "@/data/lease-terminations";

const STATUS_KEY: Record<LeaseTerminationStatus, string> = {
  en_attente: "statusEnAttente",
  validee: "statusValidee",
  refusee: "statusRefusee",
  annulee: "statusAnnulee",
};
const STATUS_VARIANT: Record<LeaseTerminationStatus, "secondary" | "default" | "destructive" | "outline"> = {
  en_attente: "secondary",
  validee: "default",
  refusee: "destructive",
  annulee: "outline",
};

export default async function TenantLeaseTerminationPage({
  params,
}: PageProps<"/[locale]/tenant/lease-terminations/[requestId]">) {
  const { locale, requestId } = await params;

  // Symétrique du reste du portail tenant (voir tenant/layout.tsx) : une
  // session locataire est déjà garantie ici, mais getCurrentTenant() est
  // revérifié dans chaque action — pas supposé acquis du seul fait que le
  // layout parent l'a déjà vérifié.
  const tenant = await getCurrentTenant();
  if (!tenant) {
    redirect({ href: "/login", locale });
    return null;
  }

  // Appartenance revérifiée explicitement (via le bail, pas seulement RLS)
  // — voir data/lease-terminations.ts getMyLeaseTerminationRequest().
  const request = await getMyLeaseTerminationRequest(requestId, tenant.id);
  if (!request) notFound();

  const t = await getTranslations("leaseTerminations");

  const tenantInitiated = request.initiated_by_tenant_id !== null;
  const isPending = request.status === "en_attente";
  // Requirement 1 : jamais proposé à l'auteur, même côté interface — voir
  // components/lease-terminations/respond-form.tsx. Un locataire ne
  // consulte que les demandes de SON bail (getMyLeaseTerminationRequest),
  // donc "staff-initiée" suffit ici à établir qu'il peut répondre (pas
  // besoin de permission, contrairement au staff).
  const canRespond = isPending && !tenantInitiated;
  const canCancel =
    isPending && isLeaseTerminationInitiator(request, { tenantId: tenant.id });

  return (
    <div className="flex flex-col gap-6">
      <Link
        href="/tenant/lease-terminations"
        className="text-sm text-muted-foreground hover:underline"
      >
        ← {t("title")}
      </Link>

      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>{request.leases?.properties?.name ?? "—"}</CardTitle>
          <Badge variant={STATUS_VARIANT[request.status]}>{t(STATUS_KEY[request.status])}</Badge>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {request.leases?.properties && (
            <p className="text-muted-foreground">{request.leases.properties.address}</p>
          )}
          {request.leases?.organizations && (
            <p className="text-muted-foreground">{request.leases.organizations.name}</p>
          )}
          <p>
            {t("initiatedBy")}: {t(tenantInitiated ? "initiatorTenant" : "initiatorStaff")}
          </p>
          <p>
            {t("requestedEndDate")}: {request.requested_end_date}
          </p>
          <p>{t("reason")}: {request.reason}</p>
          <p className="text-muted-foreground">
            {t("createdAt")}: {request.created_at.slice(0, 10)}
          </p>

          {isPending && (
            <p className="text-muted-foreground">
              {t(tenantInitiated ? "waitingOnStaff" : "waitingOnTenant")}
            </p>
          )}

          {!isPending && request.status !== "annulee" && request.responded_at && (
            <>
              <p>
                {t("respondedBy")}: {t(request.responded_by_tenant_id ? "initiatorTenant" : "initiatorStaff")}
              </p>
              <p className="text-muted-foreground">
                {t("respondedAt")}: {request.responded_at.slice(0, 10)}
              </p>
              {request.response_note && <p>{request.response_note}</p>}
            </>
          )}

          {request.status === "annulee" && request.cancelled_at && (
            <p className="text-muted-foreground">
              {t("cancelledAt")}: {request.cancelled_at.slice(0, 10)}
            </p>
          )}
        </CardContent>
      </Card>

      <DepositRefundNotice />

      {canRespond && <RespondForm requestId={request.id} />}
      {canCancel && <CancelButton requestId={request.id} />}
    </div>
  );
}
