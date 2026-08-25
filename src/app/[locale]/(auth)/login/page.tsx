"use client";

import { useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useRouter, Link } from "@/i18n/navigation";
import { acceptTenantInvitationForExistingAccountAction } from "@/actions/tenant-invitations";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

export default function LoginPage() {
  const t = useTranslations("auth");
  const router = useRouter();
  const searchParams = useSearchParams();
  const inviteToken = searchParams.get("inviteToken");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  // Résultat de l'acceptation d'invitation post-connexion (Module 12h) --
  // null tant qu'on n'a pas atteint cette étape (connexion classique sans
  // inviteToken, ou pas encore soumis).
  const [inviteResult, setInviteResult] = useState<
    { success: true } | { success: false; message: string } | null
  >(null);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setError(null);

    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (signInError) {
      setError(signInError.message);
      setLoading(false);
      return;
    }

    if (inviteToken) {
      // Pas de redirection aveugle : on affiche le résultat (succès ou
      // échec) avant de laisser la personne continuer, plutôt que de
      // pousser silencieusement vers /tenant sans savoir si le
      // rattachement a réellement eu lieu.
      const result = await acceptTenantInvitationForExistingAccountAction(inviteToken);
      setInviteResult(result);
      setLoading(false);
      // Pas de router.replace("/login") ici : une fois connecté,
      // proxy.ts redirige tout accès (même client-side) à /login vers
      // /dashboard -- ça écraserait cet écran de résultat avant que la
      // personne ne le voie. L'URL garde inviteToken jusqu'au clic sur
      // "Continuer" (navigation réelle vers /tenant, qui purge l'URL
      // naturellement) -- même jeton déjà accepté à ce stade de toute
      // façon, sans valeur résiduelle pour un tiers qui l'intercepterait.
      return;
    }

    router.push("/dashboard");
    router.refresh();
  }

  if (inviteResult) {
    return (
      <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
        <Card>
          <CardHeader>
            <CardTitle>
              {inviteResult.success ? t("inviteJoinSuccessTitle") : t("inviteJoinErrorTitle")}
            </CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-3">
            <p className="text-sm text-muted-foreground">
              {inviteResult.success ? t("inviteJoinSuccessMessage") : inviteResult.message}
            </p>
            <Link href="/tenant">
              <Button className="w-full">{t("continueLink")}</Button>
            </Link>
          </CardContent>
        </Card>
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-sm flex-col justify-center p-6">
      <Card>
        <CardHeader>
          <CardTitle>{t("loginTitle")}</CardTitle>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="flex flex-col gap-4">
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="email">{t("email")}</Label>
              <Input
                id="email"
                type="email"
                required
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <Label htmlFor="password">{t("password")}</Label>
              <Input
                id="password"
                type="password"
                required
                autoComplete="current-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
              <Link
                href="/forgot-password"
                className="self-end text-sm text-muted-foreground hover:underline"
              >
                {t("forgotPasswordLink")}
              </Link>
            </div>
            {error ? (
              <p className="text-sm text-destructive" role="alert">
                {error}
              </p>
            ) : null}
            <Button type="submit" disabled={loading} className="w-full">
              {loading ? t("submitting") : t("submit")}
            </Button>
          </form>
          <p className="mt-4 text-center text-sm text-muted-foreground">
            {t("loginNoAccount")}{" "}
            <Link href="/signup" className="underline">
              {t("loginNoAccountLink")}
            </Link>
          </p>
        </CardContent>
      </Card>
    </main>
  );
}
