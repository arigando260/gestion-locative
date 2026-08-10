import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

export type PermissionSet = Set<string>;

// Lit la vue public.my_permissions (une seule définition de la requête côté
// base, voir ARCHITECTURE.md) plutôt que de reconstruire la jointure
// user_roles/role_permissions côté TypeScript. Vide pour un compte tenant.
export const getCurrentUserPermissions = cache(
  async (): Promise<PermissionSet> => {
    const supabase = await createClient();
    const { data, error } = await supabase
      .from("my_permissions")
      .select("resource, action");

    if (error || !data) return new Set();
    return new Set(data.map((p) => `${p.resource}:${p.action}`));
  }
);

// Aide à l'ergonomie de l'affichage UNIQUEMENT. RLS reste la seule frontière
// de sécurité réelle : masquer un bouton n'a jamais valeur d'autorisation.
export function can(
  permissions: PermissionSet,
  resource: string,
  action: string
) {
  return permissions.has(`${resource}:${action}`);
}
