-- ============================================================================
-- FORMALISATION — filet de sécurité prospectif RLS (event trigger ensure_rls)
--
-- Ce mécanisme existait déjà sur dev, créé directement en base (hors
-- migration) à un moment non tracé. Diagnostic effectué avant d'écrire cette
-- migration (comparaison structurée dev réel vs rejeu à blanc des 47
-- migrations précédentes sur un projet jetable, puis vérification directe de
-- pg_class.relrowsecurity) : les 25 tables existantes ont chacune leur propre
-- `alter table ... enable row level security` explicite dans leur migration
-- d'origine, et 0 d'entre elles a RLS désactivé aujourd'hui. Aucune ne dépend
-- de ce trigger rétroactivement — il ne peut d'ailleurs pas agir
-- rétroactivement : le filtre `WHEN TAG IN (...)` au niveau de l'event
-- trigger ne se déclenche que sur CREATE TABLE / CREATE TABLE AS / SELECT
-- INTO, jamais sur une table déjà existante.
--
-- Son seul rôle, désormais formalisé : empêcher qu'une future migration crée
-- une table dans public sans activer RLS dessus, par oubli. Pur filet de
-- sécurité, redondant avec la discipline actuelle tant qu'elle est
-- respectée, actif seulement si elle ne l'est pas.
-- ============================================================================

create or replace function public.rls_auto_enable()
 returns event_trigger
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
as $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

drop event trigger if exists ensure_rls;

create event trigger ensure_rls
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  execute function public.rls_auto_enable();
