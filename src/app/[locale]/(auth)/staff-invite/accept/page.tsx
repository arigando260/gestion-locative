import { getTranslations } from "next-intl/server";
import { getStaffInvitationPreview } from "@/data/staff-invitations";
import { StaffInviteAcceptForm } from "@/components/auth/staff-invite-accept-form";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function StaffInviteAcceptPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  const t = await getTranslations("staffInvite");

  // Un jeton absent, invalide ou correspondant à aucune invitation remonte
  // "aucune ligne" ici -- même granularité que /invite/accept (Module 12).
  const preview = token ? await getStaffInvitationPreview(token) : null;
  const isExpired = preview ? new Date(preview.expires_at) < new Date() : false;

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("title")}</CardTitle>
        </CardHeader>
        <CardContent>
          {!preview || !token ? (
            <div className="flex flex-col gap-2">
              <h2 className="text-lg font-semibold">{t("invalidTitle")}</h2>
              <p className="text-sm text-muted-foreground">{t("invalidMessage")}</p>
            </div>
          ) : preview.status !== "en_attente" || isExpired ? (
            <div className="flex flex-col gap-2">
              <h2 className="text-lg font-semibold">{t("invalidTitle")}</h2>
              <p className="text-sm text-muted-foreground">{t("invalidMessage")}</p>
            </div>
          ) : (
            <StaffInviteAcceptForm
              token={token}
              email={preview.email}
              organizationName={preview.organization_name}
              roleCode={preview.role_code}
            />
          )}
        </CardContent>
      </Card>
    </main>
  );
}
