import { getTranslations } from "next-intl/server";
import { getTenantInvitationPreview } from "@/data/tenant-invitations";
import { InviteAcceptForm } from "@/components/auth/invite-accept-form";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function InviteAcceptPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token } = await searchParams;
  const t = await getTranslations("invite");

  // Un jeton absent, invalide ou correspondant à aucune invitation remonte
  // "aucune ligne" ici (get_tenant_invitation_preview ne distingue pas ces
  // cas — même granularité que private.handle_new_user() côté acceptation
  // réelle, pas de raison d'en dire plus côté aperçu). L'expiration, elle,
  // est vérifiée séparément ci-dessous.
  const preview = token ? await getTenantInvitationPreview(token) : null;
  // get_tenant_invitation_preview ne filtre pas sur expires_at, seulement
  // sur token_hash -- vérifié ici en plus pour ne pas afficher "vous êtes
  // invité" pour une invitation déjà expirée. La vérification faisant
  // autorité reste dans private.handle_new_user() au moment de l'acceptation
  // réelle ; celle-ci n'est qu'un affichage anticipé cohérent avec elle.
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
            <>
              <p className="mb-4 text-sm text-muted-foreground">
                {t("welcomeMessage", { organization: preview.organization_name })}
              </p>
              <InviteAcceptForm
                token={token}
                email={preview.email}
                organizationName={preview.organization_name}
              />
            </>
          )}
        </CardContent>
      </Card>
    </main>
  );
}
