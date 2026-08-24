"use client";

import { useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { SelectField } from "@/components/forms/select-field";
import type { Country } from "@/data/countries";

export function SignupForm({ countries }: { countries: Country[] }) {
  const t = useTranslations("auth");
  const [organizationName, setOrganizationName] = useState("");
  const [country, setCountry] = useState(countries[0]?.code ?? "");
  const [organizationPhone, setOrganizationPhone] = useState("");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);

    if (password !== confirmPassword) {
      setError(t("passwordMismatch"));
      return;
    }
    if (password.length < 6) {
      setError(t("passwordTooShort"));
      return;
    }

    setLoading(true);
    const supabase = createClient();
    // account_type/organization_name/organization_country/organization_phone/
    // full_name : forme exacte attendue par private.handle_new_user()
    // (Module 12e). organization_id n'est jamais envoyé -- ce chemin ne sert
    // qu'à créer une NOUVELLE organisation, jamais à en rejoindre une.
    // .trim() sur les champs texte : évite des espaces parasites en début/
    // fin stockés tels quels en base (observé en vérification navigateur :
    // "RIMCO " avec un espace final).
    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          account_type: "internal",
          organization_name: organizationName.trim(),
          organization_country: country,
          organization_phone: organizationPhone.trim(),
          full_name: fullName.trim(),
        },
      },
    });

    setLoading(false);

    if (signUpError) {
      // Vérifié empiriquement : les erreurs déclenchées par le trigger
      // (RAISE EXCEPTION, avec leur slug DETAIL) n'atteignent jamais le
      // client -- GoTrue les remplace par un message générique ("Database
      // error saving new user"), quelle que soit la cause réelle côté base.
      // Message générique traduit ici plutôt qu'une tentative illusoire de
      // distinguer les cas depuis signUpError.message.
      setError(t("signupGenericError"));
      return;
    }

    setSuccess(true);
  }

  if (success) {
    return (
      <div className="flex flex-col gap-2">
        <h2 className="text-lg font-semibold">{t("signupSuccessTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("signupSuccessMessage")}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="organizationName">{t("organizationName")}</Label>
        <Input
          id="organizationName"
          required
          value={organizationName}
          onChange={(event) => setOrganizationName(event.target.value)}
        />
      </div>
      <SelectField
        name="country"
        label={t("country")}
        defaultValue={country}
        onValueChange={setCountry}
        options={countries.map((c) => ({ value: c.code, label: c.name }))}
      />
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="organizationPhone">{t("phone")}</Label>
        <Input
          id="organizationPhone"
          type="tel"
          required
          value={organizationPhone}
          onChange={(event) => setOrganizationPhone(event.target.value)}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="fullName">{t("fullName")}</Label>
        <Input
          id="fullName"
          required
          value={fullName}
          onChange={(event) => setFullName(event.target.value)}
        />
      </div>
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
          minLength={6}
          autoComplete="new-password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
      </div>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="confirmPassword">{t("confirmPassword")}</Label>
        <Input
          id="confirmPassword"
          type="password"
          required
          minLength={6}
          autoComplete="new-password"
          value={confirmPassword}
          onChange={(event) => setConfirmPassword(event.target.value)}
        />
      </div>
      {error ? (
        <p className="text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}
      <Button type="submit" disabled={loading} className="w-full">
        {loading ? t("signupSubmitting") : t("signupSubmit")}
      </Button>
    </form>
  );
}
