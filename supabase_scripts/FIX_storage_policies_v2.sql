-- =====================================================
-- FIX POLÍTICAS RLS - V2 (sin storage.foldername)
-- =====================================================
-- Propósito: Corregir error 22P02 "invalid_text_representation"
--            causado por storage.foldername() no disponible
--            en esta versión de Supabase.
-- Solución:  Usar split_part(name, '/', 1) en su lugar.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- =====================================================

-- =====================================================
-- PASO 1: ELIMINAR POLÍTICAS PROBLEMÁTICAS
-- =====================================================

DROP POLICY IF EXISTS "profile_images_upload"    ON storage.objects;
DROP POLICY IF EXISTS "profile_images_read"      ON storage.objects;
DROP POLICY IF EXISTS "profile_images_update"    ON storage.objects;
DROP POLICY IF EXISTS "profile_images_delete"    ON storage.objects;

DROP POLICY IF EXISTS "restaurant_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_read"   ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_update" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_delete" ON storage.objects;

DROP POLICY IF EXISTS "documents_upload"         ON storage.objects;
DROP POLICY IF EXISTS "documents_read"           ON storage.objects;
DROP POLICY IF EXISTS "documents_update"         ON storage.objects;
DROP POLICY IF EXISTS "documents_delete"         ON storage.objects;

DROP POLICY IF EXISTS "vehicle_images_upload"    ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_read"      ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_update"    ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_delete"    ON storage.objects;

-- =====================================================
-- PASO 2: PROFILE-IMAGES (Público)
-- Path: <userId>/profile_*.jpg
-- split_part(name, '/', 1) = userId
-- =====================================================

CREATE POLICY "profile_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

CREATE POLICY "profile_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'profile-images');

CREATE POLICY "profile_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

CREATE POLICY "profile_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

-- =====================================================
-- PASO 3: RESTAURANT-IMAGES (Público)
-- Path: <restaurantId>/logo_*.jpg
-- split_part(name, '/', 1) = restaurantId
-- =====================================================

CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = split_part(name, '/', 1)
        AND r.user_id = (select auth.uid())
    )
  );

CREATE POLICY "restaurant_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'restaurant-images');

CREATE POLICY "restaurant_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = split_part(name, '/', 1)
        AND r.user_id = (select auth.uid())
    )
  );

CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = split_part(name, '/', 1)
        AND r.user_id = (select auth.uid())
    )
  );

-- =====================================================
-- PASO 4: DOCUMENTS (Privado)
-- Path A: <userId>/business_permit_*.jpg  → split_part[1] = userId
-- Path B: delivery-evidence/<userId>/...  → split_part[1] = 'delivery-evidence'
--                                           split_part[2] = userId
-- =====================================================

CREATE POLICY "documents_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (
      split_part(name, '/', 1) = (select auth.uid()::text)
      OR (
        split_part(name, '/', 1) = 'delivery-evidence'
        AND split_part(name, '/', 2) = (select auth.uid()::text)
      )
    )
  );

CREATE POLICY "documents_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      split_part(name, '/', 1) = (select auth.uid()::text)
      OR split_part(name, '/', 1) = 'delivery-evidence'
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = (select auth.uid()) AND u.role = 'admin'
      )
    )
  );

CREATE POLICY "documents_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

CREATE POLICY "documents_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

-- =====================================================
-- PASO 5: VEHICLE-IMAGES (Privado)
-- Path: <userId>/photo_*.jpg
-- split_part(name, '/', 1) = userId
-- =====================================================

CREATE POLICY "vehicle_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

CREATE POLICY "vehicle_images_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (
      split_part(name, '/', 1) = (select auth.uid()::text)
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = (select auth.uid()) AND u.role = 'admin'
      )
    )
  );

CREATE POLICY "vehicle_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

CREATE POLICY "vehicle_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (select auth.uid()::text)
  );

-- =====================================================
-- VERIFICACIÓN
-- =====================================================

SELECT policyname, cmd, roles
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY policyname;

-- ✅ Deben aparecer 16 políticas (4 por bucket)
