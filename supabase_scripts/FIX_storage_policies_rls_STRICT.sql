-- =====================================================
-- FIX: STORAGE POLICIES - RLS ESTRICTO
-- =====================================================
-- Propósito: Políticas RLS que validan propiedad del restaurante
-- Fecha: Solución al error 403 con validación estricta
-- =====================================================
-- IMPORTANTE: Usa este script si quieres máxima seguridad
-- y validar que el usuario sea dueño del restaurante
-- =====================================================

-- =====================================================
-- ELIMINAR POLÍTICAS EXISTENTES
-- =====================================================

DROP POLICY IF EXISTS "restaurant_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_read" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_update" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_delete" ON storage.objects;

-- =====================================================
-- CREAR POLÍTICAS ESTRICTAS PARA restaurant-images
-- =====================================================

-- Subir: Solo si el usuario es dueño del restaurante
CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 
      FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
    )
  );

-- Leer: Acceso público (las imágenes de restaurantes son públicas)
CREATE POLICY "restaurant_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'restaurant-images');

-- Actualizar: Solo si el usuario es dueño del restaurante
CREATE POLICY "restaurant_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 
      FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
    )
  );

-- Eliminar: Solo si el usuario es dueño del restaurante
CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 
      FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
    )
  );

-- =====================================================
-- VERIFICACIÓN DE POLÍTICAS
-- =====================================================

-- Ver las políticas de restaurant-images
SELECT
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'objects'
  AND schemaname = 'storage'
  AND policyname LIKE 'restaurant_images%'
ORDER BY policyname;

-- =====================================================
-- TEST: Verificar que funciona
-- =====================================================
-- Ejecuta esto para probar la política (reemplaza los UUIDs):
-- 
-- SELECT EXISTS (
--   SELECT 1 
--   FROM public.restaurants r
--   WHERE r.id::text = '5afb0bac-e526-423e-b74e-695de7554abf'
--     AND r.user_id = '203b6855-db86-4764-a33d-380efda49436'
-- );
-- 
-- ✅ Debería retornar TRUE si el usuario es dueño del restaurante
-- =====================================================

-- =====================================================
-- TROUBLESHOOTING
-- =====================================================
-- Si sigues teniendo el error 403:
--
-- 1. Verifica que el usuario esté autenticado:
--    SELECT auth.uid();
--    Debería retornar el UUID del usuario
--
-- 2. Verifica que el restaurante existe y pertenece al usuario:
--    SELECT id, user_id, name 
--    FROM public.restaurants 
--    WHERE user_id = auth.uid();
--
-- 3. Verifica la estructura del path:
--    El path debe ser: <restaurant_id>/<filename>
--    Ejemplo: '5afb0bac-e526-423e-b74e-695de7554abf/logo_123.jpg'
--
-- 4. Si aún falla, usa temporalmente la versión permisiva:
--    Ejecuta el script FIX_storage_policies_rls.sql
-- =====================================================
