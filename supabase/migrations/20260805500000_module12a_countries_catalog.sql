-- ============================================================================
-- MODULE 12a — Catalogue des pays (Phase 2, volet 2 : inscription
-- self-service).
--
-- Support de la décision "adresse structurée : Pays (hérité de
-- l'organisation, modifiable par bien) -> Ville -> Quartier -> Complément".
-- Table de référence modifiable, même patron que subscription_plans
-- (Module 11) et permissions (Module 1) : catalogue, pas une liste codée
-- en dur dans l'application.
--
-- Seed de démarrage : Bénin (marché principal) + voisins régionaux
-- immédiats. Liste extensible par simple INSERT, aucune migration requise
-- pour ajouter un pays plus tard.
-- ============================================================================

create table public.countries (
  code       text primary key,  -- ISO 3166-1 alpha-2
  name       text not null,
  is_active  boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_countries_updated_at
  before update on public.countries
  for each row execute function private.set_updated_at();

insert into public.countries (code, name, sort_order) values
  ('BJ', 'Bénin',          1),
  ('BF', 'Burkina Faso',   2),
  ('CI', 'Côte d''Ivoire', 3),
  ('GH', 'Ghana',          4),
  ('NE', 'Niger',          5),
  ('NG', 'Nigeria',        6),
  ('TG', 'Togo',           7);

alter table public.countries enable row level security;

-- Catalogue plateforme, pas par organisation : lecture ouverte à tout
-- utilisateur authentifié, aucune écriture possible via RLS — même patron
-- que public.permissions et public.subscription_plans.
create policy countries_select on public.countries
  for select
  to authenticated
  using (true);
