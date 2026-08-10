# Architecture applicative

Ce document fixe les conventions établies pour la tranche verticale bien → bail → échéances → paiement, à suivre pour tous les modules suivants.

## Structure des dossiers

```
src/
  app/[locale]/          Pages (App Router, segment de routage i18n)
  components/ui/         Primitives shadcn/ui (générées, jamais éditées à la main)
  components/<feature>/  Composants composés par fonctionnalité
  data/                  Data Access Layer — server-only, lecture ET écriture
  actions/               Server Actions ("use server") — fines, délèguent à data/*
  lib/                   Clients Supabase, types générés, utilitaires, gestion d'erreurs
  i18n/                  Configuration next-intl, dictionnaires fr/en
```

Principe : organisation **par type technique** au premier niveau (`data/`, `actions/`, `components/`), **par fonctionnalité** à l'intérieur.

## Accès aux données

- **Lecture** : les composants serveur importent directement des fonctions de `data/*.ts` (`import 'server-only'`), qui utilisent le client Supabase **SSR** (cookies de session). RLS s'applique pleinement — `data/` centralise la forme des requêtes, ce n'est **pas** une couche d'autorisation supplémentaire.
- **Écriture** : Server Actions fines dans `actions/*.ts`, qui délèguent à `data/*.ts` puis appellent `revalidatePath`.
- Le client `service_role` (`lib/supabase/admin.ts`) ne doit **jamais** apparaître dans `data/` ni dans un composant — réservé aux scripts d'administration.

## Permissions à l'écran

La matrice rôle × ressource × action (Module 1) est exposée par la vue `public.my_permissions` (voir `supabase/migrations/20260805130000_my_permissions_view.sql`) : une seule définition de la requête côté base, lue telle quelle côté front via `data/permissions.ts`. Ne jamais reconstruire cette jointure côté TypeScript — si le modèle de permissions évolue, un seul endroit à ajuster.

**Un contrôle de permission à l'écran est une aide à l'ergonomie, jamais la sécurité elle-même.** Même si un bouton apparaissait par erreur, la policy RLS correspondante refuserait quand même l'écriture. RLS fait autorité ; l'affichage ne fait que la refléter.

## Erreurs base de données → utilisateur

Le code d'erreur Postgres distingue deux catégories :
- **`P0001`** (`RAISE EXCEPTION` sans code explicite) : un message métier qu'on a nous-mêmes rédigé en français dans un trigger — affiché tel quel à l'utilisateur, sans traduction.
- **Tout autre code** (`23505`, `23503`, `42501`, ...) : une contrainte/erreur technique brute, jamais montrée telle quelle — un message générique français y correspond dans `lib/errors.ts`.

Vérifié empiriquement : `supabase-js` expose `error.code` (SQLSTATE) et `error.details` (le champ `DETAIL` de `RAISE EXCEPTION ... USING DETAIL = '...'`) séparément du `message`.

### Convention pour toute NOUVELLE exception (à partir de ce jour)

Chaque `RAISE EXCEPTION` écrit à partir de maintenant doit porter, en plus de son message français, un **slug stable et machine-lisible** dans le champ `DETAIL` :

```sql
raise exception 'Message métier en français, inchangé'
  using detail = '<domaine>.<sujet>.<raison>', errcode = 'P0001';
```

Convention de nommage du slug : minuscules, séparé par des points, stable dans le temps (ne pas le renommer une fois posé — le front peut s'y accrocher pour un comportement spécifique, ex: proposer un lien direct vers l'action corrective). Exemples : `lease.damage_imputation.missing_entry_inspection`, `property_type.collision.global_code`.

`errcode = 'P0001'` est explicite ici pour rester cohérent avec le comportement par défaut de `RAISE EXCEPTION` (déjà `P0001` sans le préciser) — pas nécessaire techniquement, mais rend l'intention visible dans le code source sans avoir à se souvenir du défaut.

**Portée de cette convention** : uniquement les nouvelles exceptions. Les ~40 exceptions déjà écrites dans les Modules 1 à 6d restent en l'état ; elles seront reprises progressivement au fil des modules qui les touchent, pas en une passe dédiée. La dette est plafonnée à son niveau actuel, pas amenée à grandir.

**Limite connue acceptée** : les messages métier restent en français quel que soit le paramètre de langue de l'utilisateur (ils sont écrits en dur dans le SQL). Seuls les messages génériques de `lib/errors.ts` et le reste de l'interface sont bilingues. Corriger ça pour de bon demanderait de faire porter un slug `DETAIL` à chaque exception (existante et future) et de déplacer le texte affiché dans les dictionnaires i18n — hors périmètre de cette tranche.
