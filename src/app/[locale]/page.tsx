import { getTranslations } from "next-intl/server";
import { createClient } from "@/lib/supabase/server";
import { redirect, Link } from "@/i18n/navigation";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  CardDescription,
} from "@/components/ui/card";

// Module 12l : remplace l'ancienne redirection pure vers /login. Un
// visiteur déjà connecté est toujours renvoyé vers /dashboard (comportement
// inchangé — DashboardLayout rebondit lui-même vers /tenant si c'est un
// compte locataire) ; un visiteur anonyme voit désormais cette page
// d'accueil à 3 choix plutôt que d'atterrir directement sur /login.
export default async function Home({ params }: PageProps<"/[locale]">) {
  const { locale } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect({ href: "/dashboard", locale });
    return null;
  }

  const t = await getTranslations("home");

  return (
    <main className="mx-auto flex min-h-screen max-w-3xl flex-col justify-center gap-8 p-6">
      <div className="text-center">
        <h1 className="text-2xl font-semibold">{t("title")}</h1>
        <p className="mt-2 text-muted-foreground">{t("subtitle")}</p>
      </div>
      <div className="grid gap-4 sm:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>{t("ownerTitle")}</CardTitle>
            <CardDescription>{t("ownerDescription")}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button
              render={<Link href="/signup?type=proprietaire" />}
              nativeButton={false}
              className="w-full"
            >
              {t("ownerCta")}
            </Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>{t("agencyTitle")}</CardTitle>
            <CardDescription>{t("agencyDescription")}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button
              render={<Link href="/signup?type=agence" />}
              nativeButton={false}
              className="w-full"
            >
              {t("agencyCta")}
            </Button>
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>{t("tenantTitle")}</CardTitle>
            <CardDescription>{t("tenantDescription")}</CardDescription>
          </CardHeader>
          <CardContent>
            <Button
              render={<Link href="/tenant-info" />}
              nativeButton={false}
              variant="outline"
              className="w-full"
            >
              {t("tenantCta")}
            </Button>
          </CardContent>
        </Card>
      </div>
      <p className="text-center text-sm text-muted-foreground">
        {t("hasAccount")}{" "}
        <Link href="/login" className="underline">
          {t("hasAccountLink")}
        </Link>
      </p>
    </main>
  );
}
