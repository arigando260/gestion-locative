"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Phase = "loading" | "create" | "already-exists";

// Contrairement à InviteAcceptForm (locataire, 3 branches + rattachement
// direct pour un compte déjà existant, Module 12g/12h), il n'existe aucun
// chemin de rattachement possible ici : un profil interne appartient à une
// seule organisation à vie (voir le commentaire de
// check_staff_invitation_existing_account, Module 12m). Donc seulement 2
// issues possibles après détection : "create" (email inédit, signUp()
// normal) ou "already-exists" (refus explicite, jamais une tentative de
// rattachement).
export function StaffInviteAcceptForm({
  token,
  email,
  organizationName,
  roleCode,
}: {
  token: string;
  email: string;
  organizationName: string;
  roleCode: string;
}) {
  const t = useTranslations("staffInvite");
  const [phase, setPhase] = useState<Phase>("loading");

  useEffect(() => {
    let cancelled = false;

    async function detect() {
      const supabase = createClient();
      const { data: existsData } = await supabase.rpc(
        "check_staff_invitation_existing_account",
        { p_token: token }
      );

      if (cancelled) return;
      setPhase(existsData ? "already-exists" : "create");
    }

    detect();
    return () => {
      cancelled = true;
    };
  }, [token]);

  if (phase === "loading") {
    return <p className="text-sm text-muted-foreground">{t("previewLoading")}</p>;
  }

  if (phase === "already-exists") {
    return (
      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("alreadyExistsTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("alreadyExistsMessage", { email })}</p>
        <Link href="/login">
          <Button className="w-full">{t("loginLink")}</Button>
        </Link>
      </div>
    );
  }

  return (
    <CreateAccountForm
      token={token}
      email={email}
      organizationName={organizationName}
      roleCode={roleCode}
    />
  );
}

function CreateAccountForm({
  token,
  email,
  organizationName,
  roleCode,
}: {
  token: string;
  email: string;
  organizationName: string;
  roleCode: string;
}) {
  const t = useTranslations("staffInvite");
  const [fullName, setFullName] = useState("");
  const [phone, setPhone] = useState("");
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
    // account_type/staff_invitation_token/full_name/phone : forme exacte
    // attendue par private.handle_new_user() (Module 12n). email vient de
    // l'invitation elle-même (préremplie, non modifiable) -- doit
    // correspondre exactement, sinon le trigger refuse
    // (staff_invitation.accept.email_mismatch).
    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          account_type: "internal",
          staff_invitation_token: token,
          full_name: fullName.trim(),
          phone: phone.trim(),
        },
      },
    });

    setLoading(false);

    if (signUpError) {
      // Même limite empirique que le signup organisation/locataire (Module
      // 12) : le slug DETAIL du trigger n'atteint jamais le client, GoTrue
      // le remplace par un message générique.
      setError(t("genericError"));
      return;
    }

    setSuccess(true);
  }

  if (success) {
    return (
      <div className="flex flex-col gap-2">
        <h2 className="text-lg font-semibold">{t("successTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("successMessage")}</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
      <p className="mb-2 text-sm text-muted-foreground">
        {t("welcomeMessage", { organization: organizationName, role: t(`role${capitalize(roleCode)}`) })}
      </p>
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="email">{t("email")}</Label>
        <Input id="email" type="email" value={email} disabled />
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
        <Label htmlFor="phone">{t("phone")}</Label>
        <Input
          id="phone"
          type="tel"
          required
          value={phone}
          onChange={(event) => setPhone(event.target.value)}
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
        {loading ? t("submitting") : t("submit")}
      </Button>
    </form>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
