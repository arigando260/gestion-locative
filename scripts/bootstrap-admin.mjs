// Script de bootstrap temporaire : crée une organisation + son premier
// compte Admin, sans passer par un flux d'invitation par email.
//
// Utilise la clé service_role (bypass RLS) : ne doit jamais être exposé
// comme route HTTP, uniquement exécuté en local via la CLI.
//
// Usage :
//   node --env-file=.env.local scripts/bootstrap-admin.mjs "<nom org>" <email> <mot de passe>

import { createClient } from "@supabase/supabase-js";

const [, , orgName, email, password] = process.argv;

if (!orgName || !email || !password) {
  console.error(
    'Usage: node --env-file=.env.local scripts/bootstrap-admin.mjs "<nom org>" <email> <mot de passe>'
  );
  process.exit(1);
}

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

function slugify(value) {
  // Slug purement technique (identifiant unique) : pas besoin de
  // translittérer les accents, le suffixe temporel garantit l'unicité.
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

async function main() {
  const slug = `${slugify(orgName)}-${Date.now().toString(36)}`;

  const { data: org, error: orgError } = await supabase
    .from("organizations")
    .insert({ name: orgName, slug })
    .select()
    .single();
  if (orgError) throw orgError;
  console.log(`Organisation créée : ${org.name} (${org.id})`);

  const { data: created, error: userError } =
    await supabase.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        account_type: "internal",
        organization_id: org.id,
        full_name: "Admin",
      },
    });
  if (userError) throw userError;
  console.log(`Utilisateur auth créé : ${created.user.id}`);

  // Le trigger handle_new_user a déjà créé la ligne profiles.
  // Le trigger seed_default_roles_for_org a déjà créé le rôle "admin".
  const { data: adminRole, error: roleError } = await supabase
    .from("roles")
    .select("id")
    .eq("organization_id", org.id)
    .eq("code", "admin")
    .single();
  if (roleError) throw roleError;

  const { error: userRoleError } = await supabase
    .from("user_roles")
    .insert({ user_id: created.user.id, role_id: adminRole.id });
  if (userRoleError) throw userRoleError;

  console.log("\nCompte Admin prêt :");
  console.log(`  organisation : ${org.name} (${org.slug})`);
  console.log(`  email        : ${email}`);
}

main().catch((err) => {
  console.error("Échec du bootstrap :", err.message ?? err);
  process.exit(1);
});
