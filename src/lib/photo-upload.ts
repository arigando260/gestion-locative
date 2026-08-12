// Utilitaires CÔTÉ NAVIGATEUR uniquement (pas de "server-only" ici) : la
// compression et le hash doivent porter sur les octets réellement envoyés,
// donc s'exécuter avant toute transmission — voir ARCHITECTURE.md / Module 6.
// Aucune nouvelle dépendance : Canvas et Web Crypto sont natifs au navigateur.

const MAX_DIMENSION = 1600;
const JPEG_QUALITY = 0.8;

// Redimensionne (plus grand côté <= 1600px) et réencode en JPEG qualité 0.8,
// quel que soit le format d'origine (jpeg/png/webp, cf. mime types acceptés
// par le bucket) — la sortie est toujours du JPEG, ce qui simplifie
// l'extension de fichier en aval.
export async function compressImage(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(
    1,
    MAX_DIMENSION / Math.max(bitmap.width, bitmap.height)
  );
  const width = Math.round(bitmap.width * scale);
  const height = Math.round(bitmap.height * scale);

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("Canvas 2D non disponible");
  ctx.drawImage(bitmap, 0, 0, width, height);
  bitmap.close();

  return new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (blob) =>
        blob ? resolve(blob) : reject(new Error("Échec de la compression de l'image")),
      "image/jpeg",
      JPEG_QUALITY
    );
  });
}

// Empreinte calculée sur le Blob compressé (les octets qui partiront
// réellement sur le réseau), jamais sur le fichier d'origine.
export async function hashBlob(blob: Blob): Promise<string> {
  const buffer = await blob.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// Chemin de stockage, généré côté client AVANT l'envoi direct au bucket
// (voir Module 6) : {organization_id}/{inspection_id}/{inspection_item_id}/{uuid}.jpg
export function buildInspectionPhotoPath(
  organizationId: string,
  inspectionId: string,
  inspectionItemId: string
): string {
  return `${organizationId}/${inspectionId}/${inspectionItemId}/${crypto.randomUUID()}.jpg`;
}

// Chemin à 2 niveaux (pas de notion d'"item" côté maintenance, contrairement
// aux états des lieux) : {organization_id}/{maintenance_ticket_id}/{uuid}.jpg
// — voir supabase/migrations/20260805160000_module7_maintenance_tickets.sql.
export function buildMaintenanceTicketPhotoPath(
  organizationId: string,
  maintenanceTicketId: string
): string {
  return `${organizationId}/${maintenanceTicketId}/${crypto.randomUUID()}.jpg`;
}
