import { cn } from "@/lib/utils";

function getInitials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

const sizeClasses = {
  sm: "size-[26px] rounded-[7px] text-[11px]",
  md: "size-8 rounded-[9px] text-xs",
  lg: "size-9 rounded-[10px] text-sm",
};

const toneClasses = {
  person: "bg-[#f1efec] text-[#57534e]",
  system: "bg-[#f4f4f5] text-[#52525b]",
};

export function AvatarInitials({
  name,
  size = "md",
  tone = "person",
  className,
}: {
  name: string;
  size?: keyof typeof sizeClasses;
  tone?: keyof typeof toneClasses;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex shrink-0 items-center justify-center font-semibold",
        sizeClasses[size],
        toneClasses[tone],
        className
      )}
    >
      {getInitials(name)}
    </span>
  );
}
