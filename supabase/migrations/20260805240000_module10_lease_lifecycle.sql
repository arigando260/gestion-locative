-- ============================================================================
-- MODULE 10 — CYCLE DE VIE DU BAIL (baux longue durée / meublé simple —
-- les réservations courte durée restent hors périmètre, traitées séparément).
--
-- Trois volets liés, un seul état de statut élargi :
--
--   brouillon --(approbation contrat locataire, dépôts complets)--> actif
--      actif --(Module 8, consensus résiliation, INCHANGÉ)--> resilie
--      actif --(clôture directe : clés + état des lieux de sortie)--> termine
--   resilie --(même clôture : clés + état des lieux de sortie)--> termine
--
-- VOLET A — un bail démarre 'brouillon' (jamais 'actif' dès l'INSERT). Il ne
-- devient 'actif' qu'une fois (1) les dépôts initiaux (avance de garantie +
-- caution eau/électricité si prévue) intégralement versés ET (2) le
-- locataire a approuvé son contrat PDF depuis son portail. C'est cette
-- approbation, et uniquement elle, qui déclenche le passage à 'actif' — et
-- donc, désormais, la génération des échéances (Module 5c ajusté : ne se
-- déclenche plus à l'INSERT, mais à cette transition précise).
--
-- VOLET B — aucun passage automatique/silencieux à 'termine' à l'échéance
-- (decision produit explicite : un bail peut être tacitement reconduit,
-- seul un humain décide). Rien de nouveau à modéliser ici côté base : la
-- vue leases_closure_status (section 5) expose déjà tout ce qu'il faut
-- (end_date, statut) pour que l'écran affiche un bandeau "renouveler /
-- enclencher la clôture" quand end_date approche ou est dépassée — le geste
-- "renouveler" est une simple UPDATE de end_date, déjà couvert par la RLS
-- leases_update existante, rien à ajouter.
--
-- VOLET C — keys_returned_at (Module 6, jusqu'ici inaccessible depuis
-- aucun écran) devient le pivot d'un parcours de clôture unique, commun aux
-- deux origines (résiliation Module 8 validée, OU décision Volet B) : une
-- fois les clés restituées, un état des lieux de sortie FINALISÉ (peu
-- importe son statut de validation locataire — en_attente / valide /
-- conteste / accepte_tacitement, cf. Module 6, n'entre pas en ligne de
-- compte ici) est la seule condition du passage à 'termine', jamais
-- automatique, toujours un clic staff explicite. 'resilie' n'est donc plus
-- un état terminal isolé : il rejoint la même chaîne de clôture que
-- 'actif' — cohérent avec payment_schedules_effective_status (Module 8) qui
-- traite déjà 'resilie' et 'termine' de façon identique (hors_periode). Ce
-- rapprochement est aussi rétroactif sans aucune donnée à corriger : un
-- bail déjà 'resilie' avant ce module rejoint le parcours dès sa première
-- consultation post-déploiement, le délai de 7 jours ne démarrant qu'à la
-- saisie réelle de keys_returned_at, jamais depuis la date de résiliation.
--
-- Toutes les transitions de leases.status sont désormais centralisées dans
-- UN SEUL trigger de garde (section 1.2) — ferme au passage une lacune
-- préexistante : la policy RLS leases_update ne restreignait jusqu'ici ni
-- les colonnes ni les valeurs qu'un profil avec leases:update pouvait
-- écrire ; rien n'empêchait en théorie un UPDATE direct posant
-- status='resilie', court-circuitant le consensus Module 8. Le nouveau
-- trigger ferme cette lacune pour toutes les transitions, pas seulement les
-- deux nouvelles.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. LEASES — nouveau statut 'brouillon', garde-fou générique de transition,
--    message propre à la suppression d'un brouillon avec historique de
--    dépôts.
-- ----------------------------------------------------------------------------

-- 1.1 Statut : 'brouillon' ajouté, devient la valeur par défaut (plus 'actif').

alter table public.leases
  drop constraint leases_status_check;

alter table public.leases
  add constraint leases_status_check
  check (status in ('brouillon', 'actif', 'termine', 'resilie'));

alter table public.leases
  alter column status set default 'brouillon';

comment on column public.leases.status is
  'brouillon (défaut, à la création) -> actif (approbation contrat + dépôts complets, Module 10) -> resilie (Module 8, consensus) OU termine (clôture directe). resilie -> termine également possible (même parcours de clôture : restitution des clés + état des lieux de sortie finalisé, Module 10). Toutes les transitions sont validées par private.validate_lease_status_transition() ci-dessous — jamais une simple contrainte de valeur.';

-- 1.2 Garde-fou générique de transition — SEULE autorité sur les
-- changements de leases.status, qu'ils passent par ce module, par le
-- Module 8 (résiliation), ou par un futur code non encore écrit.
--
-- Transitions autorisées (tout le reste est refusé) :
--
--   INSERT            -> status doit être 'brouillon', aucune autre valeur.
--   x -> x (inchangé)  -> toujours accepté sans autre vérification (no-op).
--   brouillon -> actif -> UNIQUEMENT en cascade (pg_trigger_depth() >= 2)
--                         depuis trg_lease_contracts_activate_lease
--                         (section 3, security definer) : un appel direct
--                         top-level, même avec leases:update, est refusé.
--   actif -> resilie   -> UNIQUEMENT en cascade (pg_trigger_depth() >= 2)
--                         depuis apply_effective_lease_termination
--                         (Module 8, inchangé, security definer) : idem,
--                         un appel direct top-level est refusé.
--   actif -> termine   -> appel direct autorisé (aucune contrainte de
--   resilie -> termine    profondeur : c'est un geste staff délibéré,
--                         jamais un effet de cascade), à condition que
--                         keys_returned_at soit renseigné ET qu'un état des
--                         lieux de sortie finalisé existe pour ce bail.
--
-- pg_trigger_depth() : à l'intérieur d'un trigger déclenché directement par
-- une instruction cliente (top-level), la profondeur vaut 1 ; si CE
-- trigger exécute lui-même une instruction SQL qui déclenche un autre
-- trigger, ce dernier s'exécute à la profondeur 2. C'est l'idiome standard
-- Postgres pour garantir qu'une transition n'est JAMAIS atteignable
-- autrement qu'en effet de bord d'un mécanisme précis — ici, uniquement
-- depuis l'intérieur d'un autre trigger, jamais depuis un UPDATE direct.
create or replace function private.validate_lease_status_transition()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if new.status <> 'brouillon' then
      raise exception 'Un bail est toujours créé au statut brouillon (valeur reçue : %)', new.status
        using detail = 'lease.status.invalid_initial_value', errcode = 'P0001';
    end if;
    return new;
  end if;

  -- TG_OP = 'UPDATE' (ce trigger n'est posé que "of status", voir plus bas :
  -- il ne se déclenche que si status fait partie du SET, même si la
  -- nouvelle valeur est égale à l'ancienne).
  if new.status is not distinct from old.status then
    return new;
  end if;

  if old.status = 'brouillon' and new.status = 'actif' then
    if pg_trigger_depth() < 2 then
      raise exception 'Passage brouillon -> actif impossible en écriture directe : requiert l''approbation du contrat par le locataire'
        using detail = 'lease.status.invalid_transition', errcode = 'P0001';
    end if;
    return new;
  end if;

  if old.status = 'actif' and new.status = 'resilie' then
    if pg_trigger_depth() < 2 then
      raise exception 'Passage actif -> resilie impossible en écriture directe : requiert le consensus de résiliation (Module 8)'
        using detail = 'lease.status.invalid_transition', errcode = 'P0001';
    end if;
    return new;
  end if;

  if old.status in ('actif', 'resilie') and new.status = 'termine' then
    if new.keys_returned_at is null then
      raise exception 'Clôture définitive impossible : la restitution des clés (keys_returned_at) n''est pas encore enregistrée pour ce bail'
        using detail = 'lease.closure.keys_not_returned', errcode = 'P0001';
    end if;

    if not exists (
      select 1 from public.property_inspections pi
      where pi.lease_id = new.id
        and pi.inspection_type = 'sortie'
        and pi.document_status = 'finalise'
    ) then
      raise exception 'Clôture définitive impossible : aucun état des lieux de sortie finalisé n''existe pour ce bail'
        using detail = 'lease.closure.missing_exit_inspection', errcode = 'P0001';
    end if;

    return new;
  end if;

  raise exception 'Transition de statut de bail invalide : % -> %', old.status, new.status
    using detail = 'lease.status.invalid_transition', errcode = 'P0001';
end;
$$;

create trigger trg_leases_validate_status_transition
  before insert or update of status on public.leases
  for each row execute function private.validate_lease_status_transition();

-- 1.3 Suppression d'un bail brouillon : message métier propre plutôt que la
-- violation FK brute (23503) de deposit_ledger_lease_org_fk (ON DELETE
-- RESTRICT, comme TOUTES les FK vers leases dans ce projet — jamais de
-- cascade sur un historique financier). Ne bloque QUE sur un historique de
-- dépôts réel : payment_schedules est structurellement vide tant que le
-- bail n'a jamais été actif (section 3), donc jamais la cause du blocage
-- ici. C'est le mécanisme de refus de contrat décidé : un brouillon sans
-- dépôt versé se supprime proprement ; dès qu'un dépôt existe, la
-- suppression reste bloquée à dessein (remboursement via le mécanisme
-- RefundForm existant, le brouillon reste ensuite inerte en base — hors
-- périmètre de ce module d'ajouter un geste de clôture dédié à ce cas).
create or replace function private.prevent_lease_delete_with_deposit_history()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (select 1 from public.deposit_ledger dl where dl.lease_id = old.id) then
    raise exception 'Suppression impossible : des dépôts ont déjà été enregistrés pour ce bail (historique financier immuable) — remboursez via le suivi des cautions si nécessaire, le bail restera alors inerte'
      using detail = 'lease.delete.has_deposit_history', errcode = 'P0001';
  end if;
  return old;
end;
$$;

create trigger trg_leases_prevent_delete_with_deposit_history
  before delete on public.leases
  for each row execute function private.prevent_lease_delete_with_deposit_history();

-- ----------------------------------------------------------------------------
-- 2. ÉLIGIBILITÉ À L'ACTIVATION — dépôts complets, calculé à la volée à
--    partir de deposit_ledger_balances (Module 5), jamais matérialisé.
--    Fonction SQL simple (pas plpgsql) réutilisée à la fois par la vue de
--    lecture (section 5) et par le trigger d'activation (section 3) — même
--    principe de source unique que private.inspection_effective_validation_status
--    (Module 6).
-- ----------------------------------------------------------------------------

create or replace function private.lease_deposits_complete(p_lease_id uuid)
returns boolean
language sql
stable
as $$
  select
    coalesce(dg.amount_held, 0) >= l.security_deposit_amount
    and (
      l.utility_deposit_amount is null
      or l.utility_deposit_amount = 0
      or coalesce(du.amount_held, 0) >= l.utility_deposit_amount
    )
  from public.leases l
  left join public.deposit_ledger_balances dg
    on dg.lease_id = l.id and dg.deposit_type = 'avance_garantie'
  left join public.deposit_ledger_balances du
    on du.lease_id = l.id and du.deposit_type = 'caution_utilities'
  where l.id = p_lease_id
$$;

comment on function private.lease_deposits_complete is
  'true si les dépôts initiaux requis (avance de garantie, toujours ; caution eau/électricité, uniquement si utility_deposit_amount est renseigné et non nul) ont atteint leur montant convenu sur ce bail. Calculé à la volée depuis deposit_ledger_balances (Module 5), jamais matérialisé.';

-- ----------------------------------------------------------------------------
-- 3. LEASE_CONTRACTS — document PDF du contrat, généré à la demande (staff
--    ou locataire, la première fois que l'un ou l'autre le consulte),
--    stocké et immuable comme payment_receipts/schedule_invoices
--    (Module 9), MAIS avec une seconde transition contrôlée en plus du
--    dépôt du PDF : l'approbation par le locataire (approved_at), qui
--    déclenche l'activation du bail.
-- ----------------------------------------------------------------------------

create table public.lease_contracts (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  -- Un seul contrat par bail : les montants qu'il reflète (security_deposit_amount,
  -- utility_deposit_amount, etc.) sont fixés à la création du bail (Module 3c),
  -- pas de scénario de révision qui justifierait plusieurs versions.
  lease_id        uuid not null unique,
  storage_path    text not null,
  generated_at    timestamptz not null default now(),
  -- NULL tant que le locataire n'a pas approuvé. Posé une seule fois, par le
  -- serveur, jamais avant, jamais modifié ensuite (voir triggers ci-dessous).
  approved_at     timestamptz,

  constraint lease_contracts_lease_org_fk
    foreign key (organization_id, lease_id)
    references public.leases (organization_id, id)
    on delete restrict
);

comment on table public.lease_contracts is
  'Document de contrat de bail (PDF, Storage privé, URL signée — même infrastructure que payment_receipts/schedule_invoices, Module 9). Un seul par bail. approved_at NULL jusqu''à approbation locataire ; ce passage (trigger security definer ci-dessous) est ce qui fait passer leases.status de brouillon à actif.';

create index lease_contracts_organization_id_idx on public.lease_contracts (organization_id);

-- Immuabilité de l'identité et du document ; horodatage d'approbation posé
-- par le serveur uniquement. AUCUNE règle métier ici (dépôts complets) :
-- cette fonction s'exécute sous l'identité de l'appelant (potentiellement
-- le locataire), dont la RLS de lecture sur deposit_ledger_balances n'est
-- pas la préoccupation de cette section — la vérification fiable est
-- déportée dans le trigger security definer ci-dessous, dans la MÊME
-- transaction : un rejet là-bas annule aussi tout ce qui est posé ici
-- (atomicité normale d'une instruction UPDATE unique).
create or replace function private.fill_lease_contract_approved_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- Verrou INCONDITIONNEL dès que approved_at est déjà posé — pas une
  -- comparaison "nouvelle valeur différente de l'ancienne". now() renvoie
  -- l'heure de DÉBUT DE TRANSACTION en Postgres (pas l'heure réelle de
  -- l'instruction) : à l'intérieur d'une même transaction, deux appels à
  -- now() sont identiques, donc une comparaison par valeur laisserait passer
  -- une ré-approbation dans ce cas précis. Le seul invariant correct est
  -- "plus aucune écriture, quelle qu'elle soit, une fois approuvé".
  if old.approved_at is not null then
    raise exception 'Un contrat déjà approuvé est immuable : aucune modification possible'
      using detail = 'lease_contract.approved_at.immutable', errcode = 'P0001';
  end if;

  if new.organization_id is distinct from old.organization_id
     or new.lease_id is distinct from old.lease_id
     or new.storage_path is distinct from old.storage_path
     or new.generated_at is distinct from old.generated_at
  then
    raise exception 'organization_id, lease_id, storage_path et generated_at sont immuables'
      using detail = 'lease_contract.identity.immutable', errcode = 'P0001';
  end if;

  if new.approved_at is not null then
    new.approved_at := now();
  end if;

  return new;
end;
$$;

create trigger trg_lease_contracts_fill_approved_at
  before update on public.lease_contracts
  for each row execute function private.fill_lease_contract_approved_at();

-- Défense en profondeur : suppression bloquée même pour un rôle qui
-- bypasserait RLS (service_role) — même principe que payment_receipts
-- (Module 9).
create or replace function private.prevent_lease_contract_delete()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  raise exception 'Un contrat de bail est immuable : suppression impossible'
    using detail = 'lease_contract.delete.immutable', errcode = 'P0001';
end;
$$;

create trigger trg_lease_contracts_prevent_delete
  before delete on public.lease_contracts
  for each row execute function private.prevent_lease_contract_delete();

-- Applique l'effet réel de l'approbation : SEUL endroit qui revérifie
-- l'éligibilité (dépôts complets) et fait passer le bail à 'actif'.
-- security definer nécessaire pour deux raisons : (1) c'est le locataire
-- qui déclenche ce passage, sans la permission leases:update — même
-- principe que apply_effective_lease_termination (Module 8) ; (2) la
-- lecture de private.lease_deposits_complete doit être fiable, indépendante
-- de ce que la RLS autorise le locataire à voir directement sur
-- deposit_ledger_balances.
create or replace function private.activate_lease_on_contract_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.approved_at is not null and old.approved_at is null then
    if not coalesce(private.lease_deposits_complete(new.lease_id), false) then
      raise exception 'Approbation refusée : les dépôts initiaux requis (avance de garantie / caution eau-électricité) ne sont pas encore intégralement versés pour ce bail'
        using detail = 'lease_contract.approve.deposits_incomplete', errcode = 'P0001';
    end if;

    update public.leases
    set status = 'actif'
    where id = new.lease_id and status = 'brouillon';

    if not found then
      raise exception 'Approbation refusée : ce bail n''est plus au statut brouillon (déjà activé, ou dans un autre état)'
        using detail = 'lease_contract.approve.lease_not_draft', errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_lease_contracts_activate_lease
  after update on public.lease_contracts
  for each row execute function private.activate_lease_on_contract_approval();

-- ----------------------------------------------------------------------------
-- 4. MODULE 5c — la génération d'échéances ne se déclenche plus à l'INSERT
--    du bail, mais au passage effectif à 'actif' (Volet A). La fonction
--    appelée (generate_payment_schedules_for_lease, Module 5b) ne change
--    pas : déjà idempotente. Le trigger reste volontairement PAS security
--    definer pour la même raison qu'à l'origine (commentaire Module 5c) —
--    sauf que, désormais, la seule façon d'atteindre cette transition est
--    justement DEPUIS le trigger security definer ci-dessus (section 3) :
--    la cascade de génération d'échéances s'exécute donc avec les
--    privilèges du définisseur de trg_lease_contracts_activate_lease,
--    exactement le même compromis déjà accepté par le Module 8 pour la
--    résiliation déclenchée côté locataire (aucune régression de posture,
--    un précédent déjà établi).
-- ----------------------------------------------------------------------------

drop trigger trg_leases_generate_schedules_after_insert on public.leases;

create trigger trg_leases_generate_schedules_on_activation
  after update of status on public.leases
  for each row
  when (old.status = 'brouillon' and new.status = 'actif')
  execute function private.trigger_generate_payment_schedules_for_new_lease();

-- ----------------------------------------------------------------------------
-- 5. VUES DE LECTURE — calculées à la volée, aucune n'écrit jamais sur
--    leases (même discipline que leases_schedule_coverage, Module 5c). Le
--    seuil d'alerte (ex: 30 jours avant end_date) n'est PAS ici : décision
--    d'affichage, portée par la couche application (comme
--    LOW_COVERAGE_HORIZON_MONTHS), pas par la base.
-- ----------------------------------------------------------------------------

-- 5.1 Éligibilité à l'activation (Volet A) — un bail brouillon uniquement.
create view public.leases_activation_readiness
with (security_invoker = true)
as
select
  l.id as lease_id,
  l.organization_id,
  l.status,
  private.lease_deposits_complete(l.id) as deposits_complete,
  lc.id as contract_id,
  lc.storage_path as contract_storage_path,
  lc.generated_at as contract_generated_at,
  lc.approved_at as contract_approved_at
from public.leases l
left join public.lease_contracts lc on lc.lease_id = l.id
where l.status = 'brouillon';

grant select on public.leases_activation_readiness to authenticated;

-- 5.2 Statut de clôture (Volets B/C) — tout bail actif ou resilie, qu'il
-- soit ou non déjà engagé dans une clôture. exit_inspection_done reflète le
-- même critère que le trigger de garde (section 1.2) : un état des lieux
-- 'sortie' 'finalise' existe, indépendamment de son statut de validation
-- locataire.
create view public.leases_closure_status
with (security_invoker = true)
as
select
  l.id as lease_id,
  l.organization_id,
  l.status,
  l.end_date as lease_end_date,
  l.property_id,
  p.name as property_name,
  l.tenant_account_id,
  ta.full_name as tenant_full_name,
  l.keys_returned_at,
  (l.keys_returned_at + 7) as exit_inspection_due_date,
  si.id as latest_finalized_exit_inspection_id,
  si.inspection_date as latest_finalized_exit_inspection_date,
  (si.id is not null) as exit_inspection_done
from public.leases l
join public.properties p on p.id = l.property_id
join public.tenant_accounts ta on ta.id = l.tenant_account_id
left join lateral (
  select pi.id, pi.inspection_date
  from public.property_inspections pi
  where pi.lease_id = l.id
    and pi.inspection_type = 'sortie'
    and pi.document_status = 'finalise'
  order by pi.finalized_at desc
  limit 1
) si on true
where l.status in ('actif', 'resilie');

grant select on public.leases_closure_status to authenticated;

-- ----------------------------------------------------------------------------
-- 6. CATALOGUE DE PERMISSIONS.
-- ----------------------------------------------------------------------------

insert into public.permissions (resource, action, description) values
  ('lease_contracts', 'create', 'Générer le document de contrat d''un bail (avant approbation locataire)'),
  ('lease_contracts', 'read',   'Consulter le contrat d''un bail');

-- Pas d'action 'update'/'delete' : l'approbation est gouvernée par la
-- propriété du bail (RLS), pas par une permission ; suppression toujours
-- bloquée (voir trg_lease_contracts_prevent_delete). Pas de nouvelle
-- permission pour keys_returned_at / fin de bail / clôture définitive :
-- ce sont de simples UPDATE sur leases, déjà couverts par leases:update.

create or replace function private.seed_default_roles_for_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id     uuid;
  v_agent_id     uuid;
  v_comptable_id uuid;
begin
  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'admin', 'Administrateur', 'Accès complet à l''organisation', true)
  returning id into v_admin_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'agent', 'Gestionnaire / Agent', 'Gestion opérationnelle des locataires', true)
  returning id into v_agent_id;

  insert into public.roles (organization_id, code, name, description, is_system)
  values (new.id, 'comptable', 'Comptable', 'Accès en lecture, périmètre financier à venir', true)
  returning id into v_comptable_id;

  insert into public.role_permissions (role_id, resource, action)
  select v_admin_id, resource, action from public.permissions;

  insert into public.role_permissions (role_id, resource, action) values
    (v_agent_id, 'tenant_accounts', 'create'),
    (v_agent_id, 'tenant_accounts', 'read'),
    (v_agent_id, 'tenant_accounts', 'update'),
    (v_agent_id, 'users', 'read'),
    (v_agent_id, 'roles', 'read'),
    (v_agent_id, 'properties', 'create'),
    (v_agent_id, 'properties', 'read'),
    (v_agent_id, 'properties', 'update'),
    (v_agent_id, 'properties', 'delete'),
    (v_agent_id, 'leases', 'create'),
    (v_agent_id, 'leases', 'read'),
    (v_agent_id, 'leases', 'update'),
    (v_agent_id, 'leases', 'delete'),
    (v_agent_id, 'reservations', 'create'),
    (v_agent_id, 'reservations', 'read'),
    (v_agent_id, 'reservations', 'update'),
    (v_agent_id, 'reservations', 'delete'),
    (v_agent_id, 'payment_schedules', 'create'),
    (v_agent_id, 'payment_schedules', 'read'),
    (v_agent_id, 'payment_schedules', 'update'),
    (v_agent_id, 'payment_schedules', 'delete'),
    (v_agent_id, 'payments', 'create'),
    (v_agent_id, 'payments', 'read'),
    (v_agent_id, 'payments', 'update'),
    (v_agent_id, 'payments', 'delete'),
    (v_agent_id, 'deposit_ledger', 'create'),
    (v_agent_id, 'deposit_ledger', 'read'),
    (v_agent_id, 'property_inspections', 'create'),
    (v_agent_id, 'property_inspections', 'read'),
    (v_agent_id, 'property_inspections', 'update'),
    (v_agent_id, 'property_inspections', 'delete'),
    (v_agent_id, 'maintenance_tickets', 'create'),
    (v_agent_id, 'maintenance_tickets', 'read'),
    (v_agent_id, 'maintenance_tickets', 'update'),
    (v_agent_id, 'maintenance_tickets', 'delete'),
    (v_agent_id, 'lease_termination_requests', 'create'),
    (v_agent_id, 'lease_termination_requests', 'read'),
    (v_agent_id, 'lease_termination_requests', 'update'),
    (v_agent_id, 'payment_receipts', 'read'),
    (v_agent_id, 'payment_receipts', 'update'),
    (v_agent_id, 'schedule_invoices', 'create'),
    (v_agent_id, 'schedule_invoices', 'read'),
    (v_agent_id, 'lease_contracts', 'create'),
    (v_agent_id, 'lease_contracts', 'read');

  insert into public.role_permissions (role_id, resource, action) values
    (v_comptable_id, 'tenant_accounts', 'read'),
    (v_comptable_id, 'users', 'read'),
    (v_comptable_id, 'roles', 'read'),
    (v_comptable_id, 'properties', 'read'),
    (v_comptable_id, 'leases', 'read'),
    (v_comptable_id, 'reservations', 'read'),
    (v_comptable_id, 'payment_schedules', 'read'),
    (v_comptable_id, 'payments', 'read'),
    (v_comptable_id, 'payments', 'create'),
    (v_comptable_id, 'deposit_ledger', 'read'),
    (v_comptable_id, 'property_inspections', 'read'),
    (v_comptable_id, 'maintenance_tickets', 'read'),
    (v_comptable_id, 'lease_termination_requests', 'read'),
    (v_comptable_id, 'payment_receipts', 'read'),
    (v_comptable_id, 'payment_receipts', 'update'),
    (v_comptable_id, 'schedule_invoices', 'read'),
    (v_comptable_id, 'lease_contracts', 'read');

  return new;
