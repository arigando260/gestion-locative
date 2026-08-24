import "server-only";
import { createClient } from "@/lib/supabase/server";

// Type écrit à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 12a (countries absente du fichier généré). À remplacer
// par Tables<"countries"> dès que `supabase gen types` est rejoué.
export type Country = {
  code: string;
  name: string;
};

// Catalogue public (Module 12a) : lue depuis /signup, avant toute session —
// nécessite que la policy RLS countries_select couvre le rôle anon, pas
// seulement authenticated (voir suivi de migration signalé séparément).
export async function getCountries(): Promise<Country[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("countries")
    .select("code, name")
    .eq("is_active", true)
    .order("sort_order");

  if (error) throw error;
  return data as Country[];
}
