// Script ponctuel : crée un compte locataire de test, rattaché à
// l'organisation active trouvée en base, pour vérifier manuellement le
// portail locataire (Module 7 maintenance notamment).
//
// PAS destiné à être committé — script jetable, à supprimer après usage
// (voir ARCHITECTURE.md, section "à purger avant toute mise en production").
//
// Utilise uniquement supabase.auth.admin.createUser() (clé service_role,
// jamais exposée côté client) : aucune insertion manuelle dans auth.users.
// Le trigger handle_new_user (Module 1b) crée ensuite lui-même la ligne
// tenant_accounts + l'adhésion active à l'organisation.
//
// Usage :
//   node --env-file=.env.local scripts/create-test-tenant.mjs

import { createClient } from "@supabase/supabase-js";

const TENANT_EMAIL = "locataire.test1@example.com";
const TENANT_PASSWORD = "LocataireTest2026!";
const TENANT_FULL_NAME = "Locataire Test";

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
  // "Organisation active" : is_active = true, la plus ancienne si plusieurs
  // existent (Agence Demo, Org Test 6d...) — affichée explicitement pour
  // vérification, pas une hypothèse silencieuse.
  const { data: org, error: orgError } = await supabase
    .from("organizations")
    .select("id, name, slug")
    .eq("is_active", true)
    .order("created_at", { ascending: true })
    .limit(1)
    .single();
  if (orgError) throw orgError;
  console.log(`Organisation utilisée : ${org.name} (${org.slug}, ${org.id})`);

  const { data: created, error: userError } = await supabase.auth.admin.createUser({
    email: TENANT_EMAIL,
    password: TENANT_PASSWORD,
    email_confirm: true,
    user_metadata: {
      account_type: "tenant",
      organization_id: org.id,
      full_name: TENANT_FULL_NAME,
    },
  });
  if (userError) throw userError;
  console.log(`Utilisateur auth créé : ${created.user.id}`);

  // Vérifie que le trigger handle_new_user a bien créé la ligne
  // tenant_accounts (Module 1b) — jamais supposé acquis du seul fait que
  // createUser() a réussi.
  const { data: tenantAccount, error: tenantError } = await supabase
    .from("tenant_accounts")
    .select("id, email, full_name")
    .eq("id", created.user.id)
    .single();
  if (tenantError) {
    throw new Error(
      `tenant_accounts introuvable pour ${created.user.id} — le trigger handle_new_user a-t-il tourné ? (${tenantError.message})`
    );
  }

  console.log("\nCompte locataire de test prêt :");
  console.log(`  tenant_accounts.id : ${tenantAccount.id}`);
  console.log(`  email              : ${tenantAccount.email}`);
  console.log(`  full_name          : ${tenantAccount.full_name}`);
  console.log(`  organisation       : ${org.name}`);
  console.log(`\n  Identifiants de connexion :`);
  console.log(`    email    : ${TENANT_EMAIL}`);
  console.log(`    password : ${TENANT_PASSWORD}`);
}

main().catch((err) => {
  console.error("Échec de la création du compte locataire de test :", err.message ?? err);
  process.exit(1);
});
