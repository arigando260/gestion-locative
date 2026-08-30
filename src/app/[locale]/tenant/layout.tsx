import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";
import { Sidebar, type SidebarNavItem, type SidebarSection } from "@/components/layout/sidebar";
import { MobileBottomNav } from "@/components/layout/mobile-bottom-nav";
import { Home, Wrench, FileMinus2 } from "lucide-react";

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

  const navItems: SidebarNavItem[] = [
    { href: "/tenant", label: t("home"), icon: <Home className="size-[18px]" /> },
    { href: "/tenant/maintenance", label: t("maintenance"), icon: <Wrench className="size-[18px]" /> },
    {
      href: "/tenant/lease-terminations",
      label: t("leaseTerminations"),
      icon: <FileMinus2 className="size-[18px]" />,
    },
  ];
  const sections: SidebarSection[] = [{ label: "", items: navItems }];

  return (
    <div className="flex min-h-screen">
      <div className="hidden md:block">
        <Sidebar
          appName={tc("appName")}
          appSubtitle={t("portalTitle")}
          sections={sections}
          footerName={tenant.full_name ?? tenant.email}
          footerSubtitle={t("myLeases")}
        />
      </div>
      <div className="flex min-h-screen flex-1 flex-col">
        <header className="flex items-center justify-between gap-3 border-b border-border px-4 py-3 sm:px-6 md:justify-end">
          <span className="text-sm font-semibold md:hidden">{tc("appName")}</span>
          <div className="flex items-center gap-3">
            <LocaleSwitcher />
            <LogoutButton />
          </div>
        </header>
        <main className="flex-1 px-4 py-6 pb-20 sm:px-6 md:pb-6">{children}</main>
      </div>
      <MobileBottomNav items={navItems} />
    </div>
  );
}
