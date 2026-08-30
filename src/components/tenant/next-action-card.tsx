import type { ReactNode } from "react";
import { CheckCircle2 } from "lucide-react";
import { Link } from "@/i18n/navigation";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/format-date";
import { formatCurrency } from "@/lib/format-currency";
import type { TenantNextAction } from "@/data/tenant-next-action";

type NextActionCopy = {
  t: (key: string, values?: Record<string, string | number>) => string;
  locale: string;
};

const ACCENT_CLASS: Record<TenantNextAction["kind"], string> = {
  signature_pending: "border-l-[#52525b]",
  entry_inspection_pending: "border-l-status-warning-fg",
  closure_in_progress: "border-l-[#52525b]",
  payment_overdue: "border-l-status-danger-fg",
  payment_upcoming: "border-l-[#52525b]",
  calm: "",
};

export function NextActionCard({ action, t, locale }: { action: TenantNextAction } & NextActionCopy): ReactNode {
  if (action.kind === "calm") {
    return (
      <Card className="flex-row items-center gap-3 border-l-[3px] border-l-status-success-fg p-5">
        <CheckCircle2 className="size-5 shrink-0 text-status-success-fg" />
        <div>
          <div className="text-[15px] font-bold">{t("nextActionCalmTitle")}</div>
          <div className="text-[13px] text-muted-foreground">{t("nextActionCalmWhy")}</div>
        </div>
      </Card>
    );
  }

  const leaseHref = `/tenant/leases/${action.leaseId}`;
  let kind: string;
  let title: string;
  let why: string;
  let cta: string;
  let ctaHref = leaseHref;
  let amount: string | undefined;

  switch (action.kind) {
    case "signature_pending":
      kind = t("nextActionSignatureKind");
      title = t("nextActionSignatureTitle");
      why = t("nextActionSignatureWhy");
      cta = t("nextActionSignatureCta");
      break;
    case "entry_inspection_pending":
      kind = t("nextActionInspectionKind");
      title = t("nextActionInspectionTitle");
      why = t("nextActionInspectionWhy");
      cta = t("nextActionInspectionCta");
      ctaHref = `${leaseHref}/inspections/${action.inspectionId}`;
      break;
    case "closure_in_progress":
      kind = t("nextActionClosureKind");
      title = t("nextActionClosureTitle");
      why = t("nextActionClosureWhy");
      cta = t("nextActionClosureCta");
      break;
    case "payment_overdue":
      kind = t("nextActionOverdueKind");
      title = t("nextActionOverdueTitle");
      why = t("nextActionOverdueWhy", { date: formatDate(action.dueDate, locale) });
      cta = t("nextActionOverdueCta");
      amount = formatCurrency(action.amount, locale);
      break;
    case "payment_upcoming":
      kind = t("nextActionUpcomingKind");
      title = t("nextActionUpcomingTitle");
      why = t("nextActionUpcomingWhy", { date: formatDate(action.dueDate, locale) });
      cta = t("nextActionUpcomingCta");
      amount = formatCurrency(action.amount, locale);
      break;
  }

  return (
    <Card className={`gap-2 border-l-[3px] p-5 ${ACCENT_CLASS[action.kind]}`}>
      <div className="text-[11.5px] font-semibold tracking-[0.06em] uppercase">{kind}</div>
      <div className="text-[18px] font-bold">{title}</div>
      <div className="text-[13.5px] text-muted-foreground">{why}</div>
      {amount ? <div className="mt-1 text-[26px] font-bold tabular-nums">{amount}</div> : null}
      <Button className="mt-2 w-fit" render={<Link href={ctaHref} />} nativeButton={false}>
        {cta}
      </Button>
    </Card>
  );
}
