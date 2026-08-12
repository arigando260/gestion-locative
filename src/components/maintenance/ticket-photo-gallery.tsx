"use client";

import { useRef, useState, type ChangeEvent } from "react";
import { useTranslations } from "next-intl";
import { createClient } from "@/lib/supabase/client";
import { compressImage, hashBlob, buildMaintenanceTicketPhotoPath } from "@/lib/photo-upload";
import {
  confirmMaintenanceTicketPhotoUploadAction,
  deleteMaintenanceTicketPhotoAction,
} from "@/actions/maintenance";
import { Button } from "@/components/ui/button";

export type GalleryPhoto = { id: string; storage_path: string; url: string | null };

type UploadStage = "idle" | "busy" | "error-upload" | "error-confirm";

// Contrat volontairement DIFFÉRENT de components/inspections/photo-upload-field.tsx :
// bucket ("maintenance-photos" vs "inspection-photos"), chemin à 2 niveaux
// (pas de notion d'"item"), et pas de composant "carte" séparé côté serveur
// puisqu'une galerie de tickets est une liste plate, sans regroupement par
// zone — un seul composant client couvre affichage + upload + suppression.
export function TicketPhotoGallery({
  organizationId,
  ticketId,
  photos,
  canUpload,
  canDelete,
  locked,
  lockedMessage,
}: {
  organizationId: string;
  ticketId: string;
  photos: GalleryPhoto[];
  canUpload: boolean;
  canDelete: boolean;
  locked: boolean;
  // Le motif du verrou diffère selon l'acteur (staff: resolu/ferme ; locataire:
  // dès que status <> 'signale', Module 7b) — le message vient donc de
  // l'appelant plutôt que d'être recalculé ici, où l'acteur n'est pas connu.
  lockedMessage?: string;
}) {
  const t = useTranslations("maintenance");
  const inputRef = useRef<HTMLInputElement>(null);
  const pendingRef = useRef<{ path: string; hash: string } | null>(null);
  const [stage, setStage] = useState<UploadStage>("idle");
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  async function confirmUpload(path: string, hash: string) {
    setStage("busy");
    const result = await confirmMaintenanceTicketPhotoUploadAction({
      organization_id: organizationId,
      maintenance_ticket_id: ticketId,
      storage_path: path,
      file_hash: hash,
    });

    if (!result.success) {
      pendingRef.current = { path, hash };
      setStage("error-confirm");
      setUploadError(result.message ?? t("photoUploadError"));
      return;
    }

    pendingRef.current = null;
    setStage("idle");
    setUploadError(null);
  }

  async function handleFileChange(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) return;
    setUploadError(null);

    try {
      setStage("busy");
      const blob = await compressImage(file);
      const hash = await hashBlob(blob);
      const path = buildMaintenanceTicketPhotoPath(organizationId, ticketId);

      const supabase = createClient();
      const { error: uploadErr } = await supabase.storage
        .from("maintenance-photos")
        .upload(path, blob, { contentType: "image/jpeg" });

      if (uploadErr) {
        setStage("error-upload");
        setUploadError(uploadErr.message);
        return;
      }

      await confirmUpload(path, hash);
    } catch (err) {
      setStage("error-upload");
      setUploadError(err instanceof Error ? err.message : String(err));
    } finally {
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  function handleRetryConfirm() {
    if (!pendingRef.current) return;
    setUploadError(null);
    void confirmUpload(pendingRef.current.path, pendingRef.current.hash);
  }

  async function handleDelete(photo: GalleryPhoto) {
    setDeleteError(null);
    setDeletingId(photo.id);
    const result = await deleteMaintenanceTicketPhotoAction({
      id: photo.id,
      storage_path: photo.storage_path,
      maintenance_ticket_id: ticketId,
    });
    setDeletingId(null);
    if (!result.success) {
      setDeleteError(result.message ?? t("photoUploadError"));
    }
  }

  return (
    <div className="flex flex-col gap-3">
      <h2 className="text-lg font-semibold">{t("photos")}</h2>

      {locked && (
        <p className="text-sm text-muted-foreground">
          {lockedMessage ?? t("photosLockedMessage")}
        </p>
      )}

      {photos.length === 0 ? (
        <p className="text-sm text-muted-foreground">{t("noPhotos")}</p>
      ) : (
        <div className="flex flex-wrap gap-3">
          {photos.map((photo) =>
            photo.url ? (
              <div key={photo.id} className="flex flex-col items-center gap-1">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={photo.url}
                  alt=""
                  className="h-24 w-24 rounded-md object-cover"
                />
                {canDelete && !locked && (
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

      {canUpload && !locked && (
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
          {uploadError && (
            <div className="flex items-center gap-2">
              <p className="text-sm text-destructive">{uploadError}</p>
              {stage === "error-confirm" && (
                <Button type="button" size="sm" variant="outline" onClick={handleRetryConfirm}>
                  {t("retryConfirm")}
                </Button>
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
