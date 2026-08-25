import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { ForgotPasswordForm } from "@/components/auth/forgot-password-form";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function ForgotPasswordPage() {
  const t = await getTranslations("auth");

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("forgotPasswordTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          <ForgotPasswordForm />
          <p className="mt-4 text-center text-sm text-muted-foreground">
            <Link href="/login" className="underline">
              {t("backToLogin")}
            </Link>
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
