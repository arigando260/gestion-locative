import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

// address (Module 12c, renommée address_complement) + country_code/city/
// neighborhood (Module 12c, nouvelles colonnes) : database.types.ts n'a pas
// encore été régénéré, le type généré porte encore l'ancien nom "address"
// et ignore les 3 nouvelles colonnes. Omit + extension plutôt qu'une
// réécriture complète, même patron que data/organizations.ts.
export type Property = Omit<Tables<"properties">, "address"> & {
  address_complement: string | null;
  country_code: string | null;
  city: string | null;
  neighborhood: string | null;
};
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

// Écrit à la main plutôt que dérivé de TablesInsert<"properties"> (même
// raison que Property ci-dessus) : country_code/city/neighborhood
// obligatoires ici (décision Module 12c -- l'écran de création les exige,
// même si la colonne reste nullable en base pour les 29 biens dev déjà
// existants) ; address_complement reste le seul champ optionnel.
export type CreatePropertyInput = {
  organization_id: string;
  name: string;
  country_code: string;
  city: string;
  neighborhood: string;
  address_complement: string | null;
  price: number;
  location_type: string;
};

// Écriture : {data, error} renvoyé tel quel, jamais throw — c'est le Server
// Action appelant qui décide comment le traduire (lib/errors.ts) et le
// renvoyer à useActionState.
//
// RPC plutôt qu'un INSERT direct (Module 12q) : un simple
// `insert(...).select().single()` échoue pour un agent — vérifié
// empiriquement sur dev — car Postgres filtre la clause RETURNING avec la
// policy SELECT de la table, et un bien fraîchement créé n'a par
// construction aucune ligne property_agent_assignments au moment où
// RETURNING est évalué (agent_property_scope() y échoue donc). La fonction
// public.create_property() pose l'assignation de l'agent créateur AVANT de
// faire son propre `returning * into`, dans la même transaction — le
// contrat {data, error} et CreatePropertyInput restent inchangés, seul le
// mécanisme d'écriture change.
export async function createProperty(input: CreatePropertyInput) {
  const supabase = await createClient();
  // Cast nécessaire même après régénération de database.types.ts (Module
  // 12r) : le vrai fichier généré décrit désormais correctement create_property
  // (Args + Returns + SetofOptions.isOneToOne, vérifié), mais
  // lib/supabase/server.ts appelle createServerClient(...) SANS lui passer
  // <Database> en paramètre générique -- le client renvoyé par createClient()
  // n'est donc typé contre AUCUN schéma, ici comme pour tout appel .from()/
  // .rpc() ailleurs dans ce projet (server.ts, client.ts et admin.ts sont
  // tous les trois dans ce cas). Le typage de Property/Tables<"properties">
  // utilisé partout ailleurs dans ce fichier tient uniquement aux annotations
  // de retour explicites (Promise<Property[]> etc.), jamais d'une inférence
  // réelle depuis le client -- ce n'est donc pas un problème spécifique aux
  // RPC ni à cette fonction, mais une lacune plus large, hors périmètre ici.
  const result = await supabase
    .rpc("create_property", {
      p_organization_id: input.organization_id,
      p_name: input.name,
      p_country_code: input.country_code,
      p_city: input.city,
      p_neighborhood: input.neighborhood,
      p_address_complement: input.address_complement,
      p_price: input.price,
      p_location_type: input.location_type,
    })
    .single();
  return { data: result.data as Property, error: result.error };
}
