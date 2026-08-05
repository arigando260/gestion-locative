import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import LogoutButton from "./logout-button";

export default async function DashboardPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Ces requêtes passent par le client "anon" avec le JWT de l'utilisateur :
  // le RLS s'applique donc pleinement, comme depuis le navigateur.
  const { data: organizations, error: organizationsError } = await supabase
    .from("organizations")
    .select("id, name, slug");

  const { data: profile } = await supabase
    .from("profiles")
    .select("email, full_name")
    .eq("id", user.id)
    .single();

  const { data: userRoles } = await supabase
    .from("user_roles")
    .select("roles(name, code)")
    .eq("user_id", user.id)
    .returns<{ roles: { name: string; code: string } | null }[]>();

  const roleNames =
    userRoles
      ?.map((row) => row.roles?.name)
      .filter((name): name is string => Boolean(name))
      .join(", ") || "aucun";

  return (
    <main className="mx-auto max-w-2xl p-6">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Tableau de bord</h1>
        <LogoutButton />
      </div>

      <section className="mt-8">
        <h2 className="font-medium">Mon profil</h2>
        <p className="text-sm text-neutral-600 dark:text-neutral-400">
          {profile?.full_name ?? "(sans nom)"} — {profile?.email ?? user.email}
        </p>
        <p className="text-sm text-neutral-600 dark:text-neutral-400">
          Rôle(s) : {roleNames}
        </p>
      </section>

      <section className="mt-8">
        <h2 className="font-medium">
          Organisations visibles ({organizations?.length ?? 0})
        </h2>
        <p className="text-sm text-neutral-500">
          Preuve d&apos;isolation RLS : cette requête ne peut jamais renvoyer
          que l&apos;organisation de l&apos;utilisateur connecté.
        </p>
        {organizationsError ? (
          <p className="mt-2 text-sm text-red-600">
            Erreur : {organizationsError.message}
          </p>
        ) : (
          <ul className="mt-2 list-disc pl-5 text-sm">
            {organizations?.map((org) => (
              <li key={org.id}>
                {org.name}{" "}
                <span className="text-neutral-400">({org.slug})</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}
