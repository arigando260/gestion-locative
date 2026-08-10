import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
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
