"use server";

import { revalidatePath } from "next/cache";
import { generateSchedulesForLease } from "@/data/schedules";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";

export async function generateSchedulesAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const leaseId = String(formData.get("lease_id") ?? "");
  if (!leaseId) return { success: false, message: "Bail introuvable." };

  const { data: count, error } = await generateSchedulesForLease(leaseId);

  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/leases/${leaseId}`);

  const t = await getTranslations("schedules");
  return { success: true, message: t("generateSuccess", { count: count ?? 0 }) };
}
