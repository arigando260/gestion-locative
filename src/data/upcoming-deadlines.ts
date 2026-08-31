import "server-only";
import { getLeasesWithUpcomingEndDate } from "@/data/lease-closure";
import { getSchedulesDueThisWeek } from "@/data/schedules";
import { getLeasesWithPendingDepositRefund } from "@/data/deposits";

// Regroupe les 3 sources de "À venir" (baux à échéance, loyers dus, garanties
// à restituer) en un seul point d'entrée -- réutilisé par le badge sidebar
// "Échéances" ET par /dashboard/echeances, jamais 3 appels dupliqués à des
// endroits différents. Seuils par défaut de chaque source (30j / 7j / toutes),
// jamais paramétrés ici : le badge sidebar doit toujours refléter les mêmes
// seuils par défaut que la carte "À venir" du tableau de bord.
export async function getUpcomingDeadlinesCount(organizationId: string): Promise<number> {
  const [upcomingEndLeases, dueThisWeek, pendingDepositRefunds] = await Promise.all([
    getLeasesWithUpcomingEndDate(organizationId),
    getSchedulesDueThisWeek(organizationId),
    getLeasesWithPendingDepositRefund(organizationId),
  ]);
  return upcomingEndLeases.length + dueThisWeek.length + pendingDepositRefunds.length;
}
