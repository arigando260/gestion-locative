"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";
import { deleteInspectionItemAction } from "@/actions/inspections";
import type { InspectionItem } from "@/data/inspections";
import { Button } from "@/components/ui/button";
import { InspectionItemForm } from "@/components/inspections/inspection-item-form";

const CONDITION_KEY: Record<string, string> = {
  bon: "conditionBon",
  usage_normal: "conditionUsageNormal",
  degrade: "conditionDegrade",
  hors_service: "conditionHorsService",
};

// Affichage en lecture d'un constat, avec bascule vers InspectionItemForm en
// mode édition et bouton de suppression — visible uniquement tant que
// l'état des lieux parent est en brouillon (canManage, calculé par
// l'appelant : InspectionItemCard).
export function InspectionItemBody({
  item,
  inspectionId,
  leaseId,
  canManage,
}: {
  item: Pick<InspectionItem, "id" | "zone" | "condition" | "description" | "estimated_repair_cost">;
  inspectionId: string;
  leaseId: string;
  canManage: boolean;
}) {
  const t = useTranslations("inspections");
  const [editing, setEditing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  async function handleDelete() {
    setDeleteError(null);
    setDeleting(true);
    const result = await deleteInspectionItemAction({
      id: item.id,
      inspection_id: inspectionId,
      lease_id: leaseId,
    });
    setDeleting(false);
    if (!result.success) {
      setDeleteError(result.message ?? t("photoUploadError"));
    }
  }

  if (editing) {
    return (
      <InspectionItemForm
        inspectionId={inspectionId}
        leaseId={leaseId}
        item={item}
        onCancel={() => setEditing(false)}
      />
    );
  }

  return (
    <>
      <p className="text-muted-foreground">
        {t("condition")}: {t(CONDITION_KEY[item.condition] ?? "conditionBon")}
      </p>
      {item.description && <p>{item.description}</p>}
      {item.estimated_repair_cost != null && (
        <p className="text-muted-foreground">
          {t("estimatedRepairCost")}: {item.estimated_repair_cost}
        </p>
      )}
      {canManage && (
        <div className="flex gap-2">
          <Button type="button" size="sm" variant="outline" onClick={() => setEditing(true)}>
            {t("editItem")}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={deleting}
            onClick={handleDelete}
          >
            {t("deleteItem")}
          </Button>
        </div>
      )}
      {deleteError && <p className="text-sm text-destructive">{deleteError}</p>}
    </>
  );
}
