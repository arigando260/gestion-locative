import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link } from "@/i18n/navigation";
import {
  getMaintenanceTicket,
  getMaintenanceTicketPhotos,
  getSignedMaintenanceTicketPhotoUrls,
  getMaintenanceTicketImputations,
} from "@/data/maintenance";
import { getCurrentUserPermissions, can } from "@/data/permissions";
import { TicketStatusControl } from "@/components/maintenance/ticket-status-control";
import { TicketCostFields } from "@/components/maintenance/ticket-cost-fields";
import { TicketPhotoGallery } from "@/components/maintenance/ticket-photo-gallery";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { MaintenanceTicketPriority, MaintenanceTicketStatus } from "@/data/maintenance";

const STATUS_KEY: Record<MaintenanceTicketStatus, string> = {
  signale: "statusSignale",
  en_cours: "statusEnCours",
  resolu: "statusResolu",
  ferme: "statusFerme",
};
const PRIORITY_KEY: Record<MaintenanceTicketPriority, string> = {
  basse: "priorityBasse",
  normale: "priorityNormale",
  haute: "priorityHaute",
  urgente: "priorityUrgente",
};

export default async function MaintenanceTicketPage({
  params,
}: PageProps<"/[locale]/maintenance/[ticketId]">) {
  const { ticketId } = await params;
  const [ticket, permissions] = await Promise.all([
    getMaintenanceTicket(ticketId),
    getCurrentUserPermissions(),
  ]);

  if (!ticket) notFound();

  const [photos, imputations] = await Promise.all([
    getMaintenanceTicketPhotos(ticketId),
    getMaintenanceTicketImputations(ticketId),
  ]);
  const signedUrls = await getSignedMaintenanceTicketPhotoUrls(
    photos.map((photo) => photo.storage_path)
  );

  const t = await getTranslations("maintenance");

  // Même verrou que côté locataire (Module 7b), version staff : bloqué
  // uniquement à resolu/ferme (trigger prevent_maintenance_ticket_photo_when_closed).
  const photosLocked = ticket.status === "resolu" || ticket.status === "ferme";
  const canUpdate = can(permissions, "maintenance_tickets", "update");
  const canDelete = can(permissions, "maintenance_tickets", "delete");

  return (
    <div className="flex flex-col gap-6">
      <Link href="/maintenance" className="text-sm text-muted-foreground hover:underline">
        ← {t("title")}
      </Link>

      <Card className="max-w-md">
        <CardHeader className="flex flex-row items-center justify-between gap-2">
          <CardTitle>{ticket.title}</CardTitle>
          <div className="flex gap-2">
            <Badge variant="secondary">{t(PRIORITY_KEY[ticket.priority])}</Badge>
            <Badge>{t(STATUS_KEY[ticket.status])}</Badge>
          </div>
        </CardHeader>
        <CardContent className="flex flex-col gap-2 text-sm">
          {ticket.properties && (
            <p className="text-muted-foreground">
              {ticket.properties.name} — {ticket.properties.address}
            </p>
          )}
          {ticket.description && <p>{ticket.description}</p>}
          <p className="text-muted-foreground">
            {t("createdAt")}: {ticket.created_at.slice(0, 10)}
          </p>
        </CardContent>
      </Card>

      {canUpdate && <TicketStatusControl ticketId={ticket.id} status={ticket.status} />}

      {canUpdate && (
        <div className="flex flex-col gap-3">
          <h2 className="text-lg font-semibold">{t("costSectionTitle")}</h2>
          <TicketCostFields ticketId={ticket.id} ticket={ticket} imputations={imputations} />
        </div>
      )}

      <TicketPhotoGallery
        organizationId={ticket.organization_id}
        ticketId={ticket.id}
        photos={photos.map((photo) => ({
          id: photo.id,
          storage_path: photo.storage_path,
          url: signedUrls[photo.storage_path] ?? null,
        }))}
        canUpload={canUpdate}
        canDelete={canDelete}
        locked={photosLocked}
      />
    </div>
  );
}
