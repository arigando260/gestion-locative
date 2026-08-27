import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

// database.types.ts régénéré depuis le Module 13 (buildings) : plus besoin
// du Omit + extension manuelle utilisé jusqu'ici (address_complement/
// country_code/city/neighborhood/building_id sont désormais tous
// correctement inférés depuis le fichier généré).
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

// Écrit à la main plutôt que dérivé de TablesInsert<"properties"> :
// country_code/city/neighborhood obligatoires quand building_id est absent
// (décision Module 12c -- l'écran de création les exige, même si la colonne
// reste nullable en base) ; nuls quand building_id est fourni (Module 13 --
// properties_building_address_exclusive, forcé de toute façon côté serveur
// par create_property(), mais reflété ici pour que l'appelant n'ait pas à
// deviner). address_complement reste toujours optionnel dans les deux cas.
export type CreatePropertyInput = {
  organization_id: string;
  name: string;
  country_code: string | null;
  city: string | null;
  neighborhood: string | null;
  address_complement: string | null;
  price: number;
  location_type: string;
  building_id: string | null;
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
      p_building_id: input.building_id,
    })
    .single();
  return { data: result.data as Property, error: result.error };
}

// Attache un bien existant à un immeuble : update ciblé (building_id +
// adresse propre vidée), pas un formulaire d'édition générique. La vraie
// garantie reste properties_update (has_permission('properties','update')
// AND agent_property_scope) et le CHECK properties_building_address_exclusive
// côté base (Module 13) -- vidés ici pour ne pas dépendre d'un aller-retour
// en erreur si l'appelant oubliait de le faire.
export async function attachPropertyToBuilding(propertyId: string, buildingId: string) {
  const supabase = await createClient();
  return supabase
    .from("properties")
    .update({ building_id: buildingId, country_code: null, city: null, neighborhood: null })
    .eq("id", propertyId)
    .select()
    .single();
}

export type ResolvedPropertyAddress = {
  formatted_address: string | null;
  country_code: string | null;
  city: string | null;
  neighborhood: string | null;
  address_complement: string | null;
  unit_complement: string | null;
  building_id: string | null;
  building_name: string | null;
};

// public.resolve_property_address() (Module 13b, wrapper SECURITY INVOKER
// de private.resolve_property_address, Module 13) : adresse effective d'un
// bien (propre, ou héritée de son immeuble + identifiant d'unité). Ne throw
// jamais : un bien introuvable ou invisible pour l'appelant renvoie
// simplement un jeu de résultats vide (comportement du wrapper), traduit
// ici en valeurs null plutôt qu'en erreur.
export async function resolvePropertyAddress(propertyId: string): Promise<ResolvedPropertyAddress> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .rpc("resolve_property_address", { p_property_id: propertyId })
    .maybeSingle();

  if (error) throw error;
  return (
    (data as ResolvedPropertyAddress | null) ?? {
      formatted_address: null,
      country_code: null,
      city: null,
      neighborhood: null,
      address_complement: null,
      unit_complement: null,
      building_id: null,
      building_name: null,
    }
  );
}

// Pour une liste (écran /properties) : un appel RPC par bien via
// Promise.all plutôt qu'une vue dédiée -- acceptable à l'échelle dev
// actuelle (quelques dizaines de biens), mais un N+1 réel si le volume
// grandit. À revisiter (vue SQL type properties_effective_status) si ça
// devient sensible, hors périmètre ici.
export async function resolvePropertyAddresses(
  propertyIds: string[]
): Promise<Record<string, ResolvedPropertyAddress>> {
  const resolved = await Promise.all(propertyIds.map((id) => resolvePropertyAddress(id)));
  return Object.fromEntries(propertyIds.map((id, index) => [id, resolved[index]]));
}
