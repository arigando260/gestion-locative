-- ============================================================================
-- MODULE 6h — DESCRIPTION OBLIGATOIRE POUR UN ÉLÉMENT DÉGRADÉ/HORS SERVICE.
--
-- Diagnostic préalable : aucun mécanisme équivalent n'existait sur
-- inspection_items (Module 6) — description est un simple text nullable,
-- sans contrainte croisée avec condition. Le patron le plus proche
-- (deposit_ledger_reason_required_for_imputation, Module 5) est un CHECK
-- constraint nu, qui ne peut porter ni message français précis ni slug
-- DETAIL stable. Même choix que Module 6g (observations à la
-- finalisation) : un trigger BEFORE INSERT OR UPDATE dédié.
--
-- Se déclenche sur condition IN ('degrade', 'hors_service') avec
-- description NULL ou vide après trim — 'bon'/'usage_normal' restent
-- inchangés (description toujours facultative). Couvre INSERT et UPDATE
-- OF condition, description : un item déjà en 'bon' sans description ne
-- doit pas pouvoir passer à 'degrade' sans en ajouter une.
-- ============================================================================

create or replace function private.validate_inspection_item_description_required()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.condition in ('degrade', 'hors_service')
     and (new.description is null or trim(new.description) = '') then
    raise exception 'Une description est obligatoire pour un élément en état "dégradé" ou "hors service"'
      using detail = 'inspection_item.description.required_for_condition', errcode = 'P0001';
  end if;
  return new;
end;
$$;

create trigger trg_inspection_items_validate_description_required
  before insert or update of condition, description on public.inspection_items
  for each row execute function private.validate_inspection_item_description_required();
