import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

// Mis en cache par requête (React cache()) : plusieurs composants imbriqués
// peuvent l'appeler sans déclencher plusieurs allers-retours.
export const getCurrentProfile = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("id, organization_id, email, full_name")
    .eq("id", user.id)
    .single();

  return profile;
});

// Même embed que property-agent-assignments.ts/staff-invitations.ts (listage
// d'AUTRES membres du staff) -- ici pour l'utilisateur courant, absent de
// getCurrentProfile() jusqu'ici car aucun écran n'en avait besoin avant
// l'accueil agent. user_roles est many-to-many en schéma mais un compte n'a
// en pratique jamais qu'un seul rôle (même hypothèse que le reste du code).
export const getCurrentStaffRole = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase
    .from("profiles")
    .select("user_roles(roles(code))")
    .eq("id", user.id)
    .maybeSingle();

  const userRoles = data?.user_roles as unknown as
    | { roles: { code: string } | null }[]
    | null;
  return userRoles?.[0]?.roles?.code ?? null;
});

// Un même auth.users est soit dans profiles, soit dans tenant_accounts,
// jamais les deux (trigger d'exclusivité, Module 1) — sert à déterminer
// quel portail afficher (voir (dashboard)/layout.tsx et tenant/layout.tsx).
export const getCurrentTenant = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: tenant } = await supabase
    .from("tenant_accounts")
    .select("id, email, full_name")
    .eq("id", user.id)
    .single();

  return tenant;
});