end;
$$;

insert into public.role_permissions (role_id, resource, action)
select r.id, p.resource, p.action
from public.roles r
join public.permissions p on p.resource = 'lease_contracts'
where r.code = 'admin'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, v.resource, v.action
from public.roles r
cross join (values
  ('lease_contracts', 'create'), ('lease_contracts', 'read')
) as v(resource, action)
where r.code = 'agent'
on conflict do nothing;

insert into public.role_permissions (role_id, resource, action)
select r.id, 'lease_contracts', 'read'
from public.roles r
where r.code = 'comptable'
on conflict do nothing;

-- ----------------------------------------------------------------------------
-- 7. ROW LEVEL SECURITY — LEASE_CONTRACTS.
-- ----------------------------------------------------------------------------

alter table public.lease_contracts enable row level security;

create policy lease_contracts_select on public.lease_contracts
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('lease_contracts', 'read'))
    or exists (select 1 from public.leases l where l.id = lease_contracts.lease_id and l.tenant_account_id = auth.uid())
  );

-- Génération à la demande : staff (permission) OU le locataire lui-même,
-- la première fois que l'un ou l'autre consulte l'onglet contrat.
-- approved_at is null : on ne peut jamais insérer un contrat déjà
-- "pré-approuvé" — l'approbation ne passe que par l'UPDATE dédié plus bas.
create policy lease_contracts_insert on public.lease_contracts
  for insert
  with check (
    approved_at is null
    and (
      (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('lease_contracts', 'create'))
      or exists (select 1 from public.leases l where l.id = lease_contracts.lease_id and l.tenant_account_id = auth.uid())
    )
  );

