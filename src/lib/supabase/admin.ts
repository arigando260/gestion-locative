import "server-only";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

// Client service_role : bypass RLS. Ne jamais importer depuis un Client
// Component ni depuis une route exposée publiquement. Réservé au script de
// bootstrap et, plus tard, au flux d'invitation serveur.
export function createAdminClient() {
  return createSupabaseClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
