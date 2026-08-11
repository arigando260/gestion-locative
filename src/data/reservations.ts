import "server-only";
import { createClient } from "@/lib/supabase/server";
import type { Tables, TablesInsert } from "@/lib/supabase/database.types";

export type Reservation = Tables<"reservations">;
export type ReservationWithProperty = Reservation & {
  properties: { name: string; address: string } | null;
};

export async function getReservations(): Promise<ReservationWithProperty[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("reservations")
    .select("*, properties(name, address)")
    .order("check_in_date", { ascending: false })
    .returns<ReservationWithProperty[]>();

  if (error) throw error;
  return data;
}

export async function getReservation(
  id: string
): Promise<Reservation | null> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("reservations")
    .select("*")
    .eq("id", id)
    .maybeSingle();

  if (error) throw error;
  return data;
}

// total_amount n'est calculé par aucun trigger côté base (Module 4) : c'est
// à l'appelant (Server Action) de le calculer à partir des dates et du tarif
// nuitée avant d'appeler cette fonction. turnover_buffer_days est de toute
// façon écrasé par trigger, inutile de l'envoyer.
export type CreateReservationInput = Pick<
  TablesInsert<"reservations">,
  | "organization_id"
  | "property_id"
  | "tenant_account_id"
  | "check_in_date"
  | "check_out_date"
  | "nightly_rate"
  | "total_amount"
>;

export async function createReservation(input: CreateReservationInput) {
  const supabase = await createClient();
  return supabase.from("reservations").insert(input).select().single();
}
