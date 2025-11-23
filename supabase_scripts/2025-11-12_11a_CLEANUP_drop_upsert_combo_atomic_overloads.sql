-- Limpieza segura de overloads antiguos de la RPC upsert_combo_atomic
-- Ejecuta este script ANTES de crear la nueva versión para evitar ambigüedades

DO $$
DECLARE
  r RECORD;
  v_dropped int := 0;
BEGIN
  FOR r IN
    SELECT n.nspname AS schema_name,
           p.proname  AS func_name,
           oidvectortypes(p.proargtypes) AS argtypes
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname  = 'upsert_combo_atomic'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.schema_name, r.func_name, r.argtypes);
    v_dropped := v_dropped + 1;
  END LOOP;

  RAISE NOTICE 'Overloads eliminados: %', v_dropped;
END $$;
