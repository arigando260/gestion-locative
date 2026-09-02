import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile, getCurrentTenant, getCurrentStaffRole } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getOrganization } from "@/data/organizations";
import { getUpcomingDeadlinesCount } from "@/data/upcoming-deadlines";
import { getMonthRentSchedules, summarizeMonthRentSchedules } from "@/data/rent-collection";
import { getBuildingsCount } from "@/data/buildings";
import { getPropertiesCount } from "@/data/properties";
import { getOrgTenantsCount } from "@/data/tenant-invitations";
import { LogoutButton } from "@/components/layout/logout-button";
import { LocaleSwitcher } from "@/components/layout/locale-switcher";
import { HeaderAddPropertyButton } from "@/components/layout/header-add-property-button";
import { Sidebar, type SidebarSection } from "@/components/layout/sidebar";
import {
  LayoutGrid,
  Home,
  Building2,
  Users,
  Wrench,
  FileMinus2,
  CalendarClock,
  Banknote,
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
  const tp = await getTranslations("properties");
  // Premier lien de nav conditionné dans ce projet -- réutilise
  // getCurrentUserPermissions()/can() (data/permissions.ts, déjà utilisée
  // par toutes les autres pages du dashboard, lit la vue my_permissions) :
  // role_permissions reste la seule source de vérité, jamais un test de
  // rôle codé en dur ici. La page /team elle-même redirige indépendamment
  // si atteinte directement sans cette permission (défense en profondeur,
  // pas seulement un masquage côté nav).
  // organization récupérée avant le reste : isOwnerOrg (organization_type)
  // conditionne quelles requêtes suivantes sont lancées (comptes Espace
  // propriétaire ci-dessous), donc doit être connue en premier plutôt que
  // dans le même Promise.all que ce qu'elle conditionne.
  const [role, organization] = await Promise.all([
    getCurrentStaffRole(),
    getOrganization(profile.organization_id),
  ]);
  // "Espace propriétaire" (maquette) : même tableau de bord staff, habillage
  // seul selon organizations.organization_type (Module 12j/12k) -- aucune
  // nouvelle table/RLS, voir le plan.
  const isOwnerOrg = organization?.organization_type === "proprietaire";

  // Badges "Échéances"/"Loyers & paiements" masqués pour l'agent (même
  // périmètre que les pages elles-mêmes, qui redirigent l'agent) -- inutile
  // de lancer les requêtes sous-jacentes pour un badge qui ne s'affichera
  // jamais. getMonthRentSchedules est la même fonction groupée que celle
  // utilisée par /dashboard/loyers (data/rent-collection.ts) -- une seule
  // requête, pas une par badge.
  //
  // Comptes "Mon logement/immeuble/locataire" (Espace propriétaire) :
  // lancés uniquement si isOwnerOrg -- coût zéro pour l'agence. getBuildingsCount
  // est mise en cache par requête (React cache(), data/buildings.ts) :
  // dashboard/page.tsx (via getDashboardStats) lit la même valeur sur le
  // même chargement de page, un seul aller-retour réel malgré les deux
  // appels.
  const [
    permissions,
    upcomingDeadlinesCount,
    monthRentSchedules,
    ownerBuildingsCount,
    ownerPropertiesCount,
    ownerTenantsCount,
  ] = await Promise.all([
    getCurrentUserPermissions(),
    role === "agent" ? Promise.resolve(0) : getUpcomingDeadlinesCount(profile.organization_id),
    role === "agent" ? Promise.resolve([]) : getMonthRentSchedules(profile.organization_id),
    isOwnerOrg ? getBuildingsCount(profile.organization_id) : Promise.resolve(0),
    isOwnerOrg ? getPropertiesCount(profile.organization_id) : Promise.resolve(0),
    isOwnerOrg ? getOrgTenantsCount(profile.organization_id) : Promise.resolve(0),
  ]);
  const rentsSummary = summarizeMonthRentSchedules(monthRentSchedules);
  const rentsBadgeCount = rentsSummary.overdueCount + rentsSummary.partialCount;
  const canManageTeam = can(permissions, "users", "create");
  // Agence : visibilité par permission, comportement strictement inchangé.
  // Propriétaire : visibilité par donnée réelle (0 immeuble = rubrique
  // masquée), décision produit actée -- deux critères différents et
  // volontairement distincts, jamais fusionnés.
  const canViewBuildings = can(permissions, "buildings", "read");
  const ownerCanViewBuildings = ownerBuildingsCount > 0;
  // En-tête enrichi (CTA "Ajouter un logement") réservé à l'Espace Agence
  // -- ni l'agent ni le propriétaire n'ont cet élément dans leur propre
  // maquette (audit validé), header inchangé pour eux. Permission réelle
  // (pas juste un gate visuel) : même vérification que le bouton déjà
  // présent sur /properties (properties/page.tsx), pas de nouvelle regle.
  const isAgenceContext = !isOwnerOrg && role !== "agent";
  const canCreateProperty = can(permissions, "properties", "create");

  const sections: SidebarSection[] = [
    {
      label: isOwnerOrg ? t("sectionMyPortfolio") : "PARC",
      items: [
        { href: "/dashboard", label: t("dashboard"), icon: <LayoutGrid className="size-[18px]" /> },
        {
          href: "/properties",
          label: isOwnerOrg ? t("propertiesOwner", { count: ownerPropertiesCount }) : t("properties"),
          icon: <Home className="size-[18px]" />,
        },
        ...((isOwnerOrg ? ownerCanViewBuildings : canViewBuildings)
          ? [{ href: "/buildings", label: t("buildings"), icon: <Building2 className="size-[18px]" /> }]
          : []),
        {
          href: "/tenants",
          label: isOwnerOrg ? t("tenantsOwner", { count: ownerTenantsCount }) : t("tenants"),
          icon: <Users className="size-[18px]" />,
        },
      ],
    },
    {
      label: isOwnerOrg ? t("sectionFollowUp") : "GESTION",
      items: [
        ...(role !== "agent"
          ? [
              {
                href: "/dashboard/loyers",
                label: t("rents"),
                icon: <Banknote className="size-[18px]" />,
                badgeCount: rentsBadgeCount,
              },
            ]
          : []),
        { href: "/maintenance", label: t("maintenance"), icon: <Wrench className="size-[18px]" /> },
        {
          href: "/lease-terminations",
          label: t("leaseTerminations"),
          icon: <FileMinus2 className="size-[18px]" />,
        },
        ...(role !== "agent"
          ? [
              {
                href: "/dashboard/echeances",
                label: t("deadlines"),
                icon: <CalendarClock className="size-[18px]" />,
                badgeCount: upcomingDeadlinesCount,
              },
            ]
          : []),
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
        appSubtitle={isOwnerOrg ? td("ownerTagline") : tc("appTagline")}
        sections={sections}
        footerName={profile.full_name ?? profile.email}
        footerSubtitle={
          isOwnerOrg && organization?.name
            ? `${organization.name} · ${t("ownerRoleLabel")}`
            : (organization?.name ?? "")
        }
      />
      <div className="flex min-h-screen flex-1 flex-col">
        <header className="flex items-center justify-end gap-3 border-b border-border px-4 py-3 sm:px-6">
          {isAgenceContext && canCreateProperty ? (
            <HeaderAddPropertyButton label={tp("create")} />
          ) : null}
          <LocaleSwitcher />
          <LogoutButton />
        </header>
        <main className="flex-1 px-4 py-6 sm:px-6">{children}</main>
      </div>
    </div>
  );
}
