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
