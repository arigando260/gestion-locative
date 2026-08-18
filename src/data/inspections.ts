import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables, TablesInsert } from "@/lib/supabase/database.types";

export type InspectionWithEffectiveStatus =
  Tables<"property_inspections_effective_status">;
export type InspectionItem = Tables<"inspection_items">;
export type InspectionPhoto = Tables<"inspection_photos">;
export type InspectionItemWithPhotos = InspectionItem & {
  inspection_photos: InspectionPhoto[];
};

// Toujours le statut EFFECTIF (inclut l'acceptation tacite à 7 jours),
// jamais tenant_validation_status brut seul — même principe que les
// échéances, voir ARCHITECTURE.md.
export async function getInspectionsForLease(
  leaseId: string
): Promise<InspectionWithEffectiveStatus[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("property_inspections_effective_status")
    .select("*")
    .eq("lease_id", leaseId)
    .order("inspection_date", { ascending: false });

  if (error) throw error;
  return data;
}

// Un brouillon existant (du même type si précisé, sinon tout type) doit
// être complété/finalisé, pas dupliqué : le trigger anti-doublon
// (private.validate_property_inspection_not_duplicate, Module 6f)
// refuserait de toute façon un second brouillon non contesté du même type.
// Sert à rediriger /leases/{id}/inspections/new avant même d'afficher un
// formulaire voué à échouer à la soumission — voir app/[locale]/(dashboard)/
// leases/[leaseId]/inspections/new/page.tsx.
export async function getDraftInspectionForLease(
  leaseId: string,
  inspectionType?: "entree" | "sortie"
): Promise<InspectionWithEffectiveStatus | null> {
  const supabase = await createClient();
  let query = supabase
    .from("property_inspections_effective_status")
    .select("*")
    .eq("lease_id", leaseId)
    .eq("document_status", "brouillon");

  if (inspectionType) {
    query = query.eq("inspection_type", inspectionType);
  }

  const { data, error } = await query
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  return data;
}

export async function getInspection(
  id: string
): Promise<InspectionWithEffectiveStatus | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("property_inspections_effective_status")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// Bucket privé (Module 6) : jamais d'URL publique, une URL signée à durée
// limitée est nécessaire pour afficher chaque photo.
export async function getSignedPhotoUrls(
  storagePaths: string[]
): Promise<Record<string, string>> {
  if (storagePaths.length === 0) return {};

  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from("inspection-photos")
    .createSignedUrls(storagePaths, 3600);

  if (error) throw error;

  const result: Record<string, string> = {};
  for (const item of data) {
    if (item.signedUrl && item.path) result[item.path] = item.signedUrl;
  }
  return result;
}

export async function getInspectionItemsWithPhotos(
  inspectionId: string
): Promise<InspectionItemWithPhotos[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inspection_items")
    .select("*, inspection_photos(*)")
    .eq("inspection_id", inspectionId)
    .order("created_at")
    .returns<InspectionItemWithPhotos[]>();

  if (error) throw error;
  return data;
}

export type CreateInspectionInput = Pick<
  TablesInsert<"property_inspections">,
  "organization_id" | "lease_id" | "inspection_type" | "inspection_date" | "conducted_by"
>;

export async function createInspection(input: CreateInspectionInput) {
  const supabase = await createClient();
  return supabase
    .from("property_inspections")
    .insert(input)
    .select()
    .single();
}

// Seul point d'écriture d'observations (Module 6g) — voir
// updateInspectionObservationsAction. La colonne reste NULL depuis
// createInspection ; remplie ensuite depuis la page de détail du
// brouillon, jamais à la création.
export async function updateInspectionObservations(id: string, observations: string | null) {
  const supabase = await createClient();
  return supabase
    .from("property_inspections")
    .update({ observations })
    .eq("id", id)
    .select()
    .single();
}

export type AddInspectionItemInput = Pick<
  TablesInsert<"inspection_items">,
  "organization_id" | "inspection_id" | "zone" | "description" | "condition" | "estimated_repair_cost"
>;

export async function addInspectionItem(input: AddInspectionItemInput) {
  const supabase = await createClient();
  return supabase.from("inspection_items").insert(input).select().single();
}

export type AddInspectionPhotoInput = {
  organization_id: string;
  inspection_item_id: string;
  storage_path: string;
  file_hash: string;
};

// Appelée UNIQUEMENT après confirmation que l'envoi direct au bucket a
// réussi (voir components/inspections/photo-upload-field.tsx) : jamais
// l'inverse, pour ne jamais référencer un fichier qui n'existe pas.
export async function addInspectionPhotoRecord(input: AddInspectionPhotoInput) {
  const supabase = await createClient();
  return supabase.from("inspection_photos").insert(input).select().single();
}

export async function finalizeInspection(id: string) {
  const supabase = await createClient();
  return supabase
    .from("property_inspections")
    .update({ document_status: "finalise" })
    .eq("id", id)
    .select()
    .single();
}

export type TenantValidationStatus = "valide" | "conteste";

// tenant_validation_at n'est pas forcé par trigger serveur (contrairement à
// finalized_at) : ce n'est pas un fait sensible à l'autorisation, juste un
// horodatage déclaratif du locataire — on le pose ici côté serveur (Server
// Action), jamais depuis une valeur envoyée par le client.
export async function submitTenantValidation(
  id: string,
  status: TenantValidationStatus,
  comments: string | null
) {
  const supabase = await createClient();
  return supabase
    .from("property_inspections")
    .update({
      tenant_validation_status: status,
      tenant_validation_at: new Date().toISOString(),
      tenant_comments: comments,
    })
    .eq("id", id)
    .select()
    .single();
}
