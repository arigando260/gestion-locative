import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getLeaseTerminationRequests } from "@/data/lease-terminations";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { LeaseTerminationList } from "@/components/lease-terminations/lease-termination-list";
import { LeaseTerminationFilters } from "@/components/lease-terminations/lease-termination-filters";
import { Button } from "@/components/ui/button";
import type { LeaseTerminationStatus } from "@/data/lease-terminations";

const VALID_STATUSES: LeaseTerminationStatus[] = [
  "en_attente",
  "validee",
  "refusee",
  "annulee",
];

export default async function LeaseTerminationsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const raw = await searchParams;
  const filters = {
    status: VALID_STATUSES.find((s) => s === raw.status),
  };

  const [requests, permissions] = await Promise.all([
    getLeaseTerminationRequests(filters),
    getCurrentUserPermissions(),
  ]);

  const t = await getTranslations("leaseTerminations");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        {/* Aide à l'ergonomie uniquement : la policy RLS sur l'INSERT reste
            la seule autorité réelle, voir ARCHITECTURE.md. */}
        {can(permissions, "lease_termination_requests", "create") && (
          <Button render={<Link href="/lease-terminations/new" />} nativeButton={false}>
            {t("create")}
          </Button>
        )}
      </div>
      <LeaseTerminationFilters filters={filters} />
      <LeaseTerminationList requests={requests} />
    </div>
  );
}
