import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent } from "@/components/ui/card";
import type { InspectionWithEffectiveStatus } from "@/data/inspections";

const TYPE_KEY: Record<string, string> = {
  entree: "typeEntree",
  sortie: "typeSortie",
};

const DOCUMENT_STATUS_KEY: Record<string, string> = {
  brouillon: "documentStatusBrouillon",
  finalise: "documentStatusFinalise",
};

const VALIDATION_KEY: Record<string, string> = {
  en_attente: "validationEnAttente",
  valide: "validationValide",
  conteste: "validationConteste",
  accepte_tacitement: "validationAccepteTacitement",
};

const VALIDATION_VARIANT: Record<string, "secondary" | "destructive" | "default"> = {
  valide: "default",
  accepte_tacitement: "default",
  conteste: "destructive",
};

export async function InspectionList({
  inspections,
  basePath,
}: {
  inspections: InspectionWithEffectiveStatus[];
  basePath: string;
}) {
  const t = await getTranslations("inspections");

  if (inspections.length === 0) {
    return <p className="text-sm text-muted-foreground">{t("empty")}</p>;
  }

  const row = (inspection: InspectionWithEffectiveStatus) => ({
    typeLabel: t(TYPE_KEY[inspection.inspection_type ?? ""] ?? "typeEntree"),
    date: inspection.inspection_date,
    documentLabel: t(DOCUMENT_STATUS_KEY[inspection.document_status ?? ""] ?? "documentStatusBrouillon"),
    validationLabel: t(VALIDATION_KEY[inspection.effective_validation_status ?? ""] ?? "validationEnAttente"),
    variant: VALIDATION_VARIANT[inspection.effective_validation_status ?? ""] ?? "secondary",
  });

  return (
    <>
      <div className="hidden sm:block">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>{t("type")}</TableHead>
              <TableHead>{t("inspectionDate")}</TableHead>
              <TableHead>{t("documentStatus")}</TableHead>
              <TableHead>{t("validationStatus")}</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {inspections.map((inspection) => {
              const r = row(inspection);
              return (
                <TableRow key={inspection.id}>
                  <TableCell>
                    <Link
                      href={`${basePath}/${inspection.id}`}
                      className="font-medium hover:underline"
                    >
                      {r.typeLabel}
                    </Link>
                  </TableCell>
                  <TableCell>{r.date}</TableCell>
                  <TableCell>{r.documentLabel}</TableCell>
                  <TableCell>
                    <Badge variant={r.variant}>{r.validationLabel}</Badge>
                  </TableCell>
                </TableRow>
              );
            })}
          </TableBody>
        </Table>
      </div>
      <div className="flex flex-col gap-3 sm:hidden">
        {inspections.map((inspection) => {
          const r = row(inspection);
          return (
            <Link key={inspection.id} href={`${basePath}/${inspection.id}`}>
              <Card>
                <CardContent className="flex flex-col gap-1">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{r.typeLabel}</span>
                    <Badge variant={r.variant}>{r.validationLabel}</Badge>
                  </div>
                  <span className="text-sm text-muted-foreground">{r.date}</span>
                  <span className="text-sm text-muted-foreground">{r.documentLabel}</span>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}
