-- ============================================================================
-- MODULE 6i — AU MOINS UN CONSTAT REQUIS À LA FINALISATION D'UN ÉTAT DES
-- LIEUX.
--
-- Diagnostic préalable : aucun mécanisme, dans toute la lignée Module 6
-- (6, 6b, 6c, 6d, 6e, 6f, 6g, 6h) ni ailleurs dans le projet, n'exigeait la
-- présence d'au moins un inspection_items avant de finaliser — un état des
-- lieux pouvait être finalisé avec zéro constat.
--
-- Même famille que private.validate_inspection_finalize_requires_
-- observations (Module 6g) : trigger BEFORE UPDATE dédié sur
-- property_inspections, déclenché uniquement sur la transition vers
-- 'finalise', message français + slug DETAIL stable — un CHECK constraint
-- nu ne pourrait ni compter les lignes liées (inspection_items est une
-- autre table) ni porter ce message/slug.
-- ============================================================================

create or replace function private.validate_inspection_finalize_requires_item()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_item_count integer;
begin
  if new.document_status = 'finalise' and old.document_status is distinct from new.document_status then
    select count(*) into v_item_count
    from public.inspection_items
    where inspection_id = new.id;

    if v_item_count = 0 then
      raise exception 'Impossible de finaliser un état des lieux sans aucun constat'
        using detail = 'property_inspection.finalize.requires_at_least_one_item', errcode = 'P0001';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_property_inspections_validate_finalize_requires_item
  before update of document_status on public.property_inspections
  for each row execute function private.validate_inspection_finalize_requires_item();
