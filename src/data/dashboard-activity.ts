import "server-only";
import { createClient } from "@/lib/supabase/server";

export type RecentActivityEvent =
  | { kind: "payment_received"; at: string; propertyName: string; tenantName: string | null }
  | { kind: "issue_reported"; at: string; propertyName: string; reportedByTenant: boolean }
  | { kind: "lease_signed"; at: string; propertyName: string; tenantName: string | null }
  | { kind: "notice_filed"; at: string; propertyName: string; tenantName: string | null };

type LeaseEmbed = {
  properties: { name: string } | null;
  tenant_accounts: { full_name: string | null } | null;
} | null;

// "Activité récente" du tableau de bord -- 4 tables déjà existantes, chacune
// déjà porteuse d'un horodatage réel (payments.created_at,
// maintenance_tickets.created_at, lease_contracts.approved_at,
// lease_termination_requests.created_at), aucune nouvelle colonne. Simple
// mélange trié par date décroissante, pas de flux d'activité en base --
// recalculé à chaque affichage.
export async function getRecentActivity(
  organizationId: string,
  limit = 6
): Promise<RecentActivityEvent[]> {
  const supabase = await createClient();

  const [{ data: payments, error: paymentsError }, { data: tickets, error: ticketsError }, { data: contracts, error: contractsError }, { data: notices, error: noticesError }] =
    await Promise.all([
      supabase
        .from("payments")
        .select("created_at, leases(properties(name), tenant_accounts(full_name))")
        .eq("organization_id", organizationId)
        .order("created_at", { ascending: false })
        .limit(limit),
      supabase
        .from("maintenance_tickets")
        .select("created_at, reported_by_tenant_id, properties(name)")
        .eq("organization_id", organizationId)
        .order("created_at", { ascending: false })
        .limit(limit),
      supabase
        .from("lease_contracts")
        .select("approved_at, leases(properties(name), tenant_accounts(full_name))")
        .eq("organization_id", organizationId)
        .not("approved_at", "is", null)
        .order("approved_at", { ascending: false })
        .limit(limit),
      supabase
        .from("lease_termination_requests")
        .select("created_at, leases(properties(name), tenant_accounts(full_name))")
        .eq("organization_id", organizationId)
        .order("created_at", { ascending: false })
        .limit(limit),
    ]);

  if (paymentsError) throw paymentsError;
  if (ticketsError) throw ticketsError;
  if (contractsError) throw contractsError;
  if (noticesError) throw noticesError;

  const events: RecentActivityEvent[] = [];

  for (const row of payments ?? []) {
    const lease = row.leases as unknown as LeaseEmbed;
    events.push({
      kind: "payment_received",
      at: row.created_at,
      propertyName: lease?.properties?.name ?? "—",
      tenantName: lease?.tenant_accounts?.full_name ?? null,
    });
  }

  for (const row of tickets ?? []) {
    const property = row.properties as unknown as { name: string } | null;
    events.push({
      kind: "issue_reported",
      at: row.created_at,
      propertyName: property?.name ?? "—",
      reportedByTenant: row.reported_by_tenant_id !== null,
    });
  }

  for (const row of contracts ?? []) {
    if (!row.approved_at) continue;
    const lease = row.leases as unknown as LeaseEmbed;
    events.push({
      kind: "lease_signed",
      at: row.approved_at,
      propertyName: lease?.properties?.name ?? "—",
      tenantName: lease?.tenant_accounts?.full_name ?? null,
    });
  }

  for (const row of notices ?? []) {
    const lease = row.leases as unknown as LeaseEmbed;
    events.push({
      kind: "notice_filed",
      at: row.created_at,
      propertyName: lease?.properties?.name ?? "—",
      tenantName: lease?.tenant_accounts?.full_name ?? null,
    });
  }

  events.sort((a, b) => (a.at < b.at ? 1 : -1));
  return events.slice(0, limit);
}
