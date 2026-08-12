import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { getCurrentProfile } from "@/data/session";
import { getOrganization } from "@/data/organizations";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { OrganizationForm } from "@/components/settings/organization-form";
import { Card, CardContent } from "@/components/ui/card";

export default async function SettingsPage() {
  const profile = await getCurrentProfile();
  if (!profile) notFound();

  const [organization, permissions] = await Promise.all([
    getOrganization(profile.organization_id),
    getCurrentUserPermissions(),
  ]);
  if (!organization) notFound();

  const t = await getTranslations("settings");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>

      {/* Aide à l'ergonomie uniquement : la policy RLS organizations_update
          (Module 1) reste la seule autorité réelle, voir ARCHITECTURE.md. */}
      {can(permissions, "organizations", "update") ? (
        <OrganizationForm organization={organization} />
      ) : (
        <Card className="max-w-md">
          <CardContent className="flex flex-col gap-1 text-sm">
            <p className="font-medium">{organization.name}</p>
            <p className="text-muted-foreground">{organization.address || "—"}</p>
            <p className="text-muted-foreground">{organization.phone || "—"}</p>
            <p className="text-muted-foreground">{organization.email || "—"}</p>
          </CardContent>
        </Card>
      )}
    </div>
  );
}
