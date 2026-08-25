import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function TenantInfoPage() {
  const t = await getTranslations("home");

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("tenantInfoTitle")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <p className="text-sm text-muted-foreground">{t("tenantInfoMessage")}</p>
          <div className="flex flex-col gap-2 text-center text-sm text-muted-foreground">
            <Link href="/" className="underline">
              {t("backToHome")}
            </Link>
            <Link href="/login" className="underline">
              {t("tenantInfoLoginLink")}
            </Link>
          </div>
        </CardContent>
      </Card>
    </main>
  );
}
