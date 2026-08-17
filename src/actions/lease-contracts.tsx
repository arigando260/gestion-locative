"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { getCurrentProfile, getCurrentTenant } from "@/data/session";
import {
  getLeaseContractByLeaseId,
  getLeaseContractRenderData,
  getSignedLeaseContractUrl,
  createLeaseContractRecord,
  approveLeaseContract,
} from "@/data/lease-contracts";
import { createClient } from "@/lib/supabase/server";
import { renderToBuffer } from "@react-pdf/renderer";
import { LeaseContractDocument } from "@/lib/pdf/lease-contract-document";
import { toUserMessage } from "@/lib/errors";
import { getTranslations } from "next-intl/server";
import type { ActionState } from "./properties";
import type { DocumentUrlResult } from "./payment-receipts";

function capitalize(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

// Partagée staff/locataire : les deux peuvent déclencher la première
// génération (RLS lease_contracts_insert, Module 10, l'autorise pour l'un
// comme pour l'autre) ; ensuite, sert directement l'URL signée existante,
// jamais de régénération (un seul contrat par bail, storage_path unique
// une fois posé). Même structure que getOrGeneratePaymentReceiptUrlAction
// (Module 9), généralisée aux deux identités plutôt que dupliquée en deux
// fonctions quasi identiques.
export async function getOrGenerateLeaseContractUrlAction(
  leaseId: string
): Promise<DocumentUrlResult> {
  const profile = await getCurrentProfile();
  const tenant = profile ? null : await getCurrentTenant();
  if (!profile && !tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const existing = await getLeaseContractByLeaseId(leaseId);
  if (existing) {
    try {
      const url = await getSignedLeaseContractUrl(existing.storage_path);
      return { success: true, url };
    } catch {
      return { success: false, message: "Impossible de générer le lien de téléchargement." };
    }
  }

  const renderData = await getLeaseContractRenderData(leaseId);
  if (!renderData) {
    return { success: false, message: "Bail introuvable." };
  }

  const t = await getTranslations("leases");
  const contractId = randomUUID();

  const buffer = await renderToBuffer(
    <LeaseContractDocument
      data={{
        organization: renderData.organization,
        tenantName: renderData.tenantName,
        propertyLabel: renderData.propertyLabel,
        propertyAddress: renderData.propertyAddress,
        contractReference: contractId,
        issuedDate: new Date().toISOString().slice(0, 10),
        startDate: renderData.startDate,
        endDate: renderData.endDate,
        rentAmount: String(renderData.rentAmount),
        paymentFrequencyLabel: t(`frequency${capitalize(renderData.paymentFrequency)}`),
        securityDepositAmount: String(renderData.securityDepositAmount),
        utilityDepositAmount:
          renderData.utilityDepositAmount !== null ? String(renderData.utilityDepositAmount) : null,
        specialTerms: renderData.specialTerms,
      }}
    />
  );

  // Chemin {organization_id}/{lease_id}/{uuid}.pdf : lease_id (pas
  // contractId) est le segment comparé par la policy Storage
  // (lease_contracts_storage_*, Module 10), puisque lease_contracts.lease_id
  // est unique — un seul contrat possible par bail.
  const storagePath = `${renderData.organizationId}/${leaseId}/${randomUUID()}.pdf`;
  const supabase = await createClient();
  const { error: uploadError } = await supabase.storage
    .from("lease-contracts")
    .upload(storagePath, buffer, { contentType: "application/pdf" });

  // Erreur Storage, pas Postgrest : voir même remarque dans
  // actions/payment-receipts.tsx.
  if (uploadError) {
    return { success: false, message: "Échec de la génération du contrat. Réessayez." };
  }

  const { error: insertError } = await createLeaseContractRecord({
    organization_id: renderData.organizationId,
    lease_id: leaseId,
    storage_path: storagePath,
  });

  if (insertError) {
    return { success: false, message: await toUserMessage(insertError) };
  }

  revalidatePath(`/leases/${leaseId}`);
  revalidatePath(`/tenant/leases/${leaseId}`);

  try {
    const url = await getSignedLeaseContractUrl(storagePath);
    return { success: true, url };
  } catch {
    return { success: false, message: "Impossible de générer le lien de téléchargement." };
  }
}

// Locataire uniquement : approuve son propre contrat. La légitimité réelle
// (dépôts complets, bail encore brouillon) est revérifiée server-side par
// le trigger security definer (private.activate_lease_on_contract_approval,
// Module 10) — l'éventuel filtrage d'affichage du bouton côté écran n'est
// qu'une aide à l'ergonomie, jamais la vraie autorisation.
export async function approveLeaseContractAction(
  _prevState: ActionState,
  formData: FormData
): Promise<ActionState> {
  const tenant = await getCurrentTenant();
  if (!tenant) {
    return { success: false, message: "Session expirée, reconnectez-vous." };
  }

  const leaseId = String(formData.get("lease_id") ?? "");
  if (!leaseId) {
    return { success: false, message: "Bail introuvable." };
  }

  const contract = await getLeaseContractByLeaseId(leaseId);
  if (!contract) {
    return { success: false, message: "Consultez d'abord votre contrat avant de l'approuver." };
  }

  const { error } = await approveLeaseContract(contract.id);
  if (error) {
    return { success: false, message: await toUserMessage(error) };
  }

  revalidatePath(`/tenant/leases/${leaseId}`);
  revalidatePath(`/leases/${leaseId}`);
  const t = await getTranslations("leases");
  return { success: true, message: t("contractApproved") };
}
