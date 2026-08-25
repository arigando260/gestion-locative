import { getTranslations } from "next-intl/server";
import { getCountries } from "@/data/countries";
import { Link } from "@/i18n/navigation";
import { SignupForm } from "@/components/auth/signup-form";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

// ?type=proprietaire|agence : posé par la page d'accueil publique (Module
// 12l), pré-remplit le titre affiché ET voyage jusqu'à organization_type
// dans les métadonnées de signUp() (Module 12j/12k). Toute autre valeur, ou
// absence du paramètre (accès direct à /signup) -> undefined, organisation
// créée sans type, cohérent avec la colonne nullable.
const ORGANIZATION_TYPES = ["proprietaire", "agence"] as const;
type OrganizationType = (typeof ORGANIZATION_TYPES)[number];

export default async function SignupPage({
  searchParams,
}: {
  searchParams: Promise<{ type?: string }>;
}) {
  const { type } = await searchParams;
  const organizationType = ORGANIZATION_TYPES.includes(type as OrganizationType)
    ? (type as OrganizationType)
    : undefined;

  const t = await getTranslations("auth");
  const countries = await getCountries();

  const title =
    organizationType === "proprietaire"
      ? t("signupTitleProprietaire")
      : organizationType === "agence"
        ? t("signupTitleAgence")
        : t("signupTitle");

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{title}</CardTitle>
        </CardHeader>
        <CardContent>
          <SignupForm countries={countries} organizationType={organizationType} />
          <p className="mt-4 text-center text-sm text-muted-foreground">
            {t("signupHasAccount")}{" "}
            <Link href="/login" className="underline">
              {t("signupHasAccountLink")}
            </Link>
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
