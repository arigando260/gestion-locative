import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import { getMyLeaseTerminationRequests } from "@/data/lease-terminations";
import { TenantLeaseTerminationList } from "@/components/lease-terminations/tenant-lease-termination-list";
import { Button } from "@/components/ui/button";

export default async function TenantLeaseTerminationsPage() {
  const requests = await getMyLeaseTerminationRequests();
  const t = await getTranslations("leaseTerminations");

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-xl font-semibold">{t("title")}</h1>
        <Button render={<Link href="/tenant/lease-terminations/new" />} nativeButton={false}>
          {t("create")}
        </Button>
      </div>
      <TenantLeaseTerminationList requests={requests} />
    </div>
  );
}
