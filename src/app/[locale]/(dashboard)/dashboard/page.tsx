import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/data/session";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { getLeasesWithLowScheduleCoverage } from "@/data/schedules";
import { Link } from "@/i18n/navigation";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function DashboardPage({
  params,
}: PageProps<"/[locale]/dashboard">) {
  const { locale } = await params;
  const profile = await getCurrentProfile();
  if (!profile) {
    redirect({ href: "/login", locale });
    return null;
  }

  const supabase = await createClient();
  const [{ data: organization }, permissions] = await Promise.all([
    supabase
      .from("organizations")
      .select("name")
      .eq("id", profile.organization_id)
      .single(),
    getCurrentUserPermissions(),
  ]);

  const canReadSchedules = can(permissions, "payment_schedules", "read");
  const lowCoverageLeases = canReadSchedules
    ? await getLeasesWithLowScheduleCoverage(profile.organization_id)
    : [];

  const t = await getTranslations("nav");
  const tp = await getTranslations("properties");
  const td = await getTranslations("dashboard");

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      {lowCoverageLeases.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">{td("lowCoverageTitle")}</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-2">
            {lowCoverageLeases.map((lease) => (
              <Link
                key={lease.lease_id}
                href={`/leases/${lease.lease_id}`}
                className="flex flex-col gap-0.5 rounded-md border p-3 text-sm hover:bg-muted"
              >
                <span className="font-medium">
                  {lease.property_name} — {lease.tenant_full_name}
                </span>
                <span className="text-muted-foreground">
                  {lease.coverage_end_date
                    ? td("lowCoverageUntil", { date: lease.coverage_end_date })
                    : td("lowCoverageNoSchedule")}
                </span>
              </Link>
            ))}
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle>{organization?.name}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm text-muted-foreground">
          <p>{profile.full_name ?? profile.email}</p>
        </CardContent>
      </Card>
      {/* @base-ui/react utilise "render" (élément à fusionner), pas "asChild"
          comme Radix — c'est la convention à suivre partout dans ce projet
          pour rendre un Button/Link polymorphe. */}
      <Button className="w-fit" render={<Link href="/properties" />} nativeButton={false}>
        {t("properties")} — {tp("title")}
      </Button>
    </div>
  );
}
