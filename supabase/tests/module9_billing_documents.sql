-- ============================================================================
-- TEST — Module 9 (documents de facturation : payment_receipts,
-- schedule_invoices, invoice_schedule_items, trigger d'éligibilité sur
-- payments, colonnes de coordonnées sur organizations).
--
-- Script SQL autonome — PAS une migration, ne pas déposer dans
-- supabase/migrations/. Même patron que les scripts précédents
-- (module7b/module8/module2c) : transaction begin/rollback, helpers
-- pg_temp, identité simulée via pg_temp.act_as(), résumé PASS/FAIL avant
-- le ROLLBACK final.
--
-- Hors périmètre de ce test (rendu PDF non implémenté à ce stade) :
-- storage_path est renseigné avec une valeur de test factice
-- ('{org}/{payment}/test.pdf'), jamais un vrai fichier déposé dans le
-- bucket — ce script vérifie le SCHÉMA (triggers, contraintes, RLS), pas
-- le pipeline de rendu.
--
-- Exécution :
--   supabase start   (si l'instance locale n'est pas déjà démarrée)
--   supabase db reset   (pour que la migration Module 9 soit appliquée)
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--     -v ON_ERROR_STOP=1 -f supabase/tests/module9_billing_documents.sql
-- ============================================================================

\set ON_ERROR_STOP on

begin;

-- ----------------------------------------------------------------------------
-- 0. HELPERS DE TEST (identiques aux scripts précédents).
-- ----------------------------------------------------------------------------

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

create or replace function pg_temp.check_detail(p_name text, p_got text, p_expected text)
returns void language plpgsql as $$
begin
  if p_got is not distinct from p_expected then
    perform pg_temp.record(p_name, 'PASS');
  else
    perform pg_temp.record(p_name, 'FAIL', format('détail attendu=%L, obtenu=%L', p_expected, p_got));
  end if;
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
--    - org, staff (admin), tenant A (bail A), tenant B (bail B, sert
--      uniquement au test de mélange inter-locataire et de non-visibilité).
--    - lease_a a 2 échéances (schedule_a1, schedule_a2) et 2 paiements :
--      l'un confirmé dès l'INSERT, l'autre confirmé via UPDATE ultérieur —
--      les deux chemins que le trigger doit couvrir indifféremment.
--    - lease_b a 1 échéance (schedule_b1), sans paiement : sert uniquement
--      à prouver qu'une facture de lease_a ne peut pas l'inclure.
-- ----------------------------------------------------------------------------

do $$
declare
  v_org_id      uuid;
  v_staff_id    uuid := gen_random_uuid();
  v_tenant_a_id uuid := gen_random_uuid();
  v_tenant_b_id uuid := gen_random_uuid();
  v_prop_a      uuid;
  v_prop_b      uuid;
  v_lease_a     uuid;
  v_lease_b     uuid;
  v_sched_a1    uuid;
  v_sched_a2    uuid;
  v_sched_b1    uuid;
  v_payment1_id uuid;
  v_payment2_id uuid;
