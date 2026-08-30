import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getOrganization } from "@/data/organizations";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";
import { Sidebar, type SidebarSection } from "@/components/layout/sidebar";
import {
  LayoutGrid,
  Home,
  Building2,
  Users,
  Wrench,
  FileMinus2,
  UsersRound,
  Settings,
} from "lucide-react";

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
  const td = await getTranslations("dashboard");
  // Premier lien de nav conditionné dans ce projet -- réutilise
  // getCurrentUserPermissions()/can() (data/permissions.ts, déjà utilisée
  // par toutes les autres pages du dashboard, lit la vue my_permissions) :
  // role_permissions reste la seule source de vérité, jamais un test de
  // rôle codé en dur ici. La page /team elle-même redirige indépendamment
  // si atteinte directement sans cette permission (défense en profondeur,
  // pas seulement un masquage côté nav).
  const [permissions, organization] = await Promise.all([
    getCurrentUserPermissions(),
    getOrganization(profile.organization_id),
  ]);
  const canManageTeam = can(permissions, "users", "create");
  const canViewBuildings = can(permissions, "buildings", "read");
  // "Espace propriétaire" (maquette) : même tableau de bord staff, habillage
  // seul selon organizations.organization_type (Module 12j/12k, purement
  // cosmétique jusqu'ici) -- aucune nouvelle table/RLS, voir le plan.
  const isOwnerOrg = organization?.organization_type === "proprietaire";

  const sections: SidebarSection[] = [
    {
      label: "PARC",
      items: [
        { href: "/dashboard", label: t("dashboard"), icon: <LayoutGrid className="size-[18px]" /> },
        { href: "/properties", label: t("properties"), icon: <Home className="size-[18px]" /> },
        ...(canViewBuildings
          ? [{ href: "/buildings", label: t("buildings"), icon: <Building2 className="size-[18px]" /> }]
          : []),
        { href: "/tenants", label: t("tenants"), icon: <Users className="size-[18px]" /> },
      ],
    },
    {
      label: "GESTION",
      items: [
        { href: "/maintenance", label: t("maintenance"), icon: <Wrench className="size-[18px]" /> },
        {
          href: "/lease-terminations",
          label: t("leaseTerminations"),
          icon: <FileMinus2 className="size-[18px]" />,
        },
      ],
    },
    {
      label: "ADMINISTRATION",
      items: [
        ...(canManageTeam
          ? [{ href: "/team", label: t("team"), icon: <UsersRound className="size-[18px]" /> }]
          : []),
        { href: "/settings", label: t("settings"), icon: <Settings className="size-[18px]" /> },
      ],
    },
  ];

  return (
    <div className="flex min-h-screen">
      <Sidebar
        appName={tc("appName")}
        appSubtitle={isOwnerOrg ? td("ownerTagline") : t("dashboard")}
        sections={sections}
        footerName={profile.full_name ?? profile.email}
        footerSubtitle={organization?.name ?? ""}
      />
      <div className="flex min-h-screen flex-1 flex-col">
        <header className="flex items-center justify-end gap-3 border-b border-border px-4 py-3 sm:px-6">
          <LocaleSwitcher />
          <LogoutButton />
        </header>
        <main className="flex-1 px-4 py-6 sm:px-6">{children}</main>
      </div>
    </div>
  );
}
