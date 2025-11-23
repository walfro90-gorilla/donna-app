-- =========================================================================
-- 2025-11-12_10_DROP_old_upsert_combo_atomic_variants.sql
-- Objetivo: eliminar TODAS las variantes/overloads existentes de
--           public.upsert_combo_atomic(...) para evitar ambigüedades
--           al crear/otorgar permisos a la nueva versión.
--
-- Uso: ejecutar este script ANTES de crear la v2.
-- =========================================================================

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT
      format('DROP FUNCTION IF EXISTS %I.%I(%s);', n.nspname, p.proname, pg_catalog.pg_get_function_identity_arguments(p.oid)) AS ddl
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'upsert_combo_atomic'
  LOOP
    EXECUTE r.ddl;
  END LOOP;
END $$;
