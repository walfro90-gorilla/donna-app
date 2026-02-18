-- =====================================================
-- DIAGNÓSTICO DE STORAGE - EJECUTAR PASO A PASO
-- =====================================================
-- Ejecutar cada bloque por separado en Supabase SQL Editor
-- y reportar los resultados.
-- =====================================================

-- =====================================================
-- BLOQUE 1: Ver TODAS las políticas activas en storage.objects
-- (puede haber políticas antiguas que no eliminamos)
-- =====================================================
SELECT
  policyname,
  cmd,
  permissive,
  roles,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY cmd, policyname;

-- =====================================================
-- BLOQUE 2: Ver triggers en storage.objects
-- =====================================================
SELECT
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'storage'
  AND event_object_table = 'objects'
ORDER BY trigger_name;

-- =====================================================
-- BLOQUE 3: Ver check constraints en storage.objects
-- =====================================================
SELECT
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'storage.objects'::regclass
  AND contype = 'c';

-- =====================================================
-- BLOQUE 4: Ver columnas de storage.objects
-- (para ver si path_tokens es GENERATED ALWAYS)
-- =====================================================
SELECT
  column_name,
  data_type,
  is_generated,
  generation_expression,
  column_default
FROM information_schema.columns
WHERE table_schema = 'storage'
  AND table_name = 'objects'
ORDER BY ordinal_position;

-- =====================================================
-- BLOQUE 5: ELIMINAR ABSOLUTAMENTE TODAS las políticas
-- de storage.objects (incluyendo cualquier nombre antiguo)
-- =====================================================
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT policyname
    FROM pg_policies
    WHERE tablename = 'objects' AND schemaname = 'storage'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
    RAISE NOTICE 'Dropped policy: %', r.policyname;
  END LOOP;
END $$;

-- Confirmar que quedaron 0 políticas:
SELECT count(*) AS policies_remaining
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage';

-- =====================================================
-- BLOQUE 6: Política MÍNIMA para probar (sin EXISTS, sin joins)
-- Si esto falla con 22P02 → el problema NO es nuestras políticas
-- Si esto funciona → el problema era el EXISTS subquery
-- =====================================================
CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'restaurant-images');

CREATE POLICY "restaurant_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'restaurant-images');

CREATE POLICY "restaurant_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'restaurant-images');

CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'restaurant-images');

-- Verificar que se crearon:
SELECT policyname, cmd FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY policyname;
