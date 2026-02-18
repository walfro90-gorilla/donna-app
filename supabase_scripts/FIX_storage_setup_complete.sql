-- =====================================================
-- SETUP COMPLETO DE STORAGE - BUCKETS + POLÍTICAS RLS
-- =====================================================
-- Propósito: Crear los 4 buckets de storage y aplicar
--            las políticas de seguridad correctas.
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- =====================================================

-- =====================================================
-- PASO 1: CREAR BUCKETS (idempotente)
-- =====================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'profile-images',
    'profile-images',
    true,  -- público: avatares son visibles por todos
    5242880,  -- 5 MB
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif','image/svg+xml']
  ),
  (
    'restaurant-images',
    'restaurant-images',
    true,  -- público: logos/portadas son visibles en el catálogo
    5242880,
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/gif','image/svg+xml']
  ),
  (
    'documents',
    'documents',
    false, -- privado: permisos de negocio, ID, etc.
    10485760,  -- 10 MB
    ARRAY['image/jpeg','image/jpg','image/png','image/webp','image/pdf']
  ),
  (
    'vehicle-images',
    'vehicle-images',
    false, -- privado: fotos de vehículos de repartidores
    5242880,
    ARRAY['image/jpeg','image/jpg','image/png','image/webp']
  )
ON CONFLICT (id) DO UPDATE SET
  public           = EXCLUDED.public,
  file_size_limit  = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- =====================================================
-- PASO 2: ELIMINAR POLÍTICAS ANTIGUAS (limpieza)
-- =====================================================

DROP POLICY IF EXISTS "profile_images_upload"   ON storage.objects;
DROP POLICY IF EXISTS "profile_images_read"     ON storage.objects;
DROP POLICY IF EXISTS "profile_images_update"   ON storage.objects;
DROP POLICY IF EXISTS "profile_images_delete"   ON storage.objects;

DROP POLICY IF EXISTS "restaurant_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_read"   ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_update" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_delete" ON storage.objects;

DROP POLICY IF EXISTS "documents_upload" ON storage.objects;
DROP POLICY IF EXISTS "documents_read"   ON storage.objects;
DROP POLICY IF EXISTS "documents_update" ON storage.objects;
DROP POLICY IF EXISTS "documents_delete" ON storage.objects;

DROP POLICY IF EXISTS "vehicle_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_read"   ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_update" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_images_delete" ON storage.objects;

-- =====================================================
-- PASO 3: PROFILE-IMAGES (Público)
-- =====================================================

-- Subir: solo a la carpeta con el propio user_id
CREATE POLICY "profile_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Leer: acceso público
CREATE POLICY "profile_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'profile-images');

-- Actualizar: solo sus propios archivos
CREATE POLICY "profile_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Eliminar: solo sus propios archivos
CREATE POLICY "profile_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'profile-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- PASO 4: RESTAURANT-IMAGES (Público)
-- =====================================================
-- Path esperado: <restaurantId>/logo_*.jpg, <restaurantId>/cover_*.jpg
-- La carpeta raíz debe coincidir con el ID de un restaurante del usuario.

-- Subir: solo a la carpeta del restaurante propio
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

-- Leer: acceso público
CREATE POLICY "restaurant_images_read" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'restaurant-images');

-- Actualizar: solo imágenes del restaurante propio
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

-- Eliminar: solo imágenes del restaurante propio
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
-- PASO 5: DOCUMENTS (Privado - dueño + admins)
-- =====================================================
-- Path esperado: <userId>/id_front_*.jpg, <userId>/business_permit_*.jpg
--                delivery-evidence/<userId>/<orderId>_*.jpg

-- Subir: carpeta raíz = propio user_id
-- También permite la ruta de evidencias de no-entrega:
--   delivery-evidence/<userId>/<orderId>_evidence_*.jpg
CREATE POLICY "documents_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR (
        (storage.foldername(name))[1] = 'delivery-evidence'
        AND (storage.foldername(name))[2] = auth.uid()::text
      )
    )
  );

-- Leer: dueño del archivo o administrador
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

-- Actualizar: solo sus propios documentos
CREATE POLICY "documents_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Eliminar: solo sus propios documentos
CREATE POLICY "documents_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- PASO 6: VEHICLE-IMAGES (Privado - dueño + admins)
-- =====================================================
-- Path esperado: <userId>/photo_*.jpg, <userId>/registration_*.jpg

-- Subir: carpeta raíz = propio user_id
CREATE POLICY "vehicle_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Leer: dueño o administrador
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

-- Actualizar: solo sus propios archivos
CREATE POLICY "vehicle_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Eliminar: solo sus propios archivos
CREATE POLICY "vehicle_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'vehicle-images'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- =====================================================
-- VERIFICACIÓN: confirmar buckets y políticas creados
-- =====================================================

-- Mostrar buckets existentes:
SELECT id, name, public, file_size_limit
FROM storage.buckets
ORDER BY id;

-- Mostrar políticas activas:
SELECT policyname, cmd, roles
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY policyname;

-- ✅ Deberían aparecer 4 buckets y 16 políticas (4 por bucket)
