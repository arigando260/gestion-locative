import { getTranslations } from "next-intl/server";
import { Link, redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";

export default async function TenantLayout({
  children,
  params,
}: {
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;

  // Symétrique de (dashboard)/layout.tsx : ce segment est réservé aux
  // comptes locataires, on rebondit vers l'autre portail sinon.
  const tenant = await getCurrentTenant();
  if (!tenant) {
    const profile = await getCurrentProfile();
    redirect({ href: profile ? "/dashboard" : "/login", locale });
    return null;
  }

  const t = await getTranslations("tenant");
  const tc = await getTranslations("common");

  return (
    <div className="flex min-h-screen flex-col">
      <header className="flex flex-wrap items-center justify-between gap-3 border-b border-border px-4 py-3 sm:px-6">
        <div className="flex flex-wrap items-center gap-4 sm:gap-6">
          <span className="text-sm font-semibold">{tc("appName")}</span>
          <nav className="flex items-center gap-4 text-sm">
            <Link href="/tenant" className="hover:underline">
              {t("myLeases")}
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
