# Architecture applicative

## RÈGLE ABSOLUE — Séparation dev/prod

**`ctfdwccijkdomvgzjlcr` est et reste le projet DEV.** La production est un
projet Supabase distinct, vierge à sa création, peuplé uniquement par
l'usage réel une fois lancée. Cette séparation n'est pas négociable au cas
par cas — elle protège prod contre exactement le type de dérive qui a rendu
ce projet DEV impropre à devenir prod (mouvements financiers de test dans
`deposit_ledger`, append-only, non purgeables par design).

- **Seules les migrations (`supabase/migrations/*.sql`) s'appliquent sur
  l'URL de production.** Aucun script de données de test, de bootstrap
  manuel, de correctif ad hoc écrit à la main, ou de vérification empirique
  ne doit jamais cibler le `SUPABASE_DB_URL` de prod.
- **Prod se peuple uniquement par l'usage réel** : comptes créés via les
  flux normaux de l'application (invitation, inscription), jamais par un
  script type `bootstrap-admin.mjs` ou une insertion directe pointée sur
  prod.
- Toute vérification empirique en navigateur, tout compte de démonstration,
  tout script `scripts/*.mjs` : dev uniquement, sans exception.
- Avant d'exécuter un script ou une commande contre une base, vérifier
  explicitement quel fichier `.env*` est chargé — voir convention de
  nommage ci-dessous.

### Convention de nommage des fichiers `.env`

- **`.env.local`** — réservé à DEV, sans exception. C'est le fichier chargé
  automatiquement par `next dev` / `next build`, et par défaut par tous les
  scripts existants (`node --env-file=.env.local ...`). Ne doit jamais
  contenir de credentials prod.
- **`.env.prod-admin.local`** (créé seulement une fois prod provisionnée) —
  credentials prod (`SUPABASE_DB_URL`, `SUPABASE_ACCESS_TOKEN`), réservé aux
  scripts d'application de migration. Nom délibérément en dehors des
  conventions `.env.production*` de Next.js : Next ne le charge jamais
  automatiquement, donc aucun risque qu'une commande `next dev` ou
  `next build` locale l'utilise par erreur. Toute commande qui cible prod
  doit le référencer explicitement (`node --env-file=.env.prod-admin.local
  ...`) — jamais implicitement, jamais par défaut.

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

## À purger avant toute mise en production réelle

Ce projet s'est construit avec des comptes et mots de passe de démonstration créés au fil des modules, réutilisés pour chaque vérification empirique en navigateur. Rien de tout ça ne doit survivre au premier déploiement réel — liste tenue à jour à chaque fois qu'un nouvel élément de ce type apparaît, pour ne pas avoir à la reconstituer de mémoire le jour du lancement :

- **`admin@demo.local`** (compte interne "Agence Demo") et son mot de passe, utilisés pour toutes les vérifications gestionnaire depuis le Module 1. Mot de passe réinitialisé via l'API Admin le 2026-08-17 pour vérifier en navigateur le nouveau champ de durée de `lease-form.tsx` (le mot de passe précédent n'est pas récupérable) — mot de passe actuel : `VerifLeaseForm2026!`.
- **Mot de passe connu posé sur un compte locataire existant** (`tenant-3c-...@demo.local`, réinitialisé via l'API Admin pour tester le portail locataire, tranche états des lieux/cautions/réservations) — le mot de passe d'origine (inconnu, généré à la création du compte) a été écrasé et n'est pas récupérable ; ce compte doit être désactivé ou son mot de passe régénéré avant production.
- **Organisation "Org Test 6d"** (Module 6d) et **"Agence Demo"** elle-même : organisations de démonstration, pas des clientes réelles.
- Les **4 biens protégés par un état des lieux finalisé** (Bien Gap Test, Bien M6 Gap ×2, Bien M6 Retest — voir historique de nettoyage) : non supprimables tant qu'un vrai mécanisme d'archivage n'existe pas (cf. décision Module 6d sur la désactivation d'organisation — on archive, on n'efface pas de donnée contractuelle). À traiter par ce futur mécanisme, pas par une suppression forcée.
- Tout bien/bail/réservation dont le nom contient "Test" (ex: "Bien Test Inspections", "Bungalow Test Réservations", "Bien Test 10f UI") : artefacts de vérification manuelle, à nettoyer avant production comme les précédents (voir historique de nettoyage des Modules 5b/6).
- **`tenant-10f-ui@example.com`** (compte locataire créé pour vérifier en navigateur le parcours d'approbation de contrat, Module 10f UI) et son mot de passe `Tenant10fUi2026!`. Le bail associé ("Bien Test 10f UI") est désormais actif avec un historique de dépôt et un contrat approuvé — non supprimable (`prevent_lease_delete_with_deposit_history`, `trg_lease_contracts_prevent_delete`), même situation que les biens protégés par état des lieux ci-dessus.
- **Bien "actif-end-date"** (nom ne contenant pas "Test", donc hors de la règle générique ci-dessus) : bail réutilisé pour de nombreuses vérifications navigateur (Module 10g à 10k, RefundForm). Porte désormais une imputation "Dégâts" de test (20 000, motif "Test diagnostic remboursement", 2026-08-20) dans `deposit_ledger` — append-only, non réversible — et une valeur de `keys_returned_at` (2026-08-15) ajustée manuellement pour satisfaire la fenêtre de 7 jours du trigger d'imputation, sans rapport avec un événement réel. Non supprimable pour les mêmes raisons que les biens ci-dessus (historique de dépôt).
- **Bien "Mira"** (nom ne contenant pas "Test") : bail `termine` sans aucun solde de caution réel restant (entièrement remboursé lors d'une vérification manuelle) — un dépôt initial de test (`avance_garantie`, 15 000, sans imputation ni remboursement associé) y a été ajouté par écriture directe le 2026-08-20 pour vérifier en navigateur le bandeau "solde de caution à rembourser" (fiche bail) et l'alerte dashboard correspondante. `deposit_ledger` append-only : non réversible, à traiter avec le reste de ce bail lors de la purge.
