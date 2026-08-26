"use client";

import { useActionState, useState } from "react";
import { useTranslations, useLocale } from "next-intl";
import { inviteStaffAction } from "@/actions/staff-invitations";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Button } from "@/components/ui/button";
import { SelectField } from "@/components/forms/select-field";
import { SubmitButton } from "@/components/forms/submit-button";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";

const ROLE_OPTIONS = ["admin", "agent", "comptable"] as const;

export function InviteStaffForm() {
  const t = useTranslations("team");
  const locale = useLocale();
  const [state, formAction] = useActionState(inviteStaffAction, null);
  const [copied, setCopied] = useState(false);

  async function handleCopy(url: string) {
    await navigator.clipboard.writeText(url);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{t("inviteTitle")}</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <form action={formAction} className="flex flex-col gap-4">
          <input type="hidden" name="locale" value={locale} />
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="staff-invite-email">{t("inviteEmail")}</Label>
            <Input id="staff-invite-email" name="email" type="email" required />
          </div>
          <SelectField
            name="role_code"
            label={t("inviteRole")}
            defaultValue="agent"
            options={ROLE_OPTIONS.map((code) => ({ value: code, label: t(`role${capitalize(code)}`) }))}
          />
          {state && !state.success ? (
            <p className="text-sm text-destructive" role="alert">
              {state.message}
            </p>
          ) : null}
          <SubmitButton pendingText={t("inviteSubmitting")}>
            {t("inviteSubmit")}
          </SubmitButton>
        </form>
        {state && state.success ? (
          <div className="flex flex-col gap-2 rounded-md border border-border p-3">
            <p className="text-sm">{t("inviteSuccess")}</p>
            <Label htmlFor="staff-invite-link">{t("linkLabel")}</Label>
            <div className="flex gap-2">
              <Input id="staff-invite-link" readOnly value={state.inviteUrl} />
              <Button
                type="button"
                variant="outline"
                onClick={() => handleCopy(state.inviteUrl)}
              >
                {copied ? t("linkCopied") : t("copyLink")}
              </Button>
            </div>
            <p className="text-xs text-muted-foreground">{t("linkHint")}</p>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}
