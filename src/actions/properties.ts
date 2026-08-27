"use server";

import { revalidatePath } from "next/cache";
import { getCurrentProfile } from "@/data/session";
import { createProperty, attachPropertyToBuilding } from "@/data/properties";
import { createBuilding } from "@/data/buildings";
import { toUserMessage } from "@/lib/errors";
import { redirect } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";

export type ActionState = { success: boolean; message?: string } | null;

// Marqueur du champ building_id (property-form.tsx) quand l'utilisateur
// choisit "Créer un nouvel immeuble" plutôt qu'un immeuble existant ou
// "aucun immeuble" (valeur vide) — jamais un id réel, sans risque de
// collision avec un uuid.
const NEW_BUILDING_MARKER = "__new__";

export async function createPropertyAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  // Re-vérifié ici, jamais supposé acquis du seul fait que la page l'a déjà
  // vérifié (une Server Action est un point d'entrée POST indépendant).
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const buildingSelection = String(formData.get("building_id") ?? "");
  let building_id: string | null = null;

  if (buildingSelection === NEW_BUILDING_MARKER) {
    // Un seul écran, pas d'aller-retour vers /buildings (Module 13,
    // point 3 du périmètre écran) : l'immeuble est créé ici, dans la même
    // Server Action, avant le bien lui-même.
    const newBuildingName = String(formData.get("new_building_name") ?? "").trim();
    const newBuildingCountryCode = String(formData.get("new_building_country_code") ?? "").trim();
    const newBuildingCity = String(formData.get("new_building_city") ?? "").trim();
    const newBuildingNeighborhood = String(formData.get("new_building_neighborhood") ?? "").trim();
    const newBuildingFloorsRaw = String(formData.get("new_building_floors_count") ?? "").trim();
    const newBuildingFloors = newBuildingFloorsRaw === "" ? null : Number(newBuildingFloorsRaw);

    if (
      !newBuildingName ||
      !newBuildingCountryCode ||
      !newBuildingCity ||
      !newBuildingNeighborhood ||
      (newBuildingFloors !== null && Number.isNaN(newBuildingFloors))
    ) {
      return { success: false, message: "Merci de remplir tous les champs de l'immeuble." };
    }

    const { data: building, error: buildingError } = await createBuilding({
      organization_id: profile.organization_id,
      name: newBuildingName,
      country_code: newBuildingCountryCode,
      city: newBuildingCity,
      neighborhood: newBuildingNeighborhood,
      address_complement: null,
      floors_count: newBuildingFloors,
    });

    if (buildingError) {
      return { success: false, message: await toUserMessage(buildingError) };
    }
    building_id = building.id;
  } else if (buildingSelection !== "") {
    building_id = buildingSelection;
  }

  const name = String(formData.get("name") ?? "").trim();
  const addressComplementRaw = String(formData.get("address_complement") ?? "").trim();
  const address_complement = addressComplementRaw === "" ? null : addressComplementRaw;
  const price = Number(formData.get("price"));
  const location_type = String(formData.get("location_type") ?? "");

  // country_code/city/neighborhood seulement quand le bien reste autonome
  // (décision Module 12c) ; nuls d'office quand rattaché à un immeuble
  // (Module 13 — properties_building_address_exclusive, forcé de toute
  // façon côté serveur par create_property(), mais jamais envoyé depuis un
  // champ qui n'est même pas affiché dans ce cas).
  let country_code: string | null = null;
  let city: string | null = null;
  let neighborhood: string | null = null;
  if (building_id === null) {
    country_code = String(formData.get("country_code") ?? "").trim();
    city = String(formData.get("city") ?? "").trim();
    neighborhood = String(formData.get("neighborhood") ?? "").trim();
    if (!country_code || !city || !neighborhood) {
      return { success: false, message: "Merci de remplir tous les champs." };
    }
  }

  if (!name || !location_type || Number.isNaN(price)) {
    return { success: false, message: "Merci de remplir tous les champs." };
  }

  const { data, error } = await createProperty({
    organization_id: profile.organization_id,
    name,
    country_code,
    city,
    neighborhood,
    address_complement,
    price,
    location_type,
    building_id,
  });

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath("/properties");
  redirect({
    href: `/properties/${data.id}`,
    locale: (formData.get("locale") as string) ?? routing.defaultLocale,
  });
  // redirect() lève toujours — inatteignable, seulement pour satisfaire le
  // contrôle de flux TypeScript (le type de retour de redirect() n'est pas
  // "never" dans cette version de next-intl).
  return null;
}

// Update ciblé sur UN bien existant (building_id + adresse propre vidée),
// pas un formulaire d'édition générique (Module 13, point 1 du périmètre
// écran). La vraie garantie reste properties_update
// (has_permission('properties','update') AND agent_property_scope) et le
// CHECK properties_building_address_exclusive côté base — rien à dupliquer
// ici, la Server Action se contente de relayer.
export async function attachPropertyToBuildingAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const profile = await getCurrentProfile();
  if (!profile) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const propertyId = String(formData.get("property_id") ?? "");
  const buildingId = String(formData.get("building_id") ?? "");
  if (!propertyId || !buildingId) {
    return { success: false, message: "Immeuble requis." };
  }

  const { error } = await attachPropertyToBuilding(propertyId, buildingId);
  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/properties/${propertyId}`);
  return { success: true };
}
