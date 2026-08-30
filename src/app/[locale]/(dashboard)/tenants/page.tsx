import { getTranslations, getLocale } from "next-intl/server";
import { getCurrentProfile } from "@/data/session";
import { getOrgTenants, getTenantInvitations } from "@/data/tenant-invitations";
import { InviteTenantForm } from "@/components/tenants/invite-tenant-form";
import { formatDateTime } from "@/lib/format-date";
import { AvatarInitials } from "@/components/ui/avatar-initials";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

const TENANT_STATUS_VARIANT = {
  actif: "success",
  inactif: "secondary",
} as const;

export default async function TenantsPage() {
  const profile = await getCurrentProfile();
  if (!profile) return null;

  const t = await getTranslations("tenants");
  const locale = await getLocale();
  const [tenants, invitations] = await Promise.all([
    getOrgTenants(profile.organization_id),
    getTenantInvitations(profile.organization_id),
  ]);

  const pendingInvitations = invitations.filter(
    (invitation) => invitation.status === "en_attente"
  );

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>

      <InviteTenantForm />

      <Card className="p-0">
        <CardHeader className="px-[22px] pt-4 pb-1">
          <CardTitle className="text-[15px] font-bold">{t("pendingTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {pendingInvitations.length === 0 ? (
            <p className="px-[22px] py-4 text-sm text-muted-foreground">{t("pendingEmpty")}</p>
          ) : (
            <div className="flex flex-col">
              {pendingInvitations.map((invitation) => (
                <div
                  key={invitation.id}
                  className="flex items-center gap-3 border-t border-[#f2f2f4] px-[22px] py-[13px] first:border-t-0 hover:bg-[#fafafa]"
                >
                  <AvatarInitials name={invitation.email} tone="person" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13.5px] font-semibold">{invitation.email}</div>
                    <div className="truncate text-[12px] text-muted-foreground">
                      {t("invitedOn", { date: formatDateTime(invitation.created_at, locale) })}
                      {" — "}
                      {t("expiresOn", { date: formatDateTime(invitation.expires_at, locale) })}
                    </div>
                  </div>
                  <Badge variant="warning">{t("invitationStatusEnAttente")}</Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="p-0">
        <CardHeader className="px-[22px] pt-4 pb-1">
          <CardTitle className="text-[15px] font-bold">{t("listTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {tenants.length === 0 ? (
            <p className="px-[22px] py-4 text-sm text-muted-foreground">{t("empty")}</p>
          ) : (
            <div className="flex flex-col">
              {tenants.map((tenant) => (
                <div
                  key={tenant.tenant_account_id}
                  className="flex items-center gap-3 border-t border-[#f2f2f4] px-[22px] py-[13px] first:border-t-0 hover:bg-[#fafafa]"
                >
                  <AvatarInitials name={tenant.full_name || tenant.email} tone="person" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13.5px] font-semibold">
                      {tenant.full_name || tenant.email}
                    </div>
                    {tenant.full_name ? (
                      <div className="truncate text-[12px] text-muted-foreground">{tenant.email}</div>
                    ) : null}
                  </div>
                  <Badge variant={TENANT_STATUS_VARIANT[tenant.status]}>
                    {tenant.status === "actif" ? t("statusActif") : t("statusInactif")}
                  </Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
