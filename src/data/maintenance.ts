import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis les Modules 7/7b (maintenance_tickets, maintenance_ticket_photos,
// deposit_ledger.maintenance_ticket_id en sont absents). À remplacer par
// Tables<"maintenance_tickets"> etc. dès que `supabase gen types` est rejoué.

export type MaintenanceTicketStatus = "signale" | "en_cours" | "resolu" | "ferme";
export type MaintenanceTicketPriority = "basse" | "normale" | "haute" | "urgente";

export type MaintenanceTicket = {
  id: string;
  organization_id: string;
  property_id: string;
  lease_id: string | null;
  reported_by_tenant_id: string | null;
  reported_by_staff_id: string | null;
  title: string;
  description: string | null;
  priority: MaintenanceTicketPriority;
  status: MaintenanceTicketStatus;
  estimated_cost: number | null;
  actual_cost: number | null;
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
};

export type MaintenanceTicketWithProperty = MaintenanceTicket & {
  properties: { name: string } | null;
};

export type MaintenanceTicketWithContext = MaintenanceTicket & {
  properties: { name: string; address: string } | null;
};

// Vue locataire : "toutes organisations confondues" (Module 1b), même
// principe que data/leases.ts LeaseWithContext.
export type MaintenanceTicketWithOrgAndProperty = MaintenanceTicket & {
  properties: { name: string; address: string } | null;
  organizations: { name: string } | null;
};

export type MaintenanceTicketPhoto = {
  id: string;
  organization_id: string;
  maintenance_ticket_id: string;
  storage_path: string;
  file_hash: string;
  uploaded_at: string;
};

// Sous-ensemble de deposit_ledger : juste ce qu'il faut pour afficher le
// montant faisant foi et pointer vers l'écran de cautions du bail concerné.
export type MaintenanceTicketImputation = {
  id: string;
  lease_id: string | null;
  reservation_id: string | null;
  amount: number;
  reason: string | null;
  created_at: string;
};

export type MaintenanceTicketFilters = {
  status?: MaintenanceTicketStatus;
  priority?: MaintenanceTicketPriority;
  propertyId?: string;
};

// RLS scope déjà la lecture à l'organisation courante (staff interne) — même
// principe que getProperties(), pas de filtre organization_id explicite ici.
export async function getMaintenanceTickets(
  filters: MaintenanceTicketFilters = {}
): Promise<MaintenanceTicketWithProperty[]> {
  const supabase = await createClient();
  let query = supabase
    .from("maintenance_tickets")
    .select("*, properties(name)")
    .order("created_at", { ascending: false });

  if (filters.status) query = query.eq("status", filters.status);
  if (filters.priority) query = query.eq("priority", filters.priority);
  if (filters.propertyId) query = query.eq("property_id", filters.propertyId);

  const { data, error } = await query.returns<MaintenanceTicketWithProperty[]>();
  if (error) throw error;
  return data;
}

export async function getMaintenanceTicket(
  id: string
): Promise<MaintenanceTicketWithContext | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("maintenance_tickets")
    .select("*, properties(name, address)")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  // .returns<T>() n'enchaîne pas proprement avec .maybeSingle() dans cette
  // version — même correctif d'inférence many-to-one qu'ailleurs (voir
  // data/leases.ts getMyLease), via un simple cast plutôt qu'un générique.
  return data as MaintenanceTicketWithContext | null;
}

// Locataire : toutes ses organisations confondues, RLS seule responsable du
// scoping (reported_by_tenant_id = auth.uid()) — même principe que
// data/leases.ts getMyLeases(), pas de filtre explicite ici.
export async function getMyMaintenanceTickets(): Promise<
  MaintenanceTicketWithOrgAndProperty[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("maintenance_tickets")
    .select("*, properties(name, address), organizations(name)")
    .order("created_at", { ascending: false })
    .returns<MaintenanceTicketWithOrgAndProperty[]>();

  if (error) throw error;
  return data;
}

// Contrairement à getMyMaintenanceTickets() ci-dessus, l'appartenance est
// revérifiée explicitement ici (filtre reported_by_tenant_id, pas seulement
// RLS) : un ticket précis affiché en détail donne accès à l'upload/
// suppression de photo et à l'édition, la lecture d'un seul enregistrement
// par id mérite cette défense en profondeur supplémentaire, demandée
// explicitement pour cet écran.
export async function getMyMaintenanceTicket(
  id: string,
  tenantId: string
): Promise<MaintenanceTicketWithOrgAndProperty | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("maintenance_tickets")
    .select("*, properties(name, address), organizations(name)")
    .eq("id", id)
    .eq("reported_by_tenant_id", tenantId)
    .maybeSingle();

  if (error) throw error;
  return data as MaintenanceTicketWithOrgAndProperty | null;
}

export async function getMaintenanceTicketPhotos(
  ticketId: string
): Promise<MaintenanceTicketPhoto[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("maintenance_ticket_photos")
    .select("*")
    .eq("maintenance_ticket_id", ticketId)
    .order("uploaded_at", { ascending: true });

  if (error) throw error;
  return data;
}

