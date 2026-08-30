"use client";

import { useActionState } from "react";
import { useTranslations } from "next-intl";
import { updateOrganizationAction } from "@/actions/organizations";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { SubmitButton } from "@/components/forms/submit-button";
import { FormMessage } from "@/components/forms/form-message";
import { Card, CardContent } from "@/components/ui/card";
import type { Organization } from "@/data/organizations";

export function OrganizationForm({ organization }: { organization: Organization }) {
  const t = useTranslations("settings");
  const tc = useTranslations("common");
  const [state, formAction] = useActionState(updateOrganizationAction, null);

  return (
    <Card className="max-w-md">
      <CardContent>
        <form action={formAction} className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="name">{t("name")}</Label>
            <Input id="name" name="name" defaultValue={organization.name} required />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="address">{t("address")}</Label>
            <Input id="address" name="address" defaultValue={organization.address ?? ""} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="phone">{t("phone")}</Label>
            <Input id="phone" name="phone" defaultValue={organization.phone ?? ""} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="email">{t("email")}</Label>
            <Input id="email" name="email" type="email" defaultValue={organization.email ?? ""} />
          </div>
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="special_terms">{t("specialTermsLabel")}</Label>
            <Textarea
              id="special_terms"
              name="special_terms"
              rows={4}
              defaultValue={organization.special_terms ?? ""}
            />
            <p className="text-sm text-muted-foreground">{t("specialTermsHint")}</p>
          </div>
          <Label htmlFor="tenant_capture_enabled" className="flex items-center gap-2 font-normal">
            <input
              type="checkbox"
              id="tenant_capture_enabled"
              name="tenant_capture_enabled"
              value="true"
              defaultChecked={organization.tenant_capture_enabled}
              className="size-4"
            />
            <span>{t("tenantCaptureLabel")}</span>
          </Label>
          <p className="text-sm text-muted-foreground">{t("tenantCaptureHint")}</p>
          <FormMessage state={state} />
          <SubmitButton pendingText={tc("loading")}>{tc("save")}</SubmitButton>
        </form>
      </CardContent>
    </Card>
  );
}
