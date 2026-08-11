import { getTranslations } from "next-intl/server";
import { getReservations } from "@/data/reservations";
import { ReservationList } from "@/components/reservations/reservation-list";

export default async function ReservationsPage() {
  const reservations = await getReservations();
  const t = await getTranslations("reservations");

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold">{t("title")}</h1>
      <ReservationList reservations={reservations} />
    </div>
  );
}
