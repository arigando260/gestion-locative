-- ============================================================================
-- MODULE 6b — CORRECTIF : finalized_at manipulable via INSERT direct
-- Le trigger posé au Module 6 ne couvrait que l'UPDATE (transition
-- brouillon -> finalisé). Un profil interne pouvait insérer directement une
-- ligne avec document_status='finalise' et un finalized_at arbitraire,
-- contournant la garantie "jamais par le client" et permettant de
-- fabriquer une acceptation tacite artificiellement ancienne. Confirmé
-- empiriquement avant correction.
-- ============================================================================

create or replace function private.set_inspection_finalized_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if TG_OP = 'INSERT' then
    if new.document_status = 'finalise' then
      new.finalized_at := now();
    else
      new.finalized_at := null;
    end if;
    return new;
  end if;

  -- TG_OP = 'UPDATE' : comportement inchangé par rapport au Module 6.
  if new.document_status = 'finalise' and old.document_status <> 'finalise' then
    new.finalized_at := now();
    return new;
  end if;

  if new.finalized_at is distinct from old.finalized_at then
    raise exception 'finalized_at est immuable, posé uniquement par le serveur au moment de la finalisation';
  end if;

  return new;
end;
$$;

drop trigger trg_property_inspections_set_finalized_at on public.property_inspections;

create trigger trg_property_inspections_set_finalized_at
  before insert or update on public.property_inspections
  for each row execute function private.set_inspection_finalized_at();
