-- =====================================================
-- STORAGE POLICIES - VERSIÓN CORREGIDA
-- =====================================================
-- Propósito: Políticas de seguridad para Storage buckets
-- Orden: Ejecutar DESPUÉS de crear los buckets manualmente en la UI
-- =====================================================

-- NOTA IMPORTANTE: 
-- 1. Primero crea los buckets en Supabase Dashboard → Storage:
--    - profile-images (público)
--    - restaurant-images (público)
--    - documents (privado)
--    - vehicle-images (privado)
-- 2. Luego ejecuta este script

-- =====================================================
-- 1. ELIMINAR POLÍTICAS EXISTENTES
-- =====================================================

DROP POLICY IF EXISTS "profile_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "profile_images_read" ON storage.objects;
DROP POLICY IF EXISTS "profile_images_update" ON storage.objects;
DROP POLICY IF EXISTS "profile_images_delete" ON storage.objects;

DROP POLICY IF EXISTS "restaurant_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_read" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_update" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_delete" ON storage.objects;

DROP POLICY IF EXISTS "documents_upload" ON storage.objects;
DROP POLICY IF EXISTS "documents_read" ON storage.objects;
DROP POLICY IF EXISTS "documents_update" ON storage.objects;
DROP POLICY IF EXISTS "documents_delete" ON storage.objects;

DROP POLICY IF EXISTS "vehicle_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_read" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_update" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_delete" ON storage.objects;

-- =====================================================
-- 2. PROFILE-IMAGES (Público)
-- =====================================================

-- Permitir subir a carpeta con su propio user_id
CREATE POLICY "profile_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir lectura pública
CREATE POLICY "profile_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'profile-images');

-- Permitir actualizar solo sus propias imágenes
CREATE POLICY "profile_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir eliminar solo sus propias imágenes
CREATE POLICY "profile_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- 3. RESTAURANT-IMAGES (Público)
-- =====================================================

-- Permitir subir a carpeta de su restaurante
CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
      AND r.user_id = auth.uid()
    )
  );

-- Permitir lectura pública
CREATE POLICY "restaurant_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'restaurant-images');

-- Permitir actualizar solo imágenes de su restaurante
CREATE POLICY "restaurant_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
      AND r.user_id = auth.uid()
    )
  );

-- Permitir eliminar solo imágenes de su restaurante
CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = (storage.foldername(name))[1]
      AND r.user_id = auth.uid()
    )
  );

-- =====================================================
-- 4. DOCUMENTS (Privado - solo dueño y admins)
-- =====================================================

-- Permitir subir a carpeta con su propio user_id
CREATE POLICY "documents_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir leer solo sus propios documentos o si es admin
CREATE POLICY "documents_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'admin'
      )
    )
  );

-- Permitir actualizar solo sus propios documentos
CREATE POLICY "documents_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir eliminar solo sus propios documentos
CREATE POLICY "documents_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- 5. VEHICLE-IMAGES (Privado - solo dueño y admins)
-- =====================================================

-- Permitir subir a carpeta con su propio user_id
CREATE POLICY "vehicle_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir leer solo sus propias imágenes o si es admin
CREATE POLICY "vehicle_images_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'admin'
      )
    )
  );

-- Permitir actualizar solo sus propias imágenes
CREATE POLICY "vehicle_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Permitir eliminar solo sus propias imágenes
CREATE POLICY "vehicle_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- ✅ POLÍTICAS DE STORAGE APLICADAS CORRECTAMENTE
-- =====================================================

-- Para verificar que las políticas se aplicaron:
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd
FROM pg_policies
WHERE tablename = 'objects'
AND schemaname = 'storage'
ORDER BY policyname;

-- ✅ Deberían aparecer 20 políticas (4 por cada bucket)
