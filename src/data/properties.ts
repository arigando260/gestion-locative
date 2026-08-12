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

// Type écrit à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 2c (vue properties_effective_status absente) — même
// remarque que data/maintenance.ts et data/lease-terminations.ts. Surensemble
// de Property (la vue expose p.* + effective_status), donc substituable
// partout où Property l'est.
export type PropertyWithEffectiveStatus = Property & { effective_status: PropertyStatus };

// Lit toujours le statut EFFECTIF (calculé à la volée), jamais la colonne
// brute properties.status qui ne porte plus que la décision manuelle
// (disponible/en_travaux) — voir ARCHITECTURE.md. Réservé aux deux écrans
// qui affichent réellement le statut ; getProperties()/getProperty()
// ci-dessus restent la lecture par défaut pour tout le reste (formulaires de
// sélection, contexte d'un bail/ticket...), qui n'a jamais besoin de cette
// colonne.
export async function getPropertiesWithEffectiveStatus(): Promise<
  PropertyWithEffectiveStatus[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties_effective_status")
    .select("*")
    .order("created_at", { ascending: false })
    .returns<PropertyWithEffectiveStatus[]>();

  if (error) throw error;
  return data;
}

export async function getPropertyWithEffectiveStatus(
  id: string
): Promise<PropertyWithEffectiveStatus | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("properties_effective_status")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data as PropertyWithEffectiveStatus | null;
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
