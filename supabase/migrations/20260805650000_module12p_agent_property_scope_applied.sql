-- ============================================================================
-- MODULE 12p — Branchement de private.agent_property_scope() sur les 7
-- tables identifiées (Phase 3, sous-module 3, brique 2/2).
--
-- Chaque policy modifiée reprend caractère pour caractère sa condition
-- existante (relue directement depuis pg_policies sur dev avant d'écrire
-- cette migration, pas depuis l'historique des migrations -- plusieurs
-- policies ici ont été réécrites plusieurs fois au fil du projet, la seule
-- source fiable est l'état vivant) : seul un "and private.agent_property_
-- scope(...)" est AJOUTÉ à la branche STAFF de chacune, jamais à la branche
-- tenant (tenant_account_id = auth.uid() / reported_by_tenant_id = ... /
-- initiated_by_tenant_id = ...), jamais en remplacement de is_internal()/
-- has_permission() déjà posés.
--
-- Résolution de property_id par table :
--   - properties               : id (directe)
--   - leases                   : property_id (colonne directe)
--   - maintenance_tickets      : property_id (colonne directe)
--   - lease_termination_requests, payment_schedules, schedule_invoices :
--     via lease_id -> leases.property_id (1 jointure -- lease_id est
--     désormais NOT NULL-équivalent sur les deux dernières depuis le
--     retrait des réservations, contrainte ..._lease_required)
--   - payment_receipts         : via payment_id -> payments.lease_id ->
--     leases.property_id (2 jointures, même chemin que sa policy SELECT)
--
-- EXCEPTION délibérée -- properties_insert n'est PAS modifiée : au moment
-- de l'INSERT, la ligne properties n'existe pas encore, donc aucune
-- assignation ne peut exister pour son id à ce stade (property_agent_
-- assignments référence par FK une ligne properties déjà existante).
-- Appliquer agent_property_scope(id) ici rendrait la condition TOUJOURS
-- fausse pour un agent (jamais vraie par construction), ce qui reviendrait
-- à lui retirer silencieusement la capacité de créer des biens alors qu'il
-- détient properties:create -- un changement de comportement qui dépasse
-- le périmètre de cette brique (restreindre la VISIBILITÉ d'un bien
-- existant, pas retirer un droit déjà accordé). Signalé explicitement au
-- lieu d'être appliqué silencieusement -- à trancher séparément si
-- souhaité (l'écran d'assignation, brique suivante, ne couvre que des
-- biens déjà créés de toute façon).
--
-- UPDATE : agent_property_scope() ajoutée à USING et, quand la policy en
-- a une, à WITH CHECK -- sans autrement toucher aux asymétries déjà
-- existantes entre les deux (ex: leases_update/payment_schedules_update
-- ont un WITH CHECK plus faible que leur USING de longue date, pas
-- modifié ici, hors périmètre de cette brique).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- PROPERTIES
-- ----------------------------------------------------------------------------

alter policy properties_select on public.properties
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.agent_property_scope(id)
    )
    or exists (
      select 1 from public.leases l
      where l.property_id = properties.id and l.tenant_account_id = auth.uid()
    )
  );

alter policy properties_update on public.properties
  using (
    organization_id = private.current_org_id()
    and private.has_permission('properties', 'update')
    and private.agent_property_scope(id)
  )
  with check (
    organization_id = private.current_org_id()
    and private.agent_property_scope(id)
  );

alter policy properties_delete on public.properties
  using (
    organization_id = private.current_org_id()
    and private.has_permission('properties', 'delete')
    and private.agent_property_scope(id)
  );

-- ----------------------------------------------------------------------------
-- LEASES
-- ----------------------------------------------------------------------------

alter policy leases_select on public.leases
  using (
    tenant_account_id = auth.uid()
    or (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.has_permission('leases', 'read')
      and private.agent_property_scope(property_id)
    )
  );

alter policy leases_insert on public.leases
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'create')
    and private.agent_property_scope(property_id)
  );

alter policy leases_update on public.leases
  using (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'update')
    and private.agent_property_scope(property_id)
  )
  with check (
    organization_id = private.current_org_id()
    and private.agent_property_scope(property_id)
  );

alter policy leases_delete on public.leases
  using (
    organization_id = private.current_org_id()
    and private.has_permission('leases', 'delete')
    and private.agent_property_scope(property_id)
  );

-- ----------------------------------------------------------------------------
-- MAINTENANCE_TICKETS
-- ----------------------------------------------------------------------------

alter policy maintenance_tickets_select on public.maintenance_tickets
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.agent_property_scope(property_id)
    )
    or reported_by_tenant_id = auth.uid()
  );

alter policy maintenance_tickets_insert on public.maintenance_tickets
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('maintenance_tickets', 'create')
      and reported_by_staff_id = auth.uid()
      and private.agent_property_scope(property_id)
    )
    or (
      reported_by_tenant_id = auth.uid()
      and reported_by_staff_id is null
      and status = 'signale'
      and priority = 'normale'
      and actual_cost is null
    )
  );

alter policy maintenance_tickets_update on public.maintenance_tickets
  using (
    (
      organization_id = private.current_org_id()
      and private.has_permission('maintenance_tickets', 'update')
      and private.agent_property_scope(property_id)
    )
    or (reported_by_tenant_id = auth.uid() and status = 'signale')
  )
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('maintenance_tickets', 'update')
      and private.agent_property_scope(property_id)
    )
    or reported_by_tenant_id = auth.uid()
  );

