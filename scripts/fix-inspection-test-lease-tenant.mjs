// Script ponctuel : vérifie le tenant_account_id du bail le plus récent sur
// "Bien Test Inspections" et le corrige vers le compte "Locataire Test" créé
// par create-test-tenant.mjs si un autre locataire y est actuellement
// rattaché.
//
// PAS destiné à être committé — script jetable, à supprimer après usage
// (même principe que create-test-tenant.mjs).
//
// Usage :
//   node --env-file=.env.local scripts/fix-inspection-test-lease-tenant.mjs

import { createClient } from "@supabase/supabase-js";

const PROPERTY_NAME = "Bien Test Inspections";
const TARGET_TENANT_ID = "3b14c0d9-5125-47fb-89d2-bf13a33c692d"; // Locataire Test

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceRoleKey) {
  console.error(
    "NEXT_PUBLIC_SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY doivent être définis (ex: --env-file=.env.local)."
  );
  process.exit(1);
}

const supabase = createClient(url, serviceRoleKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  const { data: property, error: propertyError } = await supabase
    .from("properties")
    .select("id, name, organization_id")
    .eq("name", PROPERTY_NAME)
    .maybeSingle();
  if (propertyError) throw propertyError;

  if (!property) {
    console.log(`Aucun bien nommé "${PROPERTY_NAME}" trouvé en base.`);
    return;
  }

  const { data: lease, error: leaseError } = await supabase
    .from("leases")
    .select("id, tenant_account_id, status, created_at")
    .eq("property_id", property.id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (leaseError) throw leaseError;

  if (!lease) {
    console.log(
      `RÉSULTAT : aucun bail trouvé sur "${PROPERTY_NAME}" (id ${property.id}). Il faudra le recréer depuis l'écran.`
    );
    return;
  }

  console.log(
    `Bail le plus récent trouvé sur "${PROPERTY_NAME}" : ${lease.id} (statut ${lease.status}, créé le ${lease.created_at}).`
  );
  console.log(`  tenant_account_id actuel : ${lease.tenant_account_id}`);

  if (lease.tenant_account_id === TARGET_TENANT_ID) {
    console.log(
      `RÉSULTAT : ce bail est déjà rattaché à Locataire Test (${TARGET_TENANT_ID}). Rien à faire.`
    );
    return;
  }

  const { data: currentTenant } = await supabase
    .from("tenant_accounts")
    .select("full_name, email")
    .eq("id", lease.tenant_account_id)
    .maybeSingle();
  console.log(
    `  locataire actuel : ${currentTenant?.full_name ?? "(inconnu)"} <${currentTenant?.email ?? lease.tenant_account_id}>`
  );

  const { data: updated, error: updateError } = await supabase
    .from("leases")
    .update({ tenant_account_id: TARGET_TENANT_ID })
    .eq("id", lease.id)
    .select("id, tenant_account_id")
    .single();
  if (updateError) throw updateError;

  console.log(
    `RÉSULTAT : bail ${updated.id} corrigé — tenant_account_id passé de ${lease.tenant_account_id} à ${updated.tenant_account_id} (Locataire Test).`
  );
}

main().catch((err) => {
  console.error("Échec de la vérification/correction :", err.message ?? err);
  process.exit(1);
});
