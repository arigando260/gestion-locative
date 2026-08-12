import "server-only";
import { createClient } from "@/lib/supabase/server";

// Types écrits à la main : database.types.ts n'a pas encore été régénéré
// depuis le Module 8 (lease_termination_requests en est absent). À
// remplacer par Tables<"lease_termination_requests"> etc. dès que
// `supabase gen types` est rejoué — même remarque que data/maintenance.ts.

export type LeaseTerminationStatus = "en_attente" | "validee" | "refusee" | "annulee";

export type LeaseTerminationRequest = {
  id: string;
  organization_id: string;
  lease_id: string;
  initiated_by_tenant_id: string | null;
  initiated_by_staff_id: string | null;
  requested_end_date: string;
  reason: string;
  status: LeaseTerminationStatus;
  responded_by_tenant_id: string | null;
  responded_by_staff_id: string | null;
  response_note: string | null;
  responded_at: string | null;
  cancelled_at: string | null;
  created_at: string;
  updated_at: string;
};

export type LeaseTerminationRequestWithContext = LeaseTerminationRequest & {
  leases: {
    id: string;
    status: string;
    end_date: string | null;
    tenant_account_id: string;
    properties: { name: string; address: string } | null;
  } | null;
};

// Vue locataire : "toutes organisations confondues" (Module 1b), même
// principe que data/maintenance.ts MaintenanceTicketWithOrgAndProperty.
export type LeaseTerminationRequestWithOrgContext = LeaseTerminationRequest & {
  leases: {
    id: string;
    status: string;
    end_date: string | null;
    properties: { name: string; address: string } | null;
    organizations: { name: string } | null;
  } | null;
};

export type LeaseTerminationFilters = {
  status?: LeaseTerminationStatus;
};

const STAFF_SELECT =
  "*, leases(id, status, end_date, tenant_account_id, properties(name, address))";

// RLS scope déjà la lecture à l'organisation courante (staff interne), même
// principe que getMaintenanceTickets().
export async function getLeaseTerminationRequests(
  filters: LeaseTerminationFilters = {}
): Promise<LeaseTerminationRequestWithContext[]> {
  const supabase = await createClient();
  let query = supabase
    .from("lease_termination_requests")
    .select(STAFF_SELECT)
    .order("created_at", { ascending: false });

  if (filters.status) query = query.eq("status", filters.status);

  const { data, error } = await query.returns<LeaseTerminationRequestWithContext[]>();
  if (error) throw error;
  return data;
}

export async function getLeaseTerminationRequest(
  id: string
): Promise<LeaseTerminationRequestWithContext | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("lease_termination_requests")
    .select(STAFF_SELECT)
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  // .returns<T>() n'enchaîne pas proprement avec .maybeSingle() dans cette
  // version — même correctif d'inférence many-to-one qu'ailleurs (voir
  // data/leases.ts getMyLease), via un simple cast plutôt qu'un générique.
  return data as LeaseTerminationRequestWithContext | null;
}

// Une seule demande en_attente possible par bail (index partiel unique en
// base, Module 8) — utilisé pour afficher clairement l'état AVANT de
// proposer un nouveau formulaire, plutôt que de laisser une tentative
// échouer silencieusement (23505) sur l'écran d'initiation.
export async function getPendingLeaseTerminationRequests(): Promise<
  LeaseTerminationRequestWithContext[]
> {
  return getLeaseTerminationRequests({ status: "en_attente" });
}

// Locataire : toutes ses demandes de résiliation, toutes organisations
// confondues — RLS (via le bail) seule responsable du scoping, même
// principe que getMyMaintenanceTickets().
export async function getMyLeaseTerminationRequests(): Promise<
  LeaseTerminationRequestWithOrgContext[]
> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("lease_termination_requests")
    .select("*, leases(id, status, end_date, properties(name, address), organizations(name))")
    .order("created_at", { ascending: false })
    .returns<LeaseTerminationRequestWithOrgContext[]>();

  if (error) throw error;
  return data;
}

// Contrairement à getMyLeaseTerminationRequests() ci-dessus, l'appartenance
// est revérifiée explicitement ici (filtre sur leases.tenant_account_id, pas
// seulement RLS) — même défense en profondeur que getMyMaintenanceTicket().
// Filtre sur le bail (pas sur initiated_by_tenant_id) : contrairement à un
// ticket de maintenance, une demande visible par ce locataire peut avoir été
// initiée par le STAFF (il en est alors le répondant, pas l'auteur).
export async function getMyLeaseTerminationRequest(
  id: string,
  tenantId: string
): Promise<LeaseTerminationRequestWithOrgContext | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("lease_termination_requests")
    .select(
      "*, leases!inner(id, status, end_date, properties(name, address), organizations(name))"
    )
    .eq("id", id)
    .eq("leases.tenant_account_id", tenantId)
    .maybeSingle();

  if (error) throw error;
  return data as LeaseTerminationRequestWithOrgContext | null;
}

export type CreateLeaseTerminationRequestInput = {
  organization_id: string;
  lease_id: string;
  initiated_by_tenant_id: string | null;
  initiated_by_staff_id: string | null;
  requested_end_date: string;
  reason: string;
};

export async function createLeaseTerminationRequest(
  input: CreateLeaseTerminationRequestInput
) {
  const supabase = await createClient();
  return supabase.from("lease_termination_requests").insert(input).select().single();
}

// Réservé à la partie qui n'a PAS initié (RLS + trigger
// validate_lease_termination_request_transition, Module 8, seuls garants
// réels) : cette fonction se contente d'écrire la transition demandée.
export async function respondToLeaseTerminationRequest(
  id: string,
  status: Extract<LeaseTerminationStatus, "validee" | "refusee">,
  responseNote: string | null
) {
  const supabase = await createClient();
  return supabase
    .from("lease_termination_requests")
    .update({ status, response_note: responseNote })
    .eq("id", id)
    .select()
    .single();
}

// Réservé à l'auteur, tant que la demande est encore en attente (même
// garde-fou base que ci-dessus).
export async function cancelLeaseTerminationRequest(id: string) {
  const supabase = await createClient();
  return supabase
    .from("lease_termination_requests")
    .update({ status: "annulee" })
    .eq("id", id)
    .select()
    .single();
}

// Détermine si l'acteur courant est l'auteur EXACT de la demande — pilote
// l'affichage du bouton "Annuler" (réservé à l'auteur) et, en creux, permet
// de ne jamais proposer "Répondre" à son propre auteur : déjà bloqué en
// base (trigger), mais l'interface ne doit même pas afficher le bouton.
export function isLeaseTerminationInitiator(
  request: Pick<LeaseTerminationRequest, "initiated_by_tenant_id" | "initiated_by_staff_id">,
  actor: { tenantId?: string; staffId?: string }
): boolean {
  if (actor.tenantId) return request.initiated_by_tenant_id === actor.tenantId;
  if (actor.staffId) return request.initiated_by_staff_id === actor.staffId;
  return false;
}
