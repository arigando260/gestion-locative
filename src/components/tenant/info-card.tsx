import { Link } from "@/i18n/navigation";
import { Card } from "@/components/ui/card";

export function InfoCard({
  label,
  value,
  meta,
  href,
}: {
  label: string;
  value: string;
  meta?: string;
  href?: string;
}) {
  const content = (
    <Card className="gap-1 px-[18px] py-4">
      <div className="text-[11.5px] font-semibold tracking-[0.06em] text-muted-foreground uppercase">
        {label}
      </div>
      <div className="text-[15px] font-bold">{value}</div>
      {meta ? <div className="text-[12px] text-muted-foreground">{meta}</div> : null}
    </Card>
  );

  if (!href) return content;
  return (
    <Link href={href} className="block">
      {content}
    </Link>
  );
}
