import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { listBuildings } from "@/data/buildings";
import { getCountries } from "@/data/countries";
import { getOrganization } from "@/data/organizations";
import { BuildingList } from "@/components/buildings/building-list";
import { BuildingForm } from "@/components/buildings/building-form";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

// Même défense en profondeur que /team (Module 12m) : bloque l'écran lui-même
// pour un accès direct par URL sans buildings:read, pas seulement le lien de
// nav (déjà conditionné dans (dashboard)/layout.tsx).
export default async function BuildingsPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) return null;

  const permissions = await getCurrentUserPermissions();
  if (!can(permissions, "buildings", "read")) {
    redirect({ href: "/dashboard", locale });
    return null;
  }

  const t = await getTranslations("buildings");
  const [buildings, countries, organization] = await Promise.all([
    listBuildings(profile.organization_id),
    getCountries(),
    getOrganization(profile.organization_id),
  ]);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>

      <BuildingList buildings={buildings} />

      {can(permissions, "buildings", "create") && (
        <Card className="max-w-md">
          <CardHeader>
            <CardTitle>{t("createTitle")}</CardTitle>
          </CardHeader>
          <CardContent>
            <BuildingForm countries={countries} defaultCountryCode={organization?.country_code} />
          </CardContent>
        </Card>
      )}
    </div>
  );
}
