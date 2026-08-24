import { getTranslations, getLocale } from "next-intl/server";
import { getCurrentProfile } from "@/data/session";
import { getOrgTenants, getTenantInvitations } from "@/data/tenant-invitations";
import { InviteTenantForm } from "@/components/tenants/invite-tenant-form";
import { formatDateTime } from "@/lib/format-date";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

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

      <Card>
        <CardHeader>
          <CardTitle>{t("pendingTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          {pendingInvitations.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("pendingEmpty")}</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {pendingInvitations.map((invitation) => (
                <li
                  key={invitation.id}
                  className="flex flex-col gap-0.5 border-b border-border pb-2 text-sm last:border-0 last:pb-0"
                >
                  <span>{invitation.email}</span>
                  <span className="text-xs text-muted-foreground">
                    {t("invitedOn", {
                      date: formatDateTime(invitation.created_at, locale),
                    })}
                    {" — "}
                    {t("expiresOn", {
                      date: formatDateTime(invitation.expires_at, locale),
                    })}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t("listTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          {tenants.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("empty")}</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {tenants.map((tenant) => (
                <li
                  key={tenant.tenant_account_id}
                  className="flex items-center justify-between border-b border-border pb-2 text-sm last:border-0 last:pb-0"
                >
                  <span>{tenant.full_name || tenant.email}</span>
                  <span className="text-xs text-muted-foreground">
                    {tenant.status === "actif" ? t("statusActif") : t("statusInactif")}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
