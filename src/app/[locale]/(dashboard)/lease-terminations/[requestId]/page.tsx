import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  getLeaseTerminationRequest,
  isLeaseTerminationInitiator,
} from "@/data/lease-terminations";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { formatDateTime } from "@/lib/format-date";
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

export default async function LeaseTerminationPage({
  params,
}: PageProps<"/[locale]/lease-terminations/[requestId]">) {
  const { locale, requestId } = await params;
  const [request, profile, permissions] = await Promise.all([
    getLeaseTerminationRequest(requestId),
    getCurrentProfile(),
    getCurrentUserPermissions(),
  ]);

  if (!request || !profile) notFound();

  const t = await getTranslations("leaseTerminations");

  const tenantInitiated = request.initiated_by_tenant_id !== null;
  const isPending = request.status === "en_attente";
  // Requirement 1 : jamais proposé à l'auteur, même côté interface — voir
  // components/lease-terminations/respond-form.tsx.
  const canRespond =
    isPending && tenantInitiated && can(permissions, "lease_termination_requests", "update");
  const canCancel =
    isPending && isLeaseTerminationInitiator(request, { staffId: profile.id });

  return (
    <div className="flex flex-col gap-6">
      <Link href="/lease-terminations" className="text-sm text-muted-foreground hover:underline">
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
          <p>
            {t("initiatedBy")}: {t(tenantInitiated ? "initiatorTenant" : "initiatorStaff")}
          </p>
          <p>
            {t("requestedEndDate")}: {request.requested_end_date}
          </p>
          <p>{t("reason")}: {request.reason}</p>
          <p className="text-muted-foreground">
            {t("createdAt")}: {formatDateTime(request.created_at, locale)}
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
                {t("respondedAt")}: {formatDateTime(request.responded_at, locale)}
              </p>
              {request.response_note && <p>{request.response_note}</p>}
            </>
          )}

          {request.status === "annulee" && request.cancelled_at && (
            <p className="text-muted-foreground">
              {t("cancelledAt")}: {formatDateTime(request.cancelled_at, locale)}
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
