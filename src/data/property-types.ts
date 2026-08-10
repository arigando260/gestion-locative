import "server-only";
import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import type { PropertyType } from "@/lib/property-type-labels";

export type { PropertyType };

// location_type est validé par trigger contre property_types.code, pas par
// une foreign key déclarée (voir Module 2) : PostgREST ne peut donc pas
// faire d'embedding relationnel automatique. On charge la liste une fois
// (mise en cache par requête) et on résout le libellé manuellement.
export const getPropertyTypes = cache(async (): Promise<PropertyType[]> => {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("property_types")
    .select("id, code, name, organization_id")
    .order("name");

  if (error) throw error;
  return data;
});
