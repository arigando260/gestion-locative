import { getTranslations } from "next-intl/server";
import { redirect } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentProfile } from "@/data/session";
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
  const { data: organization } = await supabase
    .from("organizations")
    .select("name")
    .eq("id", profile.organization_id)
    .single();

  const t = await getTranslations("nav");
  const tp = await getTranslations("properties");

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
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
