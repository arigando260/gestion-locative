"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { Link } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/client";
import { acceptTenantInvitationForExistingAccountAction } from "@/actions/tenant-invitations";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Phase =
  | "loading"
  | "create"
  | "existing-need-login"
  | "existing-logged-in"
  | "existing-joined";

// 3 branches (+ chargement initial) selon ce que révèle
// check_tenant_invitation_existing_account (Module 12g), croisé avec la
// session en cours : pas de compte -> formulaire de création habituel ;
// compte déjà existant mais pas connecté (ou connecté avec un autre
// email) -> renvoi vers /login ; compte déjà existant et déjà connecté
// avec le bon email -> rattachement direct, sans jamais passer par
// signUp() (Module 12h).
export function InviteAcceptForm({
  token,
  email,
  organizationName,
}: {
  token: string;
  email: string;
  organizationName: string;
}) {
  const t = useTranslations("invite");
  const [phase, setPhase] = useState<Phase>("loading");

  useEffect(() => {
    let cancelled = false;

    async function detect() {
      const supabase = createClient();
      const [{ data: userData }, { data: existsData }] = await Promise.all([
        supabase.auth.getUser(),
        supabase.rpc("check_tenant_invitation_existing_account", {
          p_token: token,
        }),
      ]);

      if (cancelled) return;

      if (!existsData) {
        setPhase("create");
        return;
      }

      const currentEmail = userData.user?.email?.toLowerCase();
      if (currentEmail && currentEmail === email.toLowerCase()) {
        setPhase("existing-logged-in");
      } else {
        setPhase("existing-need-login");
      }
    }

    detect();
    return () => {
      cancelled = true;
    };
  }, [token, email]);

  if (phase === "loading") {
    return <p className="text-sm text-muted-foreground">{t("previewLoading")}</p>;
  }

  if (phase === "existing-need-login") {
    return (
      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("existingAccountTitle")}</h2>
        <p className="text-sm text-muted-foreground">
          {t("existingAccountMessage", { email, organization: organizationName })}
        </p>
        <Link href={`/login?inviteToken=${encodeURIComponent(token)}`}>
          <Button className="w-full">{t("loginLink")}</Button>
        </Link>
      </div>
    );
  }

  if (phase === "existing-logged-in" || phase === "existing-joined") {
    return (
      <JoinExistingOrganization
        token={token}
        organizationName={organizationName}
        joined={phase === "existing-joined"}
        onJoined={() => setPhase("existing-joined")}
      />
    );
  }

  return <CreateAccountForm token={token} email={email} />;
}

function JoinExistingOrganization({
  token,
  organizationName,
  joined,
  onJoined,
}: {
  token: string;
  organizationName: string;
  joined: boolean;
  onJoined: () => void;
}) {
  const t = useTranslations("invite");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleJoin() {
    setLoading(true);
    setError(null);
    const result = await acceptTenantInvitationForExistingAccountAction(token);
    setLoading(false);
    if (!result.success) {
      setError(result.message);
      return;
    }
    onJoined();
  }

  if (joined) {
    return (
      <div className="flex flex-col gap-2">
        <h2 className="text-lg font-semibold">{t("joinTitle", { organization: organizationName })}</h2>
        <p className="text-sm text-muted-foreground">{t("successMessage")}</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">{t("joinTitle", { organization: organizationName })}</h2>
      <p className="text-sm text-muted-foreground">{t("joinMessage")}</p>
      {error ? (
        <p className="text-sm text-destructive" role="alert">
          {error}
        </p>
      ) : null}
      <Button onClick={handleJoin} disabled={loading} className="w-full">
        {loading ? t("joinSubmitting") : t("joinSubmit")}
      </Button>
    </div>
  );
}

function CreateAccountForm({ token, email }: { token: string; email: string }) {
  const t = useTranslations("invite");
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
    // account_type/invitation_token/full_name/phone : forme exacte attendue
    // par private.handle_new_user() (Module 12e). email vient de
    // l'invitation elle-même (préremplie, non modifiable) -- doit
    // correspondre exactement, sinon le trigger refuse
    // (tenant_invitation.accept.email_mismatch). .trim() sur les champs
    // texte : même raison que signup-form.tsx, éviter des espaces
    // parasites stockés tels quels en base.
    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          account_type: "tenant",
          invitation_token: token,
          full_name: fullName.trim(),
          phone: phone.trim(),
        },
      },
    });

    setLoading(false);

    if (signUpError) {
      // Même limite empirique que le signup organisation : le slug DETAIL
      // du trigger (jeton invalide/expiré, email non correspondant...)
      // n'atteint jamais le client, GoTrue le remplace par un message
      // générique. Message générique traduit ici plutôt qu'une tentative
      // illusoire de le distinguer.
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
      <p className="text-center text-sm text-muted-foreground">
        {t("alreadyHaveAccount")}{" "}
        <Link href={`/login?inviteToken=${encodeURIComponent(token)}`} className="underline">
          {t("loginLink")}
        </Link>
      </p>
    </form>
  );
}
