-- ============================================================================
-- TEST — Module 12p (agent_property_scope() branchée sur les 7 policies :
-- properties, leases, maintenance_tickets, lease_termination_requests,
-- payment_schedules, schedule_invoices, payment_receipts).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents : transaction
-- begin/rollback, helpers pg_temp, identité simulée via pg_temp.act_as(),
-- résumé PASS/FAIL avant le ROLLBACK final.
--
-- Fixtures : org_a (admin_a réel), agent_a (assigné à property_a1, PAS à
-- property_a2), comptable_a, tenant_x (locataire réel des deux baux, via
-- le vrai parcours d'invitation). Pour chaque table, un enregistrement lié
-- à property_a1 (assigné) et un lié à property_a2 (non assigné) -- chaque
-- test d'écriture cible directement l'id connu de l'enregistrement, jamais
-- seulement un comptage de liste (couvre explicitement "un id deviné/connu
-- directement").
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration 20260805650000 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module12p_agent_property_scope_applied.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

create table pg_temp.test_results (
  id     serial primary key,
  name   text not null,
  status text not null check (status in ('PASS', 'FAIL')),
  detail text
);

create or replace function pg_temp.record(p_name text, p_status text, p_detail text default null)
returns void language plpgsql as $$
begin
  insert into pg_temp.test_results (name, status, detail) values (p_name, p_status, p_detail);
  raise notice '[%] % %', p_status, p_name, coalesce('— ' || p_detail, '');
end;
$$;

create or replace function pg_temp.act_as(p_pg_role text, p_user_id uuid)
returns void language plpgsql as $$
begin
  execute format('set local role %I', p_pg_role);
  if p_user_id is null then
    perform set_config('request.jwt.claims', '{}', true);
  else
    perform set_config(
      'request.jwt.claims',
      json_build_object('sub', p_user_id::text, 'role', p_pg_role)::text,
      true
    );
  end if;
end;
$$;

create or replace function pg_temp.act_as_owner()
returns void language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '{}', true);
end;
$$;

select pg_temp.act_as_owner();

grant select, insert on pg_temp.test_results to authenticated, service_role;
grant usage, select on all sequences in schema pg_temp to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 1. FIXTURES.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id       uuid;
  v_admin        uuid := gen_random_uuid();
  v_agent        uuid := gen_random_uuid();
  v_comptable    uuid := gen_random_uuid();
  v_tenant       uuid := gen_random_uuid();
  v_token_agent      text := encode(gen_random_bytes(32), 'hex');
  v_token_comptable  text := encode(gen_random_bytes(32), 'hex');
  v_token_tenant     text := encode(gen_random_bytes(32), 'hex');
  v_property_1   uuid;
  v_property_2   uuid;
  v_lease_1      uuid;
  v_lease_2      uuid;
  v_ticket_1     uuid;
  v_ticket_2     uuid;
  v_ltr_1        uuid;
  v_ltr_2        uuid;
  v_ps_1         uuid;
  v_ps_2         uuid;
  v_si_1         uuid;
  v_si_2         uuid;
  v_payment_1    uuid;
  v_payment_2    uuid;
  v_receipt_1    uuid;
  v_receipt_2    uuid;
begin
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_admin, 'admin-12p@example.com',
    jsonb_build_object(
      'account_type', 'internal', 'organization_name', 'Org Test 12p',
      'organization_country', 'BJ', 'organization_phone', '90000050', 'full_name', 'Admin 12p'
    ),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  select organization_id into v_org_id from public.profiles where id = v_admin;

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'agent-12p@example.com', 'agent', encode(extensions.digest(v_token_agent, 'sha256'), 'hex'), v_admin, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_agent, 'agent-12p@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_agent, 'full_name', 'Agent 12p'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.staff_invitations (organization_id, email, role_code, token_hash, invited_by, expires_at)
  values (v_org_id, 'comptable-12p@example.com', 'comptable', encode(extensions.digest(v_token_comptable, 'sha256'), 'hex'), v_admin, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_comptable, 'comptable-12p@example.com',
    jsonb_build_object('account_type', 'internal', 'staff_invitation_token', v_token_comptable, 'full_name', 'Comptable 12p'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (v_org_id, 'Bien Test12p 1 (assigné)', 500000, 'longue_duree', 'BJ', 'Cotonou', 'Fidjrosse', 'Test 12p')
  returning id into v_property_1;

  insert into public.properties (organization_id, name, price, location_type, country_code, city, neighborhood, address_complement)
  values (v_org_id, 'Bien Test12p 2 (non assigné)', 450000, 'longue_duree', 'BJ', 'Cotonou', 'Akpakpa', 'Test 12p')
  returning id into v_property_2;

  insert into public.property_agent_assignments (organization_id, property_id, agent_id, assigned_by)
  values (v_org_id, v_property_1, v_agent, v_admin);

  -- Locataire réel des deux baux, via le vrai parcours d'invitation.
  insert into public.tenant_invitations (organization_id, email, token_hash, invited_by, expires_at)
  values (v_org_id, 'tenant-12p@example.com', encode(extensions.digest(v_token_tenant, 'sha256'), 'hex'), v_admin, now() + interval '7 days');
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant, 'tenant-12p@example.com',
    jsonb_build_object('account_type', 'tenant', 'invitation_token', v_token_tenant, 'full_name', 'Tenant 12p'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, payment_timing, security_deposit_amount)
  values (v_org_id, v_property_1, v_tenant, current_date, 50000, 'mensuel', 'postpaye', 0)
  returning id into v_lease_1;

  insert into public.leases (organization_id, property_id, tenant_account_id, start_date, rent_amount, payment_frequency, payment_timing, security_deposit_amount)
  values (v_org_id, v_property_2, v_tenant, current_date, 45000, 'mensuel', 'postpaye', 0)
  returning id into v_lease_2;

  -- lease_termination_requests exige un bail actif -- l'écriture directe du
  -- statut est bloquée par trigger (Module 10 : seule l'approbation du
  -- contrat par le locataire peut faire passer brouillon -> actif). Dépôt à
  -- 0 -> private.lease_deposits_complete() vrai sans écriture dans
  -- deposit_ledger (même raccourci que la mise en place multi-org
  -- précédente), puis le vrai parcours contrat/consultation/approbation.
  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (v_org_id, v_lease_1, v_org_id || '/' || v_lease_1 || '/test12p-contract-1.pdf');
  insert into public.lease_contracts (organization_id, lease_id, storage_path)
  values (v_org_id, v_lease_2, v_org_id || '/' || v_lease_2 || '/test12p-contract-2.pdf');

  update public.lease_contracts set first_viewed_at = now() where lease_id in (v_lease_1, v_lease_2);
  update public.lease_contracts set approved_at = now() where lease_id in (v_lease_1, v_lease_2);

  insert into public.maintenance_tickets (organization_id, property_id, reported_by_staff_id, title)
  values (v_org_id, v_property_1, v_admin, 'Ticket Test12p 1')
  returning id into v_ticket_1;
  insert into public.maintenance_tickets (organization_id, property_id, reported_by_staff_id, title)
  values (v_org_id, v_property_2, v_admin, 'Ticket Test12p 2')
  returning id into v_ticket_2;

  -- initiated_by_staff_id = agent (pas admin) sur les deux : la seule
  -- transition de statut possible pour un staff sur sa PROPRE demande est
  -- l'annulation (state machine, Module 8) -- initier par admin aurait
  -- empêché l'agent d'agir dessus pour une tout autre raison (pas
  -- l'initiateur) que le scope qu'on veut isoler ici.
  insert into public.lease_termination_requests (organization_id, lease_id, initiated_by_staff_id, requested_end_date, reason)
  values (v_org_id, v_lease_1, v_agent, current_date + interval '30 days', 'Test 12p 1')
  returning id into v_ltr_1;
  insert into public.lease_termination_requests (organization_id, lease_id, initiated_by_staff_id, requested_end_date, reason)
  values (v_org_id, v_lease_2, v_agent, current_date + interval '30 days', 'Test 12p 2')
  returning id into v_ltr_2;

  -- L'activation du bail (ci-dessus) a déjà déclenché la génération
  -- automatique des échéances (trg_leases_generate_schedules_on_activation,
  -- Module 5c/10) -- on garde la première de chaque bail et on retire les
  -- éventuelles suivantes, pour garder des comptages prévisibles (1 par
  -- bail) dans les scénarios SELECT ci-dessous -- sans rapport avec ce que
  -- ce test vérifie.
  select id into v_ps_1 from public.payment_schedules where lease_id = v_lease_1 order by period_start_date limit 1;
  select id into v_ps_2 from public.payment_schedules where lease_id = v_lease_2 order by period_start_date limit 1;
  delete from public.payment_schedules where lease_id in (v_lease_1, v_lease_2) and id not in (v_ps_1, v_ps_2);

  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (v_org_id, v_lease_1, v_org_id || '/' || v_lease_1 || '/test12p-1.pdf', v_admin)
  returning id into v_si_1;
  insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
  values (v_org_id, v_lease_2, v_org_id || '/' || v_lease_2 || '/test12p-2.pdf', v_admin)
  returning id into v_si_2;

  insert into public.payments (organization_id, lease_id, amount, method, payment_type, direction, status)
  values (v_org_id, v_lease_1, 50000, 'mobile_money', 'loyer', 'entrant', 'confirme')
  returning id into v_payment_1;
  insert into public.payments (organization_id, lease_id, amount, method, payment_type, direction, status)
  values (v_org_id, v_lease_2, 45000, 'mobile_money', 'loyer', 'entrant', 'confirme')
  returning id into v_payment_2;

  select id into v_receipt_1 from public.payment_receipts where payment_id = v_payment_1;
  select id into v_receipt_2 from public.payment_receipts where payment_id = v_payment_2;

  create table pg_temp.fixtures as
  select
    v_org_id as org_id, v_admin as admin, v_agent as agent, v_comptable as comptable,
    v_property_1 as property_1, v_property_2 as property_2,
    v_lease_1 as lease_1, v_lease_2 as lease_2,
    v_ticket_1 as ticket_1, v_ticket_2 as ticket_2,
    v_ltr_1 as ltr_1, v_ltr_2 as ltr_2,
    v_ps_1 as ps_1, v_ps_2 as ps_2,
    v_si_1 as si_1, v_si_2 as si_2,
    v_payment_1 as payment_1, v_payment_2 as payment_2,
    v_receipt_1 as receipt_1, v_receipt_2 as receipt_2;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- Helper générique : vérifie un scénario SELECT (nombre de lignes visibles
-- par organization_id, comparé à un nombre attendu).
-- ----------------------------------------------------------------------------

create or replace function pg_temp.check_select_count(
  p_name text, p_table text, p_org_id uuid, p_expected int
) returns void language plpgsql as $$
declare
  v_count int;
begin
  execute format('select count(*) from public.%I where organization_id = %L', p_table, p_org_id) into v_count;
  if v_count = p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('obtenu=%s attendu=%s', v_count, p_expected));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. PROPERTIES.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('properties/admin voit les 2 biens', 'properties', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('properties/agent voit seulement son bien assigné', 'properties', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('properties/comptable voit les 2 biens (lecture large inchangée)', 'properties', f.org_id, 2);

  -- Écriture (UPDATE) par id direct.
  perform pg_temp.act_as('authenticated', f.agent);
  update public.properties set name = 'Modifié par agent' where id = f.property_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.properties where id = f.property_1 and name = 'Modifié par agent';
  if v_count = 1 then
    perform pg_temp.record('properties/agent modifie son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('properties/agent modifie son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.properties set name = 'Ne doit pas passer' where id = f.property_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.properties where id = f.property_2 and name = 'Ne doit pas passer';
  if v_count = 0 then
    perform pg_temp.record('properties/agent NE modifie PAS un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('properties/agent NE modifie PAS un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;

  perform pg_temp.act_as('authenticated', f.admin);
  update public.properties set name = 'Modifié par admin' where id = f.property_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.properties where id = f.property_2 and name = 'Modifié par admin';
  if v_count = 1 then
    perform pg_temp.record('properties/admin modifie n''importe quel bien de son organisation (UPDATE) -> inchangé', 'PASS');
  else
    perform pg_temp.record('properties/admin modifie n''importe quel bien de son organisation (UPDATE) -> inchangé', 'FAIL', 'modification non appliquée');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. LEASES.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('leases/admin voit les 2 baux', 'leases', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('leases/agent voit seulement le bail de son bien assigné', 'leases', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('leases/comptable voit les 2 baux (lecture large inchangée)', 'leases', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  update public.leases set special_terms = 'Modifié par agent' where id = f.lease_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.leases where id = f.lease_1 and special_terms = 'Modifié par agent';
  if v_count = 1 then
    perform pg_temp.record('leases/agent modifie le bail de son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('leases/agent modifie le bail de son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.leases set special_terms = 'Ne doit pas passer' where id = f.lease_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.leases where id = f.lease_2 and special_terms = 'Ne doit pas passer';
  if v_count = 0 then
    perform pg_temp.record('leases/agent NE modifie PAS le bail d''un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('leases/agent NE modifie PAS le bail d''un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. MAINTENANCE_TICKETS.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('maintenance_tickets/admin voit les 2 tickets', 'maintenance_tickets', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('maintenance_tickets/agent voit seulement le ticket de son bien assigné', 'maintenance_tickets', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('maintenance_tickets/comptable voit les 2 tickets (lecture large inchangée)', 'maintenance_tickets', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  update public.maintenance_tickets set status = 'en_cours' where id = f.ticket_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.maintenance_tickets where id = f.ticket_1 and status = 'en_cours';
  if v_count = 1 then
    perform pg_temp.record('maintenance_tickets/agent modifie le ticket de son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('maintenance_tickets/agent modifie le ticket de son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.maintenance_tickets set status = 'en_cours' where id = f.ticket_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.maintenance_tickets where id = f.ticket_2 and status = 'en_cours';
  if v_count = 0 then
    perform pg_temp.record('maintenance_tickets/agent NE modifie PAS un ticket sur un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('maintenance_tickets/agent NE modifie PAS un ticket sur un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;

  -- INSERT staff, par id de bien connu.
  perform pg_temp.act_as('authenticated', f.agent);
  begin
    insert into public.maintenance_tickets (organization_id, property_id, reported_by_staff_id, title)
    values (f.org_id, f.property_1, f.agent, 'Nouveau ticket agent (bien assigné)');
    perform pg_temp.record('maintenance_tickets/agent crée un ticket sur son bien assigné (INSERT) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('maintenance_tickets/agent crée un ticket sur son bien assigné (INSERT) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.agent);
  begin
    insert into public.maintenance_tickets (organization_id, property_id, reported_by_staff_id, title)
    values (f.org_id, f.property_2, f.agent, 'Ne doit pas être créé');
    perform pg_temp.record('maintenance_tickets/agent NE crée PAS un ticket sur un bien non assigné (INSERT)', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('maintenance_tickets/agent NE crée PAS un ticket sur un bien non assigné (INSERT)', 'PASS');
  end;

  -- DELETE : agent a bien la permission maintenance_tickets:delete (Phase 3,
  -- diagnostic préalable) -- c'est le SCOPE qui doit bloquer ici, pas
  -- l'absence de permission. Cible directe par id, sur le bien non assigné.
  perform pg_temp.act_as('authenticated', f.agent);
  delete from public.maintenance_tickets where id = f.ticket_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.maintenance_tickets where id = f.ticket_2;
  if v_count = 1 then
    perform pg_temp.record('maintenance_tickets/agent NE supprime PAS un ticket sur un bien non assigné, même par id direct (DELETE)', 'PASS');
  else
    perform pg_temp.record('maintenance_tickets/agent NE supprime PAS un ticket sur un bien non assigné, même par id direct (DELETE)', 'FAIL', 'ligne supprimée à tort');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  delete from public.maintenance_tickets where id = f.ticket_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.maintenance_tickets where id = f.ticket_1;
  if v_count = 0 then
    perform pg_temp.record('maintenance_tickets/agent supprime un ticket sur son bien assigné (DELETE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('maintenance_tickets/agent supprime un ticket sur son bien assigné (DELETE) -> autorisé', 'FAIL', 'ligne non supprimée');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. LEASE_TERMINATION_REQUESTS.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('lease_termination_requests/admin voit les 2 demandes', 'lease_termination_requests', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('lease_termination_requests/agent voit seulement la demande de son bien assigné', 'lease_termination_requests', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('lease_termination_requests/comptable voit les 2 demandes (lecture large inchangée)', 'lease_termination_requests', f.org_id, 2);

  -- Seule transition possible pour l'agent sur sa propre demande (state
  -- machine, Module 8) : annulation. Isole bien le scope comme seule
  -- variable (agent = initiateur des deux, condition déjà remplie).
  perform pg_temp.act_as('authenticated', f.agent);
  update public.lease_termination_requests set status = 'annulee' where id = f.ltr_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.lease_termination_requests where id = f.ltr_1 and status = 'annulee';
  if v_count = 1 then
    perform pg_temp.record('lease_termination_requests/agent annule sa demande sur son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('lease_termination_requests/agent annule sa demande sur son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.lease_termination_requests set status = 'annulee' where id = f.ltr_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.lease_termination_requests where id = f.ltr_2 and status = 'annulee';
  if v_count = 0 then
    perform pg_temp.record('lease_termination_requests/agent N''annule PAS sa demande sur un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('lease_termination_requests/agent N''annule PAS sa demande sur un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. PAYMENT_SCHEDULES.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('payment_schedules/admin voit les 2 échéances', 'payment_schedules', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('payment_schedules/agent voit seulement l''échéance de son bien assigné', 'payment_schedules', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('payment_schedules/comptable voit les 2 échéances (lecture large inchangée)', 'payment_schedules', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  update public.payment_schedules set status = 'annulee' where id = f.ps_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_schedules where id = f.ps_1 and status = 'annulee';
  if v_count = 1 then
    perform pg_temp.record('payment_schedules/agent modifie l''échéance de son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('payment_schedules/agent modifie l''échéance de son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.payment_schedules set status = 'annulee' where id = f.ps_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_schedules where id = f.ps_2 and status = 'annulee';
  if v_count = 0 then
    perform pg_temp.record('payment_schedules/agent NE modifie PAS l''échéance d''un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('payment_schedules/agent NE modifie PAS l''échéance d''un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. SCHEDULE_INVOICES (pas de policy UPDATE/DELETE -- SELECT + INSERT
--    seulement).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('schedule_invoices/admin voit les 2 factures', 'schedule_invoices', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('schedule_invoices/agent voit seulement la facture de son bien assigné', 'schedule_invoices', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('schedule_invoices/comptable voit les 2 factures (lecture large inchangée)', 'schedule_invoices', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  begin
    insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
    values (f.org_id, f.lease_1, f.org_id || '/' || f.lease_1 || '/test12p-agent-ok.pdf', f.agent);
    perform pg_temp.record('schedule_invoices/agent génère une facture sur son bien assigné (INSERT) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('schedule_invoices/agent génère une facture sur son bien assigné (INSERT) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  perform pg_temp.act_as('authenticated', f.agent);
  begin
    insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
    values (f.org_id, f.lease_2, f.org_id || '/' || f.lease_2 || '/test12p-agent-refuse.pdf', f.agent);
    perform pg_temp.record('schedule_invoices/agent NE génère PAS de facture sur un bien non assigné (INSERT)', 'FAIL', 'succès inattendu');
  exception when others then
    perform pg_temp.record('schedule_invoices/agent NE génère PAS de facture sur un bien non assigné (INSERT)', 'PASS');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. PAYMENT_RECEIPTS (pas de policy INSERT/DELETE -- SELECT + UPDATE
--    seulement ; comptable a réellement update ici, seul cas testable de
--    "écriture inchangée pour comptable").
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.admin);
  perform pg_temp.check_select_count('payment_receipts/admin voit les 2 reçus', 'payment_receipts', f.org_id, 2);

  perform pg_temp.act_as('authenticated', f.agent);
  perform pg_temp.check_select_count('payment_receipts/agent voit seulement le reçu de son bien assigné', 'payment_receipts', f.org_id, 1);

  perform pg_temp.act_as('authenticated', f.comptable);
  perform pg_temp.check_select_count('payment_receipts/comptable voit les 2 reçus (lecture large inchangée)', 'payment_receipts', f.org_id, 2);

  -- comptable a has_permission('payment_receipts','update') : doit rester
  -- inchangé (non restreint) sur le bien NON assigné à l'agent -- seule
  -- table où l'écriture actuelle de comptable est directement testable.
  perform pg_temp.act_as('authenticated', f.comptable);
  update public.payment_receipts set storage_path = f.org_id || '/comptable-test.pdf', generated_at = now() where id = f.receipt_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_receipts where id = f.receipt_2 and storage_path = f.org_id || '/comptable-test.pdf';
  if v_count = 1 then
    perform pg_temp.record('payment_receipts/comptable modifie un reçu peu importe le bien (UPDATE) -> inchangé', 'PASS');
  else
    perform pg_temp.record('payment_receipts/comptable modifie un reçu peu importe le bien (UPDATE) -> inchangé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.payment_receipts set storage_path = f.org_id || '/agent-test-ok.pdf', generated_at = now() where id = f.receipt_1;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_receipts where id = f.receipt_1 and storage_path = f.org_id || '/agent-test-ok.pdf';
  if v_count = 1 then
    perform pg_temp.record('payment_receipts/agent modifie le reçu de son bien assigné (UPDATE) -> autorisé', 'PASS');
  else
    perform pg_temp.record('payment_receipts/agent modifie le reçu de son bien assigné (UPDATE) -> autorisé', 'FAIL', 'modification non appliquée');
  end if;

  perform pg_temp.act_as('authenticated', f.agent);
  update public.payment_receipts set storage_path = f.org_id || '/agent-test-refuse.pdf', generated_at = now() where id = f.receipt_2;
  perform pg_temp.act_as_owner();
  select count(*) into v_count from public.payment_receipts where id = f.receipt_2 and storage_path = f.org_id || '/agent-test-refuse.pdf';
  if v_count = 0 then
    perform pg_temp.record('payment_receipts/agent NE modifie PAS le reçu d''un bien non assigné, même par id direct (UPDATE)', 'PASS');
  else
    perform pg_temp.record('payment_receipts/agent NE modifie PAS le reçu d''un bien non assigné, même par id direct (UPDATE)', 'FAIL', 'modification appliquée à tort');
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. RÉSUMÉ.
-- ----------------------------------------------------------------------------

select pg_temp.act_as_owner();

select
  count(*) filter (where status = 'PASS') as passed,
  count(*) filter (where status = 'FAIL') as failed,
  count(*)                                as total
from pg_temp.test_results;

select id, name, status, detail
from pg_temp.test_results
order by id;

do $$
declare
  v_failed int;
begin
  select count(*) into v_failed from pg_temp.test_results where status = 'FAIL';
  if v_failed > 0 then
    raise warning '% test(s) en échec — voir le résumé ci-dessus.', v_failed;
  else
    raise notice 'Tous les tests sont passés.';
  end if;
end;
$$;

rollback;
