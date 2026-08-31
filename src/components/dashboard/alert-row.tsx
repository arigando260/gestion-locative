import { Link } from "@/i18n/navigation";
import { AvatarInitials } from "@/components/ui/avatar-initials";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

export function AlertRow({
  name,
  subtitle,
  meta,
  metaCaption,
  badgeLabel,
  badgeVariant = "neutral",
  actionLabel,
  actionHref,
}: {
  name: string;
  subtitle: string;
  meta?: string;
  metaCaption?: string;
  badgeLabel: string;
  badgeVariant?: "success" | "warning" | "danger" | "neutral";
  actionLabel: string;
  actionHref: string;
}) {
  return (
    <div className="flex items-center gap-3 border-t border-[#f2f2f4] px-[22px] py-[15px] first:border-t-0 hover:bg-[#fafafa]">
      <AvatarInitials name={name} tone="system" />
      <div className="min-w-0 flex-1">
        <div className="truncate text-[13.5px] font-semibold tracking-[-0.01em]">{name}</div>
        <div className="truncate text-[12.5px] text-muted-foreground">{subtitle}</div>
      </div>
      {meta ? (
        <div className="hidden text-right sm:block">
          <div className="text-[13.5px] font-semibold tabular-nums">{meta}</div>
          {metaCaption ? (
            <div className="text-[12px] text-muted-foreground">{metaCaption}</div>
          ) : null}
        </div>
      ) : null}
      <Badge
        variant={
          badgeVariant === "neutral"
            ? "secondary"
            : badgeVariant === "success"
              ? "success"
              : badgeVariant === "warning"
                ? "warning"
                : "danger"
        }
      >
        {badgeLabel}
      </Badge>
      <Button
        variant="outline"
        size="sm"
        // tel:/mailto: (ex. "Relancer" -> appel direct) doivent passer par
        // une ancre native -- le Link i18n préfixerait la locale devant le
        // schéma et casserait l'URL (/fr/tel:...).
        render={
          /^[a-z]+:/.test(actionHref) ? <a href={actionHref} /> : <Link href={actionHref} />
        }
        nativeButton={false}
      >
        {actionLabel}
      </Button>
    </div>
  );
}
