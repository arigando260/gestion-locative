import { getTranslations } from "next-intl/server";
import { getCountries } from "@/data/countries";
import { SignupForm } from "@/components/auth/signup-form";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default async function SignupPage() {
  const t = await getTranslations("auth");
  const countries = await getCountries();

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("signupTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          <SignupForm countries={countries} />
        </CardContent>
      </Card>
    </main>
  );
}
