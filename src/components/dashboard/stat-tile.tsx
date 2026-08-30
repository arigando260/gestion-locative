import { Card } from "@/components/ui/card";
import { cn } from "@/lib/utils";

export function StatTile({
  label,
  value,
  meta,
  progress,
  valueClassName,
}: {
  label: string;
  value: string;
  meta?: string;
  progress?: number;
  valueClassName?: string;
}) {
  return (
    <Card className="gap-2 px-[18px] py-4">
      <div className="text-[11.5px] font-semibold tracking-[0.06em] text-muted-foreground uppercase">
        {label}
      </div>
      <div className={cn("text-[26px] leading-tight font-bold tracking-tight tabular-nums", valueClassName)}>
        {value}
      </div>
      {progress !== undefined ? (
        <div className="h-[5px] w-full rounded-full bg-[#f0f0f2]">
          <div
            className="h-full rounded-full bg-status-success-fg"
            style={{ width: `${Math.min(Math.max(progress, 0), 100)}%` }}
          />
        </div>
      ) : meta ? (
        <div className="text-[12.5px] text-muted-foreground">{meta}</div>
      ) : null}
    </Card>
  );
}
