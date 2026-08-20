import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Link, redirect } from "@/i18n/navigation";
import { getCurrentTenant } from "@/data/session";
import {
  getMyMaintenanceTicket,
  getMaintenanceTicketPhotos,
  getSignedMaintenanceTicketPhotoUrls,
} from "@/data/maintenance";
import { formatDateTime } from "@/lib/format-date";
import { TenantTicketEditForm } from "@/components/maintenance/tenant-ticket-edit-form";
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

export default async function TenantMaintenanceTicketPage({
  params,
}: PageProps<"/[locale]/tenant/maintenance/[ticketId]">) {
  const { locale, ticketId } = await params;

  // Symétrique du reste du portail tenant (voir tenant/layout.tsx) : une
  // session locataire est déjà garantie ici, mais getCurrentTenant() est
  // revérifié dans chaque action — pas supposé acquis du seul fait que le
  // layout parent l'a déjà vérifié.
  const tenant = await getCurrentTenant();
  if (!tenant) {
    redirect({ href: "/login", locale });
    return null;
  }

  // Appartenance revérifiée explicitement (filtre reported_by_tenant_id
  // dans la requête, pas seulement RLS) — voir data/maintenance.ts
  // getMyMaintenanceTicket().
  const ticket = await getMyMaintenanceTicket(ticketId, tenant.id);
  if (!ticket) notFound();

  const photos = await getMaintenanceTicketPhotos(ticketId);
  const signedUrls = await getSignedMaintenanceTicketPhotoUrls(
    photos.map((photo) => photo.storage_path)
  );

  const t = await getTranslations("maintenance");

  // Verrou locataire (Module 7b) : dès que status <> 'signale', PAS la
  // fenêtre resolu/ferme du staff (components/maintenance/ticket-photo-gallery.tsx
  // par défaut, réutilisée telle quelle côté staff).
  const locked = ticket.status !== "signale";

  return (
    <div className="flex flex-col gap-6">
      <Link href="/tenant/maintenance" className="text-sm text-muted-foreground hover:underline">
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
          {ticket.organizations && (
            <p className="text-muted-foreground">{ticket.organizations.name}</p>
          )}
          <p className="text-muted-foreground">
            {t("createdAt")}: {ticket.created_at.slice(0, 10)}
          </p>
          {ticket.resolved_at && (
            <p className="text-muted-foreground">
              {t("resolvedAt", { date: formatDateTime(ticket.resolved_at, locale) })}
            </p>
          )}
        </CardContent>
      </Card>

      <TenantTicketEditForm ticket={ticket} />

      <TicketPhotoGallery
        organizationId={ticket.organization_id}
        ticketId={ticket.id}
        photos={photos.map((photo) => ({
          id: photo.id,
          storage_path: photo.storage_path,
          url: signedUrls[photo.storage_path] ?? null,
          uploaded_at: photo.uploaded_at,
        }))}
        canUpload
        canDelete
        locked={locked}
        lockedMessage={t("tenantPhotosLockedMessage")}
      />
    </div>
  );
}
