"use client";

import { useEffect, useRef, useState, type FormEvent } from "react";
import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { Link } from "@/i18n/navigation";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type Phase = "verifying" | "ready" | "invalid" | "success";

// Le lien reçu par email pointe ici avec un ?code= PKCE dans l'URL (flowType
// forcé à "pkce" par @supabase/ssr, voir createBrowserClient) : supabase-js
// l'échange automatiquement contre une session au montage du client
// (detectSessionInUrl), puis émet PASSWORD_RECOVERY via onAuthStateChange --
// c'est ce signal, pas un appel explicite à exchangeCodeForSession, qui
// détermine quand le formulaire de nouveau mot de passe peut s'afficher.
// Un lien expiré/déjà utilisé redirige ici avec ?error=... au lieu de
// ?code=... -- détecté immédiatement, sans attendre un événement qui ne
// viendra jamais. Un timeout couvre le reste (code présent mais échange qui
// échoue silencieusement, lien malformé).
const VERIFICATION_TIMEOUT_MS = 8000;

export function ResetPasswordForm() {
  const t = useTranslations("auth");
  const searchParams = useSearchParams();
  // Lazy initializer plutôt qu'un setState dans l'effet ci-dessous : un lien
  // expiré/déjà utilisé redirige ici avec ?error=... au lieu de ?code=..., et
  // ce cas se décide entièrement depuis l'URL de rendu initial, pas depuis un
  // événement externe à synchroniser après coup.
  const [phase, setPhase] = useState<Phase>(() =>
    searchParams.get("error") ? "invalid" : "verifying"
  );
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    if (searchParams.get("error")) {
      return;
    }

    const supabase = createClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event) => {
      if (event === "PASSWORD_RECOVERY") {
        if (timeoutRef.current) clearTimeout(timeoutRef.current);
        setPhase("ready");
      }
    });

    timeoutRef.current = setTimeout(() => {
      setPhase((current) => (current === "verifying" ? "invalid" : current));
    }, VERIFICATION_TIMEOUT_MS);

    return () => {
      subscription.unsubscribe();
      if (timeoutRef.current) clearTimeout(timeoutRef.current);
    };
  }, [searchParams]);

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
    const { error: updateError } = await supabase.auth.updateUser({ password });

    if (updateError) {
      setLoading(false);
      setError(t("resetPasswordGenericError"));
      return;
    }

    // Nouvelle connexion propre plutôt que de laisser la session de
    // récupération (créée par le lien, portée limitée) se substituer à une
    // vraie connexion -- cohérent avec le principe déjà appliqué ailleurs
    // dans ce module (pas de redirection aveugle après une action sensible).
    await supabase.auth.signOut();
    setLoading(false);
    setPhase("success");
  }

  if (phase === "verifying") {
    return <p className="text-sm text-muted-foreground">{t("resetPasswordVerifying")}</p>;
  }

  if (phase === "invalid") {
    return (
      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("resetPasswordInvalidTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("resetPasswordInvalidMessage")}</p>
        <Link href="/forgot-password">
          <Button className="w-full">{t("forgotPasswordLink")}</Button>
        </Link>
      </div>
    );
  }

  if (phase === "success") {
    return (
      <div className="flex flex-col gap-3">
        <h2 className="text-lg font-semibold">{t("resetPasswordSuccessTitle")}</h2>
        <p className="text-sm text-muted-foreground">{t("resetPasswordSuccessMessage")}</p>
        <Link href="/login">
          <Button className="w-full">{t("backToLogin")}</Button>
        </Link>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="flex flex-col gap-4">
      <div className="flex flex-col gap-1.5">
        <Label htmlFor="password">{t("resetPasswordNewLabel")}</Label>
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
        {loading ? t("resetPasswordSubmitting") : t("resetPasswordSubmit")}
      </Button>
    </form>
  );
}
