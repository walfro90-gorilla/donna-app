-- =====================================================
-- FIX: POLÍTICAS DE STORAGE PARA DOCUMENTOS
-- =====================================================
-- Propósito: Permitir que los documentos de permisos de restaurante
--            se suban con userId pero se asocien al restaurante
-- =====================================================

-- 1. Eliminar políticas existentes de documents
DROP POLICY IF EXISTS "documents_upload" ON storage.objects;
DROP POLICY IF EXISTS "documents_read" ON storage.objects;
DROP POLICY IF EXISTS "documents_update" ON storage.objects;
DROP POLICY IF EXISTS "documents_delete" ON storage.objects;

-- 2. DOCUMENTS (Privado - solo dueño y admins)
-- Permitir subir a carpeta con su propio user_id O restaurantId que le pertenezca
CREATE POLICY "documents_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documents'
    AND (
      -- Subir a su propia carpeta de usuario
      (storage.foldername(name))[1] = auth.uid()::text
      OR
      -- O subir a carpeta de su restaurante
      EXISTS (
        SELECT 1 FROM public.restaurants r
        WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
      )
    )
  );

-- Permitir leer solo sus propios documentos, de sus restaurantes, o si es admin
CREATE POLICY "documents_read" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      -- Sus propios documentos
      (storage.foldername(name))[1] = auth.uid()::text
      OR
      -- Documentos de sus restaurantes
      EXISTS (
        SELECT 1 FROM public.restaurants r
        WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
      )
      OR
      -- Es admin
      EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = auth.uid() AND u.role = 'admin'
      )
    )
  );

-- Permitir actualizar solo sus propios documentos o de sus restaurantes
CREATE POLICY "documents_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR
      EXISTS (
        SELECT 1 FROM public.restaurants r
        WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
      )
    )
  );

-- Permitir eliminar solo sus propios documentos o de sus restaurantes
CREATE POLICY "documents_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documents'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR
      EXISTS (
        SELECT 1 FROM public.restaurants r
        WHERE r.id::text = (storage.foldername(name))[1]
        AND r.user_id = auth.uid()
      )
    )
  );

-- =====================================================
-- ✅ POLÍTICAS DE DOCUMENTS ACTUALIZADAS
-- =====================================================

-- Verificar políticas
SELECT
  policyname,
  cmd,
  permissive,
  roles
FROM pg_policies
WHERE tablename = 'objects'
AND schemaname = 'storage'
AND policyname LIKE 'documents_%'
ORDER BY policyname;
