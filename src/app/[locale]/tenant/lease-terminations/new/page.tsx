import { getTranslations } from "next-intl/server";
import { getMyLeases } from "@/data/leases";
import { getMyLeaseTerminationRequests } from "@/data/lease-terminations";
import { TenantInitiateForm } from "@/components/lease-terminations/tenant-initiate-form";

export default async function NewTenantLeaseTerminationPage() {
  const [leases, requests] = await Promise.all([
    getMyLeases(),
    getMyLeaseTerminationRequests(),
  ]);
  const t = await getTranslations("leaseTerminations");

  const pendingByLease = new Map(
    requests.filter((request) => request.status === "en_attente").map((request) => [request.lease_id, request.id])
  );

  const activeLeases = leases.filter((lease) => lease.status === "actif");
  const labelFor = (lease: (typeof activeLeases)[number]) =>
    lease.organizations?.name
      ? `${lease.properties?.name ?? "—"} — ${lease.organizations.name}`
      : (lease.properties?.name ?? "—");

  const eligibleLeases = activeLeases
    .filter((lease) => !pendingByLease.has(lease.id))
    .map((lease) => ({ id: lease.id, label: labelFor(lease) }));
  const blockedLeases = activeLeases
    .filter((lease) => pendingByLease.has(lease.id))
    .map((lease) => ({
      id: lease.id,
      label: labelFor(lease),
      requestId: pendingByLease.get(lease.id)!,
    }));

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <TenantInitiateForm eligibleLeases={eligibleLeases} blockedLeases={blockedLeases} />
    </div>
  );
}
