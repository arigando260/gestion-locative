import { getTranslations } from "next-intl/server";
import { getMyLeases } from "@/data/leases";
import { TenantLeaseList } from "@/components/tenant/lease-list";

export default async function TenantHomePage() {
  const leases = await getMyLeases();
  const t = await getTranslations("tenant");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("myLeases")}</h1>
      <TenantLeaseList leases={leases} />
    </div>
  );
}
