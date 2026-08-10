"use client";

import { useLocale } from "next-intl";
import { usePathname, useRouter } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

const LABELS: Record<string, string> = { fr: "Français", en: "English" };

export function LocaleSwitcher() {
  const locale = useLocale();
  const pathname = usePathname();
  const router = useRouter();

  return (
    <Select
      value={locale}
      onValueChange={(next) => {
        if (next) router.replace(pathname, { locale: next });
      }}
    >
      <SelectTrigger size="sm" className="w-28">
        <SelectValue>{(val: string) => LABELS[val] ?? val}</SelectValue>
      </SelectTrigger>
      <SelectContent>
        {routing.locales.map((l) => (
          <SelectItem key={l} value={l}>
            {LABELS[l]}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}
