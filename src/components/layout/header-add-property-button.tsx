"use client";

import { Plus } from "lucide-react";
import { Link, usePathname } from "@/i18n/navigation";
import { Button } from "@/components/ui/button";

// CTA "Ajouter un logement" du header (Espace Agence uniquement, voir
// layout.tsx -- gating par rôle/organisation et par permission déjà fait
// côté serveur avant de rendre ce composant). Visible seulement sur
// /dashboard : /properties a déjà son propre bouton "Ajouter un logement"
// (properties/page.tsx, sans icône -- fidèle à la maquette, qui ne montre
// le "+" que dans l'en-tête), l'afficher aussi ici le dupliquerait. Même
// patron que Sidebar (usePathname côté client pour réagir à la navigation
// sans re-render du layout) plutôt qu'un nouveau mécanisme page -> layout.
const VISIBLE_ON_PATHS = ["/dashboard"];

export function HeaderAddPropertyButton({ label }: { label: string }) {
  const pathname = usePathname();
  if (!VISIBLE_ON_PATHS.includes(pathname)) return null;

  return (
    <Button size="sm" render={<Link href="/properties/new" />} nativeButton={false}>
      <Plus />
      {label}
    </Button>
  );
}
