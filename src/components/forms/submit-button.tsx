"use client";

import { useFormStatus } from "react-dom";
import { Button } from "@/components/ui/button";
import type { ComponentProps } from "react";

// useFormStatus fonctionne dans tout composant enfant d'un <form>, sans lien
// direct avec useActionState — pas besoin de prop-driller l'état "pending".
export function SubmitButton({
  children,
  pendingText,
  disabled,
  ...props
}: ComponentProps<typeof Button> & { pendingText: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending || disabled} {...props}>
      {pending ? pendingText : children}
    </Button>
  );
}
