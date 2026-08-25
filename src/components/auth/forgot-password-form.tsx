"use client";

import { useState, type FormEvent } from "react";
import { useTranslations, useLocale } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export function ForgotPasswordForm() {
  const t = useTranslations("auth");
  const locale = useLocale();
  const [email, setEmail] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setLoading(true);

    const supabase = createClient();
    // resetPasswordForEmail a le même comportement anti-énumération que
    // signUp() (Module 12) : `error` reste null même si aucun compte
    // n'existe pour cet email, GoTrue ne le révèle jamais au client. Le
    // message de succès est donc formulé pour rester vrai dans les deux
    // cas ("si un compte existe...") plutôt que d'affirmer un envoi réel.
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/${locale}/reset-password`,
    });

    setLoading(false);

    if (resetError) {
      setError(t("forgotPasswordGenericError"));
      return;
    }

    setSuccess(true);
  }

  if (success) {
    return (
      <div className="flex flex-col gap-2">
        <h2 className="text-lg font-semibold">{t("forgotPasswordSuccessTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("forgotPasswordSuccessMessage")}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
      <p className="text-sm text-muted-foreground">{t("forgotPasswordMessage")}</p>
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
      {error ? (
        <p className="text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}
      <Button type="submit" disabled={loading} className="w-full">
        {loading ? t("forgotPasswordSubmitting") : t("forgotPasswordSubmit")}
      </Button>
    </form>
  );
}
