"use client";

import { useRef, useState, type ChangeEvent } from "react";
import { useTranslations } from "next-intl";
import { ImagePlusIcon } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { compressImage, hashBlob, buildInspectionPhotoPath } from "@/lib/photo-upload";
import { confirmInspectionPhotoUploadAction, deleteInspectionPhotoAction } from "@/actions/inspections";
import { Button } from "@/components/ui/button";

export type ItemPhoto = { id: string; storage_path: string; url: string | null };

type Stage = "idle" | "busy" | "error-upload" | "error-confirm";

// Envoi direct navigateur -> Storage (policies Module 6 conçues pour ça),
// puis confirmation en base via Server Action UNIQUEMENT si l'envoi a
// réussi. Si la confirmation échoue après un envoi réussi, on ne
// réenvoie jamais le fichier : on retente uniquement l'écriture de la
// ligne, avec le même storage_path/hash déjà obtenus.
//
// Affiche aussi les photos déjà envoyées, avec suppression (jamais
// d'édition — seulement supprimer + renvoyer, Module 6j). canUpload gère à
// la fois l'ajout et la suppression : les deux relèvent de la même policy
// RLS (brouillon + permission ou locataire propriétaire du brouillon).
export function PhotoUploadField({
  organizationId,
  inspectionId,
  inspectionItemId,
  leaseId,
  photos,
  canUpload,
}: {
  organizationId: string;
  inspectionId: string;
  inspectionItemId: string;
  leaseId: string;
  photos: ItemPhoto[];
  canUpload: boolean;
}) {
  const t = useTranslations("inspections");
  const inputRef = useRef<HTMLInputElement>(null);
  const pendingRef = useRef<{ path: string; hash: string } | null>(null);
  const [stage, setStage] = useState<Stage>("idle");
  const [error, setError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);

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

  async function handleDelete(photo: ItemPhoto) {
    setDeleteError(null);
    setDeletingId(photo.id);
    const result = await deleteInspectionPhotoAction({
      id: photo.id,
      storage_path: photo.storage_path,
      inspection_id: inspectionId,
      lease_id: leaseId,
    });
    setDeletingId(null);
    if (!result.success) {
      setDeleteError(result.message ?? t("photoUploadError"));
    }
  }

  return (
    <div className="flex flex-col gap-2">
      {photos.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {photos.map((photo) =>
            photo.url ? (
              <div key={photo.id} className="flex flex-col items-center gap-1">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={photo.url}
                  alt=""
                  className="h-24 w-24 rounded-md object-cover"
                />
                {canUpload && (
                  <Button
                    type="button"
                    size="xs"
                    variant="outline"
                    disabled={deletingId === photo.id}
                    onClick={() => handleDelete(photo)}
                  >
                    {t("deletePhoto")}
                  </Button>
                )}
              </div>
            ) : null
          )}
        </div>
      )}
      {deleteError && <p className="text-sm text-destructive">{deleteError}</p>}

      {canUpload && (
        <>
          <div className="relative flex flex-col items-center justify-center gap-2 rounded-md border border-dashed border-input p-6 text-center">
            <ImagePlusIcon className="h-6 w-6 text-muted-foreground" aria-hidden="true" />
            <p className="text-sm text-muted-foreground">{t("uploadDropzoneLabel")}</p>
            <input
              ref={inputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp"
              onChange={handleFileChange}
              disabled={stage === "busy"}
              aria-label={t("uploadDropzoneLabel")}
              className="absolute inset-0 h-full w-full cursor-pointer opacity-0 disabled:cursor-not-allowed"
            />
          </div>
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
        </>
      )}
    </div>
  );
}
