-- ============================================================================
-- MODULE 7b — CORRECTIFS MAINTENANCE : VERROU PHOTO LOCATAIRE, GEL DES COÛTS
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. VERROU PHOTO LOCATAIRE ALIGNÉ SUR LE VERROU D'ÉDITION.
-- Un locataire ne pouvait plus modifier le ticket dès que status <> 'signale'
-- (restrict_tenant_maintenance_ticket_update_fields), mais pouvait encore
-- ajouter/supprimer des photos tant que le ticket n'était pas résolu/fermé
-- (status not in ('resolu','ferme'), donc y compris en 'en_cours') :
-- incohérence entre les deux verrous. Alignement sur status = 'signale'.
-- La fenêtre staff (bloquée uniquement à resolu/ferme) est inchangée.
-- ----------------------------------------------------------------------------

drop policy maintenance_ticket_photos_insert on public.maintenance_ticket_photos;

create policy maintenance_ticket_photos_insert on public.maintenance_ticket_photos
  for insert
  with check (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'update'))
    or exists (
      select 1 from public.maintenance_tickets t
      where t.id = maintenance_ticket_photos.maintenance_ticket_id
        and t.reported_by_tenant_id = auth.uid()
        and t.status = 'signale'
    )
  );

drop policy maintenance_ticket_photos_delete on public.maintenance_ticket_photos;

create policy maintenance_ticket_photos_delete on public.maintenance_ticket_photos
  for delete
  using (
    (organization_id = private.current_org_id() and private.has_permission('maintenance_tickets', 'delete'))
    or exists (
      select 1 from public.maintenance_tickets t
      where t.id = maintenance_ticket_photos.maintenance_ticket_id
        and t.reported_by_tenant_id = auth.uid()
        and t.status = 'signale'
    )
  );

drop policy maintenance_ticket_photos_storage_insert on storage.objects;

create policy maintenance_ticket_photos_storage_insert on storage.objects
  for insert
  with check (
    bucket_id = 'maintenance-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('maintenance_tickets', 'update')
      )
      or exists (
        select 1 from public.maintenance_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and t.reported_by_tenant_id = auth.uid()
          and t.status = 'signale'
          and (storage.foldername(name))[1] = t.organization_id::text
      )
    )
  );

drop policy maintenance_ticket_photos_storage_delete on storage.objects;

create policy maintenance_ticket_photos_storage_delete on storage.objects
  for delete
  using (
    bucket_id = 'maintenance-photos'
    and (
      (
        private.is_internal()
        and (storage.foldername(name))[1] = private.current_org_id()::text
        and private.has_permission('maintenance_tickets', 'delete')
      )
      or exists (
        select 1 from public.maintenance_tickets t
        where t.id::text = (storage.foldername(name))[2]
          and t.reported_by_tenant_id = auth.uid()
          and t.status = 'signale'
          and (storage.foldername(name))[1] = t.organization_id::text
      )
    )
  );

-- Défense en profondeur au-delà des RLS ci-dessus, même principe que
-- prevent_maintenance_ticket_identity_change : le trigger distingue
-- désormais staff (fenêtre inchangée, bloquée à resolu/ferme) et locataire
-- (fenêtre resserrée à signale). La condition resolu/ferme reste en tête et
-- s'applique à tout le monde ; la condition locataire est un resserrement
-- supplémentaire, jamais un assouplissement.
create or replace function private.prevent_maintenance_ticket_photo_when_closed()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_status text;
begin
  select status into v_status
  from public.maintenance_tickets
  where id = coalesce(new.maintenance_ticket_id, old.maintenance_ticket_id);

  if v_status in ('resolu', 'ferme') then
    raise exception 'Impossible d''ajouter ou de supprimer une photo : ce ticket de maintenance est déjà % ',
      case when v_status = 'resolu' then 'résolu' else 'fermé' end
      using detail = 'maintenance_ticket_photo.ticket_closed.locked', errcode = 'P0001';
  end if;

  if not private.is_internal() and v_status <> 'signale' then
    raise exception 'Un locataire ne peut ajouter ou supprimer une photo que tant que son ticket est au statut ''signalé'''
      using detail = 'maintenance_ticket_photo.tenant_write.locked_after_staff_action', errcode = 'P0001';
  end if;

  return coalesce(new, old);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. GEL DE estimated_cost / actual_cost APRÈS IMPUTATION DE CAUTION.
-- Dès qu'une ligne de deposit_ledger référence le ticket (justification
-- traçable d'une imputation dégâts, cf. Module 7), les coûts affichés au
-- moment de l'imputation ne doivent plus pouvoir être modifiés a posteriori
-- — sans quoi le montant justificatif divergerait silencieusement du
-- montant réellement imputé sur la caution. S'applique à tout acteur,
-- staff inclus (deposit_ledger_select autorise déjà tout profil interne de
-- l'organisation à voir les lignes de son organisation, cf. Module 5).
-- ----------------------------------------------------------------------------

create or replace function private.prevent_maintenance_ticket_cost_change_after_imputation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.estimated_cost is distinct from old.estimated_cost
     or new.actual_cost is distinct from old.actual_cost
  then
    if exists (
      select 1 from public.deposit_ledger dl
      where dl.maintenance_ticket_id = old.id
    ) then
      raise exception 'Impossible de modifier le coût estimé ou le coût réel : ce ticket est déjà référencé par une imputation de caution'
        using detail = 'maintenance_ticket.cost.locked_after_imputation', errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$$;

create trigger trg_maintenance_tickets_prevent_cost_change_after_imputation
  before update on public.maintenance_tickets
  for each row execute function private.prevent_maintenance_ticket_cost_change_after_imputation();
