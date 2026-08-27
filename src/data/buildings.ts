import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables } from "@/lib/supabase/database.types";

export type Building = Tables<"buildings">;
export type BuildingWithUnitsCount = Building & { units_count: number };

// Une seule FK entre properties et buildings (properties_building_org_fk,
// Module 13) : l'embed properties(count) n'est jamais ambigu pour
// PostgREST, contrairement à property_agent_assignments -> profiles
// (deux FK, désambiguïsation par nom de contrainte nécessaire là-bas).
export async function listBuildings(organizationId: string): Promise<BuildingWithUnitsCount[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("buildings")
    .select("*, properties(count)")
    .eq("organization_id", organizationId)
    .order("name");

  if (error) throw error;
  return (data ?? []).map((row) => {
    const { properties, ...building } = row as Building & {
      properties: { count: number }[];
    };
    return { ...building, units_count: properties?.[0]?.count ?? 0 };
  });
}

// Fiche immeuble (module facturation groupée) : lecture d'un seul immeuble,
// même patron que getProperty. RLS buildings_select fait autorité — un
// immeuble hors organisation ou hors permission renvoie simplement null,
// jamais une erreur.
export async function getBuilding(id: string): Promise<Building | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("buildings")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export type CreateBuildingInput = {
  organization_id: string;
  name: string;
  country_code: string;
  city: string;
  neighborhood: string;
  address_complement: string | null;
  floors_count: number | null;
};

// Écriture : {data, error} renvoyé tel quel, jamais throw — même convention
// que createProperty (l'appelant décide comment le traduire). Pas de RPC ici
// contrairement à create_property() : buildings_insert n'a pas
// l'équivalent du piège RETURNING/agent_property_scope (aucune
// auto-assignation posée à la création d'un immeuble), un insert direct
// suffit.
export async function createBuilding(input: CreateBuildingInput) {
  const supabase = await createClient();
  return supabase.from("buildings").insert(input).select().single();
}
