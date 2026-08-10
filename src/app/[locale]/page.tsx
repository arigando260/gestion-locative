import { createClient } from "@/lib/supabase/server";
import { redirect } from "@/i18n/navigation";

export default async function Home({ params }: PageProps<"/[locale]">) {
  const { locale } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  redirect({ href: user ? "/dashboard" : "/login", locale });
}
