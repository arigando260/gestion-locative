import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import createMiddleware from "next-intl/middleware";
import { routing } from "@/i18n/routing";

// Next.js 16 renomme middleware.ts -> proxy.ts (fonctionnalité identique).
// Combine deux responsabilités dans cet ordre :
//   1. next-intl : détecte/redirige vers le bon segment de locale.
//   2. Supabase : rafraîchit la session et protège les pages authentifiées.
// L'ordre compte : la garde d'authentification doit lire un pathname déjà
// débarrassé du préfixe de locale pour comparer proprement à "/dashboard".
const handleIntl = createMiddleware(routing);

export async function proxy(request: NextRequest) {
  const intlResponse = handleIntl(request);

  // next-intl a déjà décidé de rediriger (ex: / -> /fr/) : on ne va pas plus
  // loin, la garde d'authentification s'appliquera sur la requête suivante.
  if (intlResponse.headers.get("location")) {
    return intlResponse;
  }

  let response = intlResponse;

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  // getUser() revalide le JWT auprès de Supabase Auth (contrairement à
  // getSession() qui ne fait que lire le cookie local sans vérification).
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Retire le préfixe de locale (/fr, /en) pour comparer le chemin applicatif.
  const { pathname } = request.nextUrl;
  const pathnameWithoutLocale =
    pathname.replace(new RegExp(`^/(${routing.locales.join("|")})`), "") ||
    "/";

  const locale =
    routing.locales.find((l) => pathname.startsWith(`/${l}`)) ??
    routing.defaultLocale;

  // Toute page authentifiée vit sous (dashboard) ; seule /login (et / qui
  // redirige lui-même) est publique. Bloquer par défaut plutôt qu'énumérer
  // chaque route protégée évite d'oublier de garder une nouvelle page.
  const isPublicPath =
    pathnameWithoutLocale === "/" || pathnameWithoutLocale === "/login";

  if (!user && !isPublicPath) {
    const url = request.nextUrl.clone();
    url.pathname = `/${locale}/login`;
    return NextResponse.redirect(url);
  }

  if (user && pathnameWithoutLocale === "/login") {
    const url = request.nextUrl.clone();
    url.pathname = `/${locale}/dashboard`;
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
