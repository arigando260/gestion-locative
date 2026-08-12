import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

// address/phone/email : colonnes du Module 9, absentes de database.types.ts
// tant que `supabase gen types` n'a pas été rejoué — même remarque que
// data/maintenance.ts. Étend le type généré plutôt que de le réécrire en
// entier, le reste de la table étant déjà correctement typé.
export type Organization = Tables<"organizations"> & {
  address: string | null;
  phone: string | null;
  email: string | null;
};

export async function getOrganization(id: string): Promise<Organization | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("organizations")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data as Organization | null;
}

export type UpdateOrganizationInput = {
  name: string;
  address: string | null;
  phone: string | null;
  email: string | null;
};

// Écriture : {data, error} renvoyé tel quel, jamais throw — la Server Action
// appelante décide comment le traduire (lib/errors.ts), même convention que
// data/properties.ts createProperty.
export async function updateOrganization(id: string, input: UpdateOrganizationInput) {
  const supabase = await createClient();
  return supabase.from("organizations").update(input).eq("id", id).select().single();
}
