import { getTranslations, getLocale } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getOrgStaff, getStaffInvitations } from "@/data/staff-invitations";
import { InviteStaffForm } from "@/components/team/invite-staff-form";
import { formatDateTime } from "@/lib/format-date";
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
                  <span>
                    {invitation.email} — {t(`role${capitalize(invitation.role_code)}`)}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {t("invitedOn", {
                      date: formatDateTime(invitation.created_at, dataLocale),
                    })}
                    {" — "}
                    {t("expiresOn", {
                      date: formatDateTime(invitation.expires_at, dataLocale),
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
          <CardTitle>{t("membersTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          {staff.length === 0 ? (
            <p className="text-sm text-muted-foreground">{t("membersEmpty")}</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {staff.map((member) => (
                <li
                  key={member.id}
                  className="flex items-center justify-between border-b border-border pb-2 text-sm last:border-0 last:pb-0"
                >
                  <span>{member.full_name || member.email}</span>
                  <span className="text-xs text-muted-foreground">
                    {member.role_code ? t(`role${capitalize(member.role_code)}`) : "—"}
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

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
