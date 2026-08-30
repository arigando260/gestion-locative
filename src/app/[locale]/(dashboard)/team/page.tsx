import { getTranslations, getLocale } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getOrgStaff, getStaffInvitations } from "@/data/staff-invitations";
import { InviteStaffForm } from "@/components/team/invite-staff-form";
import { formatDateTime } from "@/lib/format-date";
import { AvatarInitials } from "@/components/ui/avatar-initials";
import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

// Visible seulement si can(permissions, 'users', 'create') -- pas seulement
// le lien de nav (déjà conditionné dans (dashboard)/layout.tsx), l'écran
// lui-même : un accès direct par URL sans la permission ne doit pas non
// plus révéler la liste des invitations/membres. Bloquer par défaut plutôt
// que de compter sur la RLS pour rendre silencieusement une liste vide --
// même philosophie que (dashboard)/layout.tsx redirigeant hors du portail
// staff pour un compte locataire.
//
// getCurrentUserPermissions()/can() (data/permissions.ts, infrastructure déjà
// existante depuis avant ce module -- lit la vue my_permissions, cachée par
// requête via React cache()) plutôt qu'une RPC has_permission dédiée : la
// RPC initialement conçue pour ce gating était redondante avec ce mécanisme
// déjà en place et déjà utilisé par tous les autres écrans du dashboard --
// abandonnée en cours de route, voir le rapport final pour le détail.
export default async function TeamPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) return null;

  const permissions = await getCurrentUserPermissions();
  if (!can(permissions, "users", "create")) {
    redirect({ href: "/dashboard", locale });
    return null;
  }

  const t = await getTranslations("team");
  const dataLocale = await getLocale();
  const [staff, invitations] = await Promise.all([
    getOrgStaff(profile.organization_id),
    getStaffInvitations(profile.organization_id),
  ]);

  const pendingInvitations = invitations.filter(
    (invitation) => invitation.status === "en_attente"
  );

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>

      <InviteStaffForm />

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
                  <AvatarInitials name={invitation.email} tone="system" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13.5px] font-semibold">{invitation.email}</div>
                    <div className="truncate text-[12px] text-muted-foreground">
                      {t("invitedOn", { date: formatDateTime(invitation.created_at, dataLocale) })}
                      {" — "}
                      {t("expiresOn", { date: formatDateTime(invitation.expires_at, dataLocale) })}
                    </div>
                  </div>
                  <Badge variant="secondary">{t(`role${capitalize(invitation.role_code)}`)}</Badge>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <Card className="p-0">
        <CardHeader className="px-[22px] pt-4 pb-1">
          <CardTitle className="text-[15px] font-bold">{t("membersTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="px-0">
          {staff.length === 0 ? (
            <p className="px-[22px] py-4 text-sm text-muted-foreground">{t("membersEmpty")}</p>
          ) : (
            <div className="flex flex-col">
              {staff.map((member) => (
                <div
                  key={member.id}
                  className="flex items-center gap-3 border-t border-[#f2f2f4] px-[22px] py-[13px] first:border-t-0 hover:bg-[#fafafa]"
                >
                  <AvatarInitials name={member.full_name || member.email} tone="system" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-[13.5px] font-semibold">
                      {member.full_name || member.email}
                    </div>
                    {member.full_name ? (
                      <div className="truncate text-[12px] text-muted-foreground">{member.email}</div>
                    ) : null}
                  </div>
                  {member.role_code ? (
                    <Badge variant="secondary">{t(`role${capitalize(member.role_code)}`)}</Badge>
                  ) : null}
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
