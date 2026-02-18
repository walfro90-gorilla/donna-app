-- =====================================================
-- POLÍTICAS STORAGE - VERSIÓN FINAL CORRECTA
-- =====================================================
-- Root cause del 22P02: políticas viejas usaban r.name
-- (nombre del restaurante) en lugar de `name` (path del
-- archivo en storage). Al castear "Chihuahua Market"::uuid → error.
--
-- Esta versión usa siempre `name` (path del objeto storage).
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- =====================================================

-- =====================================================
-- PASO 1: Limpiar TODAS las políticas existentes
-- (por si quedó alguna del diagnóstico anterior)
-- =====================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE tablename = 'objects' AND schemaname = 'storage'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
  END LOOP;
END $$;

-- =====================================================
-- PASO 2: PROFILE-IMAGES (público)
-- Path: <userId>/profile_*.jpg
-- `name` = path del objeto, split_part(name,'/',1) = userId
-- =====================================================

CREATE POLICY "profile_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "profile_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'profile-images');

CREATE POLICY "profile_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "profile_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

-- =====================================================
-- PASO 3: RESTAURANT-IMAGES (público)
-- Path: <restaurantId>/logo_*.jpg
-- `name` = path del objeto, split_part(name,'/',1) = restaurantId
-- CRÍTICO: usar `name` (storage path), NO `r.name` (nombre del restaurante)
-- =====================================================

CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = split_part(name, '/', 1)  -- `name` = storage path ✓
        AND r.user_id = (SELECT auth.uid())
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
      WHERE r.id::text = split_part(name, '/', 1)  -- `name` = storage path ✓
        AND r.user_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id::text = split_part(name, '/', 1)  -- `name` = storage path ✓
        AND r.user_id = (SELECT auth.uid())
    )
  );

-- =====================================================
-- PASO 4: DOCUMENTS (privado)
-- Path A: <userId>/business_permit_*.jpg
-- Path B: delivery-evidence/<userId>/<orderId>_evidence_*.jpg
-- =====================================================

CREATE POLICY "documents_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (
      split_part(name, '/', 1) = (SELECT auth.uid()::text)
      OR (
        split_part(name, '/', 1) = 'delivery-evidence'
        AND split_part(name, '/', 2) = (SELECT auth.uid()::text)
      )
    )
  );

CREATE POLICY "documents_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      split_part(name, '/', 1) = (SELECT auth.uid()::text)
      OR split_part(name, '/', 1) = 'delivery-evidence'
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = (SELECT auth.uid()) AND u.role = 'admin'
      )
    )
  );

CREATE POLICY "documents_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "documents_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

-- =====================================================
-- PASO 5: VEHICLE-IMAGES (privado)
-- Path: <userId>/photo_*.jpg
-- =====================================================

CREATE POLICY "vehicle_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "vehicle_images_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (
      split_part(name, '/', 1) = (SELECT auth.uid()::text)
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = (SELECT auth.uid()) AND u.role = 'admin'
      )
    )
  );

CREATE POLICY "vehicle_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "vehicle_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

-- =====================================================
-- VERIFICACIÓN FINAL
-- =====================================================
SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY cmd, policyname;

-- ✅ Deben aparecer exactamente 16 políticas (4 por bucket)
