import { getTranslations } from "next-intl/server";
import { Link, redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";

export default async function DashboardLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  // Un même auth.users est soit staff (profiles) soit locataire
  // (tenant_accounts), jamais les deux — ce groupe de routes est réservé au
  // staff, on rebondit vers l'autre portail plutôt que de laisser RLS
  // renvoyer des écrans vides silencieusement.
  const profile = await getCurrentProfile();
  if (!profile) {
    const tenant = await getCurrentTenant();
    redirect({ href: tenant ? "/tenant" : "/login", locale });
    return null;
  }

  const t = await getTranslations("nav");
  const tc = await getTranslations("common");

  return (
    <div className="flex min-h-screen flex-col">
      {/* Une seule barre horizontale, pas de sidebar dédiée : le nombre de
          liens (2-3 dans cette tranche) ne justifie pas encore un panneau
          latéral distinct desktop/tiroir mobile — flex-wrap suffit à rester
          lisible sur petit écran sans composant supplémentaire. */}
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3 sm:px-6">
        <div className="flex flex-wrap items-center gap-4 sm:gap-6">
          <span className="text-sm font-semibold">{tc("appName")}</span>
          <nav className="flex items-center gap-4 text-sm">
            <Link href="/dashboard" className="hover:underline">
              {t("dashboard")}
            </Link>
            <Link href="/properties" className="hover:underline">
              {t("properties")}
            </Link>
            <Link href="/maintenance" className="hover:underline">
              {t("maintenance")}
            </Link>
            <Link href="/tenants" className="hover:underline">
              {t("tenants")}
            </Link>
            <Link href="/lease-terminations" className="hover:underline">
              {t("leaseTerminations")}
            </Link>
            <Link href="/settings" className="hover:underline">
              {t("settings")}
            </Link>
          </nav>
        </div>
        <div className="flex items-center gap-3">
          <LocaleSwitcher />
          <LogoutButton />
        </div>
      </header>
      <main className="flex-1 px-4 py-6 sm:px-6">{children}</main>
    </div>
  );
}
