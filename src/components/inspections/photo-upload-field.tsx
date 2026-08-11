"use client";

import { useRef, useState, type ChangeEvent } from "react";
import { useTranslations } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import { compressImage, hashBlob, buildInspectionPhotoPath } from "@/lib/photo-upload";
import { confirmInspectionPhotoUploadAction } from "@/actions/inspections";
import { Button } from "@/components/ui/button";

type Stage = "idle" | "busy" | "error-upload" | "error-confirm";

// Envoi direct navigateur -> Storage (policies Module 6 conçues pour ça),
// puis confirmation en base via Server Action UNIQUEMENT si l'envoi a
// réussi. Si la confirmation échoue après un envoi réussi, on ne
// réenvoie jamais le fichier : on retente uniquement l'écriture de la
// ligne, avec le même storage_path/hash déjà obtenus.
export function PhotoUploadField({
  organizationId,
  inspectionId,
  inspectionItemId,
  leaseId,
}: {
  organizationId: string;
  inspectionId: string;
  inspectionItemId: string;
  leaseId: string;
}) {
  const t = useTranslations("inspections");
  const inputRef = useRef<HTMLInputElement>(null);
  const pendingRef = useRef<{ path: string; hash: string } | null>(null);
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState<string | null>(null);

  async function confirmUpload(path: string, hash: string) {
    setStage("busy");
    const result = await confirmInspectionPhotoUploadAction({
      organization_id: organizationId,
      inspection_item_id: inspectionItemId,
      inspection_id: inspectionId,
      lease_id: leaseId,
      storage_path: path,
      file_hash: hash,
    });

    if (!result.success) {
      pendingRef.current = { path, hash };
      setStage("error-confirm");
      setError(result.message ?? t("photoUploadError"));
      return;
    }

    pendingRef.current = null;
    setStage("idle");
    setError(null);
  }

  async function handleFileChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setError(null);

    try {
      setStage("busy");
      const blob = await compressImage(file);
      const hash = await hashBlob(blob);
      const path = buildInspectionPhotoPath(organizationId, inspectionId, inspectionItemId);

      const supabase = createClient();
      const { error: uploadError } = await supabase.storage
        .from("inspection-photos")
        .upload(path, blob, { contentType: "image/jpeg" });

      if (uploadError) {
        setStage("error-upload");
        setError(uploadError.message);
        return;
      }

      await confirmUpload(path, hash);
    } catch (err) {
      setStage("error-upload");
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  function handleRetryConfirm() {
    if (!pendingRef.current) return;
    setError(null);
    void confirmUpload(pendingRef.current.path, pendingRef.current.hash);
  }

  return (
    <div className="flex flex-col gap-2">
      <input
        ref={inputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp"
        onChange={handleFileChange}
        disabled={stage === "busy"}
        className="text-sm"
      />
      {stage === "busy" && (
        <p className="text-sm text-muted-foreground">{t("uploadingPhoto")}</p>
      )}
      {error && (
        <div className="flex items-center gap-2">
          <p className="text-sm text-destructive">{error}</p>
          {stage === "error-confirm" && (
            <Button type="button" size="sm" variant="outline" onClick={handleRetryConfirm}>
              {t("retryConfirm")}
            </Button>
          )}
        </div>
      )}
    </div>
  );
}
