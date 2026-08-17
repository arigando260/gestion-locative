-- ============================================================================
-- RETRAIT DES RÉSERVATIONS — SUITE DE LA PASSE D : SEEDING DES NOUVEAUX
-- RÔLES SYSTÈME.
--
-- Trouvé en exécutant remove_reservations_d_e_permissions_and_table.sql sur
-- le distant, juste après application de D et E (aucune donnée perdue :
-- l'échec s'est produit à l'intérieur du script de test, dans sa propre
-- transaction BEGIN/ROLLBACK) : private.seed_default_roles_for_org()
-- (Module 1, dernière fois redéfinie au Module 10) porte encore 5 lignes
-- VALUES codées en dur pour le resource 'reservations' — 4 pour le rôle
-- agent, 1 pour comptable. Cette fonction se déclenche à la création de
-- CHAQUE nouvelle organisation (trg_seed_default_roles) ; Migration D a
-- retiré 'reservations' du catalogue public.permissions mais n'a pas et ne
-- pouvait pas toucher à cette fonction (les VALUES ne sont pas dérivées du
-- catalogue, contrairement au rôle admin qui fait
-- "select ... from public.permissions"). Résultat : toute organisation
-- créée entre l'application de D et cette migration aurait échoué à la
-- création (violation de la FK role_permissions_resource_action_fkey).
--
-- CREATE OR REPLACE FUNCTION à l'identique, moins les 5 lignes
-- 'reservations'. Aucun autre changement de corps de fonction.
-- ============================================================================

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