-- Approbation : réservée au locataire de CE bail. La légitimité précise
-- (dépôts complets, bail encore brouillon) est portée par les triggers
-- (section 3), pas ici — même principe que lease_termination_requests_update
-- (Module 8) : RLS ne peut pas comparer OLD/NEW dans WITH CHECK.
create policy lease_contracts_update on public.lease_contracts
  for update
  using (exists (select 1 from public.leases l where l.id = lease_contracts.lease_id and l.tenant_account_id = auth.uid()))
  with check (exists (select 1 from public.leases l where l.id = lease_contracts.lease_id and l.tenant_account_id = auth.uid()));

-- Pas de policy DELETE : voir trg_lease_contracts_prevent_delete.

-- ----------------------------------------------------------------------------
-- 8. SUPABASE STORAGE — bucket privé, même discipline que payment-receipts/
--    schedule-invoices (Module 9) : PDF uniquement, pas de policy UPDATE ni
--    DELETE (immuabilité).
-- ----------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('lease-contracts', 'lease-contracts', false, 2097152, array['application/pdf'])
on conflict (id) do nothing;

-- Chemin : {organization_id}/{lease_id}/{uuid}.pdf
create policy lease_contracts_storage_select on storage.objects
  for select
  using (
    bucket_id = 'lease-contracts'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('lease_contracts', 'read'))
      or exists (
        select 1 from public.leases l
        where l.id::text = (storage.foldername(name))[2]
          and l.tenant_account_id = auth.uid()
      )
    )
  );

create policy lease_contracts_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'lease-contracts'
    and (
      (private.is_internal() and (storage.foldername(name))[1] = private.current_org_id()::text and private.has_permission('lease_contracts', 'create'))
      or exists (
        select 1 from public.leases l
        where l.id::text = (storage.foldername(name))[2]
          and l.tenant_account_id = auth.uid()
      )
    )
  );