alter policy maintenance_tickets_delete on public.maintenance_tickets
  using (
    organization_id = private.current_org_id()
    and private.has_permission('maintenance_tickets', 'delete')
    and private.agent_property_scope(property_id)
  );

-- ----------------------------------------------------------------------------
-- LEASE_TERMINATION_REQUESTS (property_id via lease_id)
-- ----------------------------------------------------------------------------

alter policy lease_termination_requests_select on public.lease_termination_requests
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = lease_termination_requests.lease_id))
    )
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id and l.tenant_account_id = auth.uid()
    )
  );

alter policy lease_termination_requests_insert on public.lease_termination_requests
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('lease_termination_requests', 'create')
      and initiated_by_staff_id = auth.uid()
      and initiated_by_tenant_id is null
      and status = 'en_attente'
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = lease_termination_requests.lease_id))
    )
    or (
      initiated_by_tenant_id = auth.uid()
      and initiated_by_staff_id is null
      and status = 'en_attente'
      and exists (
        select 1 from public.leases l
        where l.id = lease_termination_requests.lease_id and l.tenant_account_id = auth.uid()
      )
    )
  );

alter policy lease_termination_requests_update on public.lease_termination_requests
  using (
    (
      organization_id = private.current_org_id()
      and private.has_permission('lease_termination_requests', 'update')
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = lease_termination_requests.lease_id))
    )
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id and l.tenant_account_id = auth.uid()
    )
  )
  with check (
    (
      organization_id = private.current_org_id()
      and private.has_permission('lease_termination_requests', 'update')
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = lease_termination_requests.lease_id))
    )
    or exists (
      select 1 from public.leases l
      where l.id = lease_termination_requests.lease_id and l.tenant_account_id = auth.uid()
    )
  );

-- ----------------------------------------------------------------------------
-- PAYMENT_SCHEDULES (property_id via lease_id)
-- ----------------------------------------------------------------------------

alter policy payment_schedules_select on public.payment_schedules
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.has_permission('payment_schedules', 'read')
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = payment_schedules.lease_id))
    )
    or exists (
      select 1 from public.leases l
      where l.id = payment_schedules.lease_id and l.tenant_account_id = auth.uid()
    )
  );

alter policy payment_schedules_insert on public.payment_schedules
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('payment_schedules', 'create')
    and private.agent_property_scope((select l.property_id from public.leases l where l.id = payment_schedules.lease_id))
  );

alter policy payment_schedules_update on public.payment_schedules
  using (
    organization_id = private.current_org_id()
    and private.has_permission('payment_schedules', 'update')
    and private.agent_property_scope((select l.property_id from public.leases l where l.id = payment_schedules.lease_id))
  )
  with check (
    organization_id = private.current_org_id()
    and private.agent_property_scope((select l.property_id from public.leases l where l.id = payment_schedules.lease_id))
  );

alter policy payment_schedules_delete on public.payment_schedules
  using (
    organization_id = private.current_org_id()
    and private.has_permission('payment_schedules', 'delete')
    and private.agent_property_scope((select l.property_id from public.leases l where l.id = payment_schedules.lease_id))
  );

-- ----------------------------------------------------------------------------
-- SCHEDULE_INVOICES (property_id via lease_id ; pas de policy UPDATE/DELETE
-- -- document immuable, rien à modifier ici).
-- ----------------------------------------------------------------------------

alter policy schedule_invoices_select on public.schedule_invoices
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.has_permission('schedule_invoices', 'read')
      and private.agent_property_scope((select l.property_id from public.leases l where l.id = schedule_invoices.lease_id))
    )
    or exists (
      select 1 from public.leases l
      where l.id = schedule_invoices.lease_id and l.tenant_account_id = auth.uid()
    )
  );

alter policy schedule_invoices_insert on public.schedule_invoices
  with check (
    organization_id = private.current_org_id()
    and private.has_permission('schedule_invoices', 'create')
    and generated_by = auth.uid()
    and private.agent_property_scope((select l.property_id from public.leases l where l.id = schedule_invoices.lease_id))
  );

-- ----------------------------------------------------------------------------
-- PAYMENT_RECEIPTS (property_id via payment_id -> payments.lease_id ; pas
-- de policy INSERT/DELETE -- ligne posée par un trigger sur payments,
-- jamais un INSERT client direct).
-- ----------------------------------------------------------------------------

alter policy payment_receipts_select on public.payment_receipts
  using (
    (
      organization_id = private.current_org_id()
      and private.is_internal()
      and private.has_permission('payment_receipts', 'read')
      and private.agent_property_scope((select l.property_id from public.payments p join public.leases l on l.id = p.lease_id where p.id = payment_receipts.payment_id))
    )
    or exists (
      select 1 from public.payments p
      join public.leases l on l.id = p.lease_id
      where p.id = payment_receipts.payment_id and l.tenant_account_id = auth.uid()
    )
  );

alter policy payment_receipts_update on public.payment_receipts
  using (
    organization_id = private.current_org_id()
    and private.has_permission('payment_receipts', 'update')
    and private.agent_property_scope((select l.property_id from public.payments p join public.leases l on l.id = p.lease_id where p.id = payment_receipts.payment_id))
  )
  with check (
    organization_id = private.current_org_id()
    and private.agent_property_scope((select l.property_id from public.payments p join public.leases l on l.id = p.lease_id where p.id = payment_receipts.payment_id))
  );
