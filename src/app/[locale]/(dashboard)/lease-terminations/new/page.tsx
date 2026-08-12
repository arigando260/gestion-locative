import { getTranslations } from "next-intl/server";
import { getLeasesForOrg } from "@/data/leases";
import { getProperties } from "@/data/properties";
import { getPendingLeaseTerminationRequests } from "@/data/lease-terminations";
import { StaffInitiateForm } from "@/components/lease-terminations/staff-initiate-form";

export default async function NewLeaseTerminationPage() {
  const [leases, properties, pending] = await Promise.all([
    getLeasesForOrg(),
    getProperties(),
    getPendingLeaseTerminationRequests(),
  ]);
  const t = await getTranslations("leaseTerminations");

  const propertyNames = new Map(properties.map((property) => [property.id, property.name]));
  const pendingByLease = new Map(pending.map((request) => [request.lease_id, request.id]));

  const activeLeases = leases.filter((lease) => lease.status === "actif");
  const eligibleLeases = activeLeases
    .filter((lease) => !pendingByLease.has(lease.id))
    .map((lease) => ({
      id: lease.id,
      label: propertyNames.get(lease.property_id) ?? "—",
    }));
  const blockedLeases = activeLeases
    .filter((lease) => pendingByLease.has(lease.id))
    .map((lease) => ({
      id: lease.id,
      label: propertyNames.get(lease.property_id) ?? "—",
      requestId: pendingByLease.get(lease.id)!,
    }));

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("createTitle")}</h1>
      <StaffInitiateForm eligibleLeases={eligibleLeases} blockedLeases={blockedLeases} />
    </div>
  );
}