// Bucket privé (Module 7) : jamais d'URL publique, même principe que
// data/inspections.ts getSignedPhotoUrls.
export async function getSignedMaintenanceTicketPhotoUrls(
  storagePaths: string[]
): Promise<Record<string, string>> {
  if (storagePaths.length === 0) return {};

  const supabase = await createClient();
  const { data, error } = await supabase.storage
    .from("maintenance-photos")
    .createSignedUrls(storagePaths, 3600);

  if (error) throw error;

  const result: Record<string, string> = {};
  for (const item of data) {
    if (item.signedUrl && item.path) result[item.path] = item.signedUrl;
  }
  return result;
}

// Existence d'une imputation référençant ce ticket, vérifiée explicitement
// côté data layer pour piloter l'affichage (champs coût désactivés) — la
// base reste seule autorité réelle (trigger
// prevent_maintenance_ticket_cost_change_after_imputation, Module 7b),
// cette fonction ne fait que refléter son résultat à l'écran sans s'y fier
// pour la sécurité, ni s'appuyer sur un try/catch de l'erreur d'écriture.
export async function getMaintenanceTicketImputations(
  ticketId: string
): Promise<MaintenanceTicketImputation[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("deposit_ledger")
    .select("id, lease_id, reservation_id, amount, reason, created_at")
    .eq("maintenance_ticket_id", ticketId)
    .order("created_at", { ascending: true });

  if (error) throw error;
  return data as MaintenanceTicketImputation[];
}

export type CreateMaintenanceTicketInput = {
  organization_id: string;
  property_id: string;
  lease_id: string | null;
  reported_by_staff_id: string;
  title: string;
  description: string | null;
  priority: MaintenanceTicketPriority;
};

export async function createMaintenanceTicket(input: CreateMaintenanceTicketInput) {
  const supabase = await createClient();
  return supabase.from("maintenance_tickets").insert(input).select().single();
}

export type CreateTenantMaintenanceTicketInput = {
  organization_id: string;
  property_id: string;
  lease_id: string;
  reported_by_tenant_id: string;
  title: string;
  description: string | null;
};

// priority/status/actual_cost/reported_by_staff_id volontairement absents de
// l'insert : les valeurs par défaut de la colonne (respectivement 'normale',
// 'signale', NULL, NULL) sont exactement celles qu'exige la policy RLS
// d'insertion locataire (maintenance_tickets_insert, Module 7) — les fixer
// ici en dur risquerait une divergence si l'un des deux changeait un jour
// sans l'autre.
export async function createTenantMaintenanceTicket(
  input: CreateTenantMaintenanceTicketInput
) {
  const supabase = await createClient();
  return supabase.from("maintenance_tickets").insert(input).select().single();
}

// Générique (titre/description) : utilisable aussi bien par le staff que le
// locataire, RLS + le trigger restrict_tenant_maintenance_ticket_update_fields
// (Module 7) décident seuls de ce qui est réellement permis selon l'acteur et
// le statut du ticket — rien à distinguer ici.
export async function updateMaintenanceTicketDetails(
  id: string,
  input: { title: string; description: string | null }
) {
  const supabase = await createClient();
  return supabase
    .from("maintenance_tickets")
    .update(input)
    .eq("id", id)
    .select()
    .single();
}

export async function updateMaintenanceTicketStatus(
  id: string,
  status: MaintenanceTicketStatus
) {
  const supabase = await createClient();
  return supabase
    .from("maintenance_tickets")
    .update({ status })
    .eq("id", id)
    .select()
    .single();
}

export type UpdateMaintenanceTicketCostInput = {
  estimated_cost: number | null;
  actual_cost: number | null;
};

// Le gel post-imputation (Module 7b) est appliqué par la base quel que soit
// l'appelant : cet appel peut échouer même si l'écran affichait les champs
// actifs (course avec une imputation posée entre-temps) — l'erreur P0001
// remonte alors telle quelle, voir lib/errors.ts.
export async function updateMaintenanceTicketCost(
  id: string,
  input: UpdateMaintenanceTicketCostInput
) {
  const supabase = await createClient();
  return supabase
    .from("maintenance_tickets")
    .update(input)
    .eq("id", id)
    .select()
    .single();
}

export type AddMaintenanceTicketPhotoInput = {
  organization_id: string;
  maintenance_ticket_id: string;
  storage_path: string;
  file_hash: string;
};

// Appelée UNIQUEMENT après confirmation que l'envoi direct au bucket a
// réussi (voir components/maintenance/ticket-photo-gallery.tsx) — même
// principe que data/inspections.ts addInspectionPhotoRecord.
export async function addMaintenanceTicketPhotoRecord(
  input: AddMaintenanceTicketPhotoInput
) {
  const supabase = await createClient();
  return supabase.from("maintenance_ticket_photos").insert(input).select().single();
}

// Supprime la ligne d'abord (RLS + trigger de verrou font autorité), le
// fichier ensuite : si la suppression en base échoue, le fichier doit
// rester pour ne jamais laisser une ligne pointer vers un objet manquant.
// L'inverse (fichier d'abord) risquerait la situation opposée, pire pour
// l'utilisateur (vignette cassée) qu'un fichier orphelin dans le bucket.
export async function deleteMaintenanceTicketPhoto(id: string, storagePath: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("maintenance_ticket_photos").delete().eq("id", id);
  if (error) return { error };

  await supabase.storage.from("maintenance-photos").remove([storagePath]);
  return { error: null };
}
