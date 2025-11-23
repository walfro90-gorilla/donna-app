-- =====================================================
-- POLÍTICAS DE SEGURIDAD PARA SUPABASE STORAGE
-- =====================================================

-- 1. BUCKET: profile-images
-- Permitir que usuarios suban sus propias fotos de perfil

-- Permitir subir imágenes (autenticado puede subir a su carpeta)
CREATE POLICY "Users can upload their own profile images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'profile-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Permitir leer todas las imágenes de perfil (público)
CREATE POLICY "Profile images are publicly accessible"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'profile-images');

-- Permitir actualizar sus propias imágenes
CREATE POLICY "Users can update their own profile images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'profile-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Permitir eliminar sus propias imágenes
CREATE POLICY "Users can delete their own profile images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- =====================================================
-- 2. BUCKET: restaurant-images
-- =====================================================

-- Permitir subir imágenes de restaurante
CREATE POLICY "Users can upload restaurant images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'restaurant-images');

-- Permitir leer todas las imágenes de restaurantes (público)
CREATE POLICY "Restaurant images are publicly accessible"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'restaurant-images');

-- Permitir actualizar imágenes de restaurante (dueños o admins)
CREATE POLICY "Restaurant owners can update their images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'restaurant-images' AND
  (
    -- El usuario es el dueño del restaurante
    (storage.foldername(name))[1] IN (
      SELECT id::text FROM restaurants WHERE owner_id = auth.uid()
    )
    OR
    -- El usuario es admin
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  )
);

-- Permitir eliminar imágenes de restaurante
CREATE POLICY "Restaurant owners can delete their images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'restaurant-images' AND
  (
    (storage.foldername(name))[1] IN (
      SELECT id::text FROM restaurants WHERE owner_id = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  )
);

-- =====================================================
-- 3. BUCKET: documents
-- =====================================================

-- Permitir subir documentos
CREATE POLICY "Users can upload their documents"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Solo admins pueden leer documentos (privados)
CREATE POLICY "Only admins can view documents"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents' AND
  (
    -- Es su propio documento
    (storage.foldername(name))[1] = auth.uid()::text
    OR
    -- Es admin
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  )
);

-- Permitir actualizar sus propios documentos
CREATE POLICY "Users can update their own documents"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Permitir eliminar sus propios documentos
CREATE POLICY "Users can delete their own documents"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'documents' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- =====================================================
-- 4. BUCKET: vehicle-images
-- =====================================================

-- Permitir subir imágenes de vehículos
CREATE POLICY "Delivery agents can upload vehicle images"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'vehicle-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Solo admins y el propio usuario pueden ver imágenes de vehículos
CREATE POLICY "Vehicle images viewable by owner and admin"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'vehicle-images' AND
  (
    (storage.foldername(name))[1] = auth.uid()::text
    OR
    EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  )
);

-- Permitir actualizar sus propias imágenes
CREATE POLICY "Delivery agents can update their vehicle images"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'vehicle-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Permitir eliminar sus propias imágenes
CREATE POLICY "Delivery agents can delete their vehicle images"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'vehicle-images' AND
  (storage.foldername(name))[1] = auth.uid()::text
);