begin
  insert into public.organizations (name, slug)
  values ('Test Org 9', 'test-org-9-' || substr(gen_random_uuid()::text, 1, 8))
  returning id into v_org_id;

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_staff_id, 'staff-9@example.com',
    jsonb_build_object('account_type', 'internal', 'organization_id', v_org_id, 'full_name', 'Staff Test 9'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into public.user_roles (user_id, role_id)
  select v_staff_id, r.id from public.roles r
  where r.organization_id = v_org_id and r.code = 'admin';

  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_a_id, 'tenant-9a@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant A Test 9'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );
  insert into auth.users (id, email, raw_user_meta_data, raw_app_meta_data, aud, role)
  values (
    v_tenant_b_id, 'tenant-9b@example.com',
    jsonb_build_object('account_type', 'tenant', 'organization_id', v_org_id, 'full_name', 'Tenant B Test 9'),
    '{}'::jsonb, 'authenticated', 'authenticated'
  );

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 9 — A', '1 rue du Test', 500000, 'longue_duree') returning id into v_prop_a;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_a, v_tenant_a_id, current_date, 100000, 'mensuel', 200000, 'postpaye')
  returning id into v_lease_a;

  insert into public.properties (organization_id, name, address, price, location_type)
  values (v_org_id, 'Bien 9 — B', '2 rue du Test', 500000, 'longue_duree') returning id into v_prop_b;
  insert into public.leases (
    organization_id, property_id, tenant_account_id, start_date,
    rent_amount, payment_frequency, security_deposit_amount, payment_timing
  ) values (v_org_id, v_prop_b, v_tenant_b_id, current_date, 90000, 'mensuel', 180000, 'postpaye')
  returning id into v_lease_b;

  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_a, current_date, current_date + 30, 100000, current_date + 30, 'en_attente')
  returning id into v_sched_a1;
  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_a, current_date + 30, current_date + 60, 100000, current_date + 60, 'en_attente')
  returning id into v_sched_a2;
  insert into public.payment_schedules (organization_id, lease_id, period_start_date, period_end_date, amount_due, due_date, status)
  values (v_org_id, v_lease_b, current_date, current_date + 30, 90000, current_date + 30, 'en_attente')
  returning id into v_sched_b1;

  -- Paiement 1 : confirmé dès l'INSERT (chemin actuel de recordPayment()).
  insert into public.payments (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (v_org_id, v_lease_a, v_sched_a1, 100000, current_date, 'virement', 'loyer', 'entrant', 'confirme')
  returning id into v_payment1_id;

  -- Paiement 2 : inséré en_attente, confirmé ENSUITE via UPDATE — le
  -- chemin que le trigger doit couvrir même si aucune Server Action ne
  -- l'exerce encore aujourd'hui.
  insert into public.payments (organization_id, lease_id, payment_schedule_id, amount, payment_date, method, payment_type, direction, status)
  values (v_org_id, v_lease_a, v_sched_a2, 100000, current_date, 'virement', 'loyer', 'entrant', 'en_attente')
  returning id into v_payment2_id;

  create table pg_temp.fixtures as
  select
    v_org_id      as org_id,
    v_staff_id    as staff_id,
    v_tenant_a_id as tenant_a_id,
    v_tenant_b_id as tenant_b_id,
    v_lease_a     as lease_a,
    v_lease_b     as lease_b,
    v_sched_a1    as sched_a1,
    v_sched_a2    as sched_a2,
    v_sched_b1    as sched_b1,
    v_payment1_id as payment1_id,
    v_payment2_id as payment2_id;
end;
$$;

grant select, insert on pg_temp.fixtures to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- 2. SCÉNARIOS 1a/1b/1c — ÉLIGIBILITÉ AUTOMATIQUE AU REÇU.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
  v_storage_path text;
begin
  select * into f from pg_temp.fixtures;

  -- 1a : paiement confirmé dès l'INSERT -> ligne payment_receipts créée.
  select count(*), max(storage_path) into v_count, v_storage_path
  from public.payment_receipts where payment_id = f.payment1_id;
  if v_count = 1 and v_storage_path is null then
    perform pg_temp.record('1a paiement confirmé à l''INSERT -> payment_receipts créé (storage_path null)', 'PASS');
  else
    perform pg_temp.record('1a paiement confirmé à l''INSERT -> payment_receipts créé (storage_path null)', 'FAIL',
      format('count=%s storage_path=%L', v_count, v_storage_path));
  end if;

  -- 1b : paiement confirmé via UPDATE (pas encore fait à ce stade des fixtures).
  select count(*) into v_count from public.payment_receipts where payment_id = f.payment2_id;
  if v_count = 0 then
    perform pg_temp.record('1b (contrôle) pas encore de reçu avant confirmation du paiement 2', 'PASS');
  else
    perform pg_temp.record('1b (contrôle) pas encore de reçu avant confirmation du paiement 2', 'FAIL', format('count=%s', v_count));
  end if;

  update public.payments set status = 'confirme' where id = f.payment2_id;

  select count(*), max(storage_path) into v_count, v_storage_path
  from public.payment_receipts where payment_id = f.payment2_id;
  if v_count = 1 and v_storage_path is null then
    perform pg_temp.record('1b paiement confirmé via UPDATE -> payment_receipts créé aussi', 'PASS');
  else
    perform pg_temp.record('1b paiement confirmé via UPDATE -> payment_receipts créé aussi', 'FAIL',
      format('count=%s storage_path=%L', v_count, v_storage_path));
  end if;

  -- 1c : re-confirmation (confirme -> echoue -> confirme) -> pas de doublon.
  update public.payments set status = 'echoue' where id = f.payment1_id;
  update public.payments set status = 'confirme' where id = f.payment1_id;

  select count(*) into v_count from public.payment_receipts where payment_id = f.payment1_id;
  if v_count = 1 then
    perform pg_temp.record('1c re-confirmation d''un paiement -> pas de doublon de reçu', 'PASS');
  else
    perform pg_temp.record('1c re-confirmation d''un paiement -> pas de doublon de reçu', 'FAIL', format('count=%s, attendu 1', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. SCÉNARIOS 2/3 — RENSEIGNER storage_path (transition légitime), PUIS
--    IMMUABILITÉ UNE FOIS POSÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_detail text;
  v_generated_at timestamptz;
begin
  select * into f from pg_temp.fixtures;
  perform pg_temp.act_as('authenticated', f.staff_id);

  -- 2 : staff renseigne storage_path -> autorisé, generated_at posé par le serveur.
  begin
    update public.payment_receipts
    set storage_path = f.org_id || '/' || f.payment1_id || '/test.pdf'
    where payment_id = f.payment1_id;
    perform pg_temp.record('2 staff renseigne storage_path -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('2 staff renseigne storage_path -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  select generated_at into v_generated_at from public.payment_receipts where payment_id = f.payment1_id;
  if v_generated_at is not null then
    perform pg_temp.record('2b generated_at posé automatiquement au moment du rendu', 'PASS');
  else
    perform pg_temp.record('2b generated_at posé automatiquement au moment du rendu', 'FAIL', 'generated_at est null');
  end if;

  -- 3 : tentative de modification après coup -> refusée.
  begin
    update public.payment_receipts
    set storage_path = f.org_id || '/' || f.payment1_id || '/autre.pdf'
    where payment_id = f.payment1_id;
    perform pg_temp.record('3 modifier storage_path après génération -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('3 modifier storage_path après génération -> refusé', v_detail, 'payment_receipt.storage_path.immutable');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. SCÉNARIOS 4/5 — LECTURE LOCATAIRE (le sien visible, celui d'un autre non).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  perform pg_temp.act_as('authenticated', f.tenant_a_id);
  select count(*) into v_count from public.payment_receipts where payment_id = f.payment1_id;
  if v_count = 1 then
    perform pg_temp.record('4 locataire A lit son propre reçu -> visible', 'PASS');
  else
    perform pg_temp.record('4 locataire A lit son propre reçu -> visible', 'FAIL', format('count=%s, attendu 1', v_count));
  end if;

  perform pg_temp.act_as('authenticated', f.tenant_b_id);
  select count(*) into v_count from public.payment_receipts where payment_id = f.payment1_id;
  if v_count = 0 then
    perform pg_temp.record('5 locataire B ne voit pas le reçu du locataire A', 'PASS');
  else
    perform pg_temp.record('5 locataire B ne voit pas le reçu du locataire A', 'FAIL', format('count=%s, attendu 0', v_count));
  end if;
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. SCÉNARIOS 6/7/8 — AUCUNE POLICY INSERT, SUPPRESSION TOUJOURS REFUSÉE
--    (y compris service_role, défense en profondeur).
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_sqlstate text;
  v_detail text;
  v_rows int;
begin
  select * into f from pg_temp.fixtures;

  -- 6 : staff tente un INSERT direct (contournant le trigger) -> refusé.
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.payment_receipts (organization_id, payment_id)
    values (f.org_id, f.payment1_id);
    perform pg_temp.record('6 staff insère directement dans payment_receipts -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_sqlstate = returned_sqlstate;
    if v_sqlstate = '42501' then
      perform pg_temp.record('6 staff insère directement dans payment_receipts -> refusé', 'PASS');
    else
      perform pg_temp.record('6 staff insère directement dans payment_receipts -> refusé', 'FAIL',
        'sqlstate attendu 42501, obtenu ' || v_sqlstate || ' (' || sqlerrm || ')');
    end if;
  end;

  -- 7 : staff tente une suppression -> aucune policy DELETE n'existe sur
  -- payment_receipts pour un rôle non-bypass, donc RLS filtre la ligne
  -- AVANT même que le trigger ne s'exécute -> 0 ligne affectée, pas
  -- d'exception (même principe que 2.2b dans module7b_maintenance_locks.sql :
  -- le trigger n'est la vraie garde-fou que pour un rôle qui bypasse RLS,
  -- voir scénario 8 juste après).
  delete from public.payment_receipts where payment_id = f.payment1_id;
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform pg_temp.record('7 staff supprime un reçu -> refusé (silencieux via RLS, aucune policy DELETE)', 'PASS');
  else
    perform pg_temp.record('7 staff supprime un reçu -> refusé (silencieux via RLS, aucune policy DELETE)', 'FAIL',
      format('%s ligne(s) supprimée(s), attendu 0', v_rows));
  end if;

  -- 8 : service_role (bypasse RLS entièrement) -> refusé quand même.
  perform pg_temp.act_as('service_role', f.staff_id);
  begin
    delete from public.payment_receipts where payment_id = f.payment1_id;
    perform pg_temp.record('8 service_role supprime un reçu -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('8 service_role supprime un reçu -> refusé malgré bypass RLS', v_detail, 'payment_receipt.delete.immutable');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 6. SCÉNARIOS 9/10/11/12/13 — FACTURATION GROUPÉE, MÉLANGE INTER-BAIL
--    BLOQUÉ, LECTURE LOCATAIRE, PAS D'INSERT LOCATAIRE, IMMUABILITÉ.
-- ----------------------------------------------------------------------------

do $$
declare
  f record;
  v_invoice_id uuid;
  v_detail text;
  v_count int;
begin
  select * into f from pg_temp.fixtures;

  -- 9 : staff génère une facture groupée sur les 2 échéances de lease_a.
  perform pg_temp.act_as('authenticated', f.staff_id);
  begin
    insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
    values (f.org_id, f.lease_a, f.org_id || '/test-invoice/test.pdf', f.staff_id)
    returning id into v_invoice_id;

    insert into public.invoice_schedule_items (organization_id, invoice_id, payment_schedule_id)
    values (f.org_id, v_invoice_id, f.sched_a1), (f.org_id, v_invoice_id, f.sched_a2);

    perform pg_temp.record('9 staff génère une facture groupée (2 échéances, même bail) -> autorisé', 'PASS');
  exception when others then
    perform pg_temp.record('9 staff génère une facture groupée (2 échéances, même bail) -> autorisé', 'FAIL', 'exception inattendue: ' || sqlerrm);
  end;

  -- 10 : tentative d'ajouter une échéance d'un AUTRE bail à cette facture -> refusé.
  begin
    insert into public.invoice_schedule_items (organization_id, invoice_id, payment_schedule_id)
    values (f.org_id, v_invoice_id, f.sched_b1);
    perform pg_temp.record('10 ajouter une échéance d''un autre bail à la facture -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('10 ajouter une échéance d''un autre bail à la facture -> refusé', v_detail, 'invoice_schedule_item.mismatch.lease_or_reservation');
  end;

  -- 11 : locataire A lit sa facture et ses lignes ; locataire B ne la voit pas.
  perform pg_temp.act_as('authenticated', f.tenant_a_id);
  select count(*) into v_count from public.schedule_invoices where id = v_invoice_id;
  if v_count = 1 then
    perform pg_temp.record('11a locataire A lit sa propre facture -> visible', 'PASS');
  else
    perform pg_temp.record('11a locataire A lit sa propre facture -> visible', 'FAIL', format('count=%s', v_count));
  end if;

  select count(*) into v_count from public.invoice_schedule_items where invoice_id = v_invoice_id;
  if v_count = 2 then
    perform pg_temp.record('11b locataire A lit les 2 lignes de sa facture', 'PASS');
  else
    perform pg_temp.record('11b locataire A lit les 2 lignes de sa facture', 'FAIL', format('count=%s, attendu 2', v_count));
  end if;

  perform pg_temp.act_as('authenticated', f.tenant_b_id);
  select count(*) into v_count from public.schedule_invoices where id = v_invoice_id;
  if v_count = 0 then
    perform pg_temp.record('11c locataire B ne voit pas la facture du locataire A', 'PASS');
  else
    perform pg_temp.record('11c locataire B ne voit pas la facture du locataire A', 'FAIL', format('count=%s, attendu 0', v_count));
  end if;

  -- 12 : locataire tente de créer une facture -> refusé.
  perform pg_temp.act_as('authenticated', f.tenant_a_id);
  begin
    insert into public.schedule_invoices (organization_id, lease_id, storage_path, generated_by)
    values (f.org_id, f.lease_a, f.org_id || '/x/x.pdf', f.tenant_a_id);
    perform pg_temp.record('12 locataire tente de créer une facture -> refusé', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = returned_sqlstate;
    if v_detail = '42501' then
      perform pg_temp.record('12 locataire tente de créer une facture -> refusé', 'PASS');
    else
      perform pg_temp.record('12 locataire tente de créer une facture -> refusé', 'FAIL', 'sqlstate attendu 42501, obtenu ' || v_detail);
    end if;
  end;

  -- 13a : facture déjà générée -> aucune policy UPDATE n'existe sur
  -- schedule_invoices pour un rôle non-bypass, donc RLS filtre la ligne
  -- avant le trigger -> 0 ligne affectée, pas d'exception (même principe
  -- que le scénario 7 ci-dessus). Le trigger reste la vraie garde-fou pour
  -- un rôle qui bypasse RLS, voir 13b juste après.
  perform pg_temp.act_as('authenticated', f.staff_id);
  update public.schedule_invoices set storage_path = f.org_id || '/x/modifie.pdf' where id = v_invoice_id;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    perform pg_temp.record('13a staff modifie une facture générée -> refusé (silencieux via RLS, aucune policy UPDATE)', 'PASS');
  else
    perform pg_temp.record('13a staff modifie une facture générée -> refusé (silencieux via RLS, aucune policy UPDATE)', 'FAIL',
      format('%s ligne(s) modifiée(s), attendu 0', v_count));
  end if;

  perform pg_temp.act_as('service_role', f.staff_id);
  begin
    delete from public.schedule_invoices where id = v_invoice_id;
    perform pg_temp.record('13b service_role supprime une facture -> refusé malgré bypass RLS', 'FAIL', 'succès inattendu');
  exception when others then
    get stacked diagnostics v_detail = pg_exception_detail;
    perform pg_temp.check_detail('13b service_role supprime une facture -> refusé malgré bypass RLS', v_detail, 'schedule_invoice.immutable');
  end;
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. RÉSUMÉ.
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
