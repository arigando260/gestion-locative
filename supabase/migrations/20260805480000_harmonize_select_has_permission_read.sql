-- ============================================================================
-- CORRECTIF — harmonisation des policies SELECT sur leases, payment_schedules,
-- deposit_ledger : ajout de private.has_permission(resource, 'read').
--
-- Trouvé lors de l'audit sécurité Phase 1 (comparaison permissions base vs
-- can() écran) : ces 3 policies SELECT ne vérifiaient que private.is_internal()
-- pour la branche staff, sans repasser par has_permission('read') comme le
-- font déjà lease_contracts_select, payment_receipts_select,
-- schedule_invoices_select et invoice_schedule_items_select. Conséquence :
-- n'importe quel membre interne d'une organisation pouvait lire ces 3 tables
-- via l'API quelle que soit la permission read réellement accordée à son
-- rôle — l'écran masquait l'information (can()), la base ne la protégeait
-- pas. Invisible tant que seuls les 3 rôles système (admin/agent/comptable,
-- qui ont tous read par défaut) existent, mais réel dès qu'une organisation
-- crée un rôle interne volontairement restreint.
--
-- Seule la branche staff change ; la branche tenant (accès à ses propres
-- données via la jointure leases/tenant_account_id) est inchangée.
-- ============================================================================

drop policy deposit_ledger_select on public.deposit_ledger;
create policy deposit_ledger_select on public.deposit_ledger
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('deposit_ledger', 'read'))
    or exists (
      select 1 from leases l
      where l.id = deposit_ledger.lease_id and l.tenant_account_id = auth.uid()
    )
  );

drop policy leases_select on public.leases;
create policy leases_select on public.leases
  for select
  using (
    tenant_account_id = auth.uid()
    or (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('leases', 'read'))
  );

drop policy payment_schedules_select on public.payment_schedules;
create policy payment_schedules_select on public.payment_schedules
  for select
  using (
    (organization_id = private.current_org_id() and private.is_internal() and private.has_permission('payment_schedules', 'read'))
    or exists (
      select 1 from leases l
      where l.id = payment_schedules.lease_id and l.tenant_account_id = auth.uid()
    )
  );
