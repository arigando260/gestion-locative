import { cn } from "@/lib/utils";

export function FormMessage({
  state,
}: {
  state: { success: boolean; message?: string } | null;
}) {
  if (!state?.message) return null;

  return (
    <p
      role="alert"
      className={cn(
        "text-sm",
        state.success ? "text-foreground" : "text-destructive"
      )}
    >
      {state.message}
    </p>
  );
}
