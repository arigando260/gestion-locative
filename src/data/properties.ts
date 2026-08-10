import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables, TablesInsert } from "@/lib/supabase/database.types";

export type Property = Tables<"properties">;
export type PropertyStatus = "disponible" | "occupe" | "en_travaux";

// Lecture : erreur inattendue => on laisse remonter (error.tsx), ce n'est
// jamais un cas "attendu" côté utilisateur ici, contrairement aux écritures.
export async function getProperties(): Promise<Property[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) throw error;
  return data;
}

export async function getProperty(id: string): Promise<Property | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export type CreatePropertyInput = Pick<
  TablesInsert<"properties">,
  "organization_id" | "name" | "address" | "price" | "location_type"
>;

// Écriture : {data, error} renvoyé tel quel, jamais throw — c'est le Server
// Action appelant qui décide comment le traduire (lib/errors.ts) et le
// renvoyer à useActionState.
export async function createProperty(input: CreatePropertyInput) {
  const supabase = await createClient();
  return supabase.from("properties").insert(input).select().single();
}
