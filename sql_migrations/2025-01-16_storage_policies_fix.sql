-- ============================================================================
-- STORAGE POLICIES FIX - Políticas para subir evidencias fotográficas
-- ============================================================================
-- Fecha: 2025-01-16
-- Propósito: Permitir que repartidores suban evidencias fotográficas al bucket 'documents'
--            en la carpeta 'delivery-evidence/<userId>/<orderId>_evidence_<timestamp>.jpg'
-- ============================================================================

-- ============================================================================
-- 1. ELIMINAR POLÍTICAS EXISTENTES (si existen)
-- ============================================================================
-- Esto previene errores de "ya existe" al re-ejecutar el script

DROP POLICY IF EXISTS "Delivery agents can upload evidence" ON storage.objects;
DROP POLICY IF EXISTS "Delivery agents can view their evidence" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all evidence" ON storage.objects;


-- ============================================================================
-- 2. POLÍTICAS PARA EL BUCKET 'documents'
-- ============================================================================

-- 2.1 POLICY: Repartidores pueden SUBIR evidencias en su propia carpeta
-- Permite INSERT en: documents/delivery-evidence/<userId>/*
-- Solo para usuarios con rol 'delivery_agent' o 'admin'
CREATE POLICY "Delivery agents can upload evidence"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = 'delivery-evidence'
  AND (
    -- Repartidor solo puede subir a su propia carpeta
    (
      auth.uid()::text = (storage.foldername(name))[2]
      AND EXISTS (
        SELECT 1 FROM public.users
        WHERE id = auth.uid()
        AND role IN ('delivery_agent', 'admin')
      )
    )
    -- O es admin (puede subir en cualquier carpeta)
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  )
);


-- 2.2 POLICY: Repartidores pueden VER sus propias evidencias
-- Permite SELECT en: documents/delivery-evidence/<userId>/*
CREATE POLICY "Delivery agents can view their evidence"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = 'delivery-evidence'
  AND (
    -- Repartidor puede ver solo sus propias evidencias
    auth.uid()::text = (storage.foldername(name))[2]
    -- O es admin (puede ver todas)
    OR EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid()
      AND role = 'admin'
    )
  )
);


-- 2.3 POLICY: Admins pueden ver TODAS las evidencias
-- Permite SELECT para admins en toda la carpeta delivery-evidence
CREATE POLICY "Admins can view all evidence"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'documents'
  AND (storage.foldername(name))[1] = 'delivery-evidence'
  AND EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid()
    AND role = 'admin'
  )
);


-- ============================================================================
-- 3. VERIFICACIÓN (opcional - solo para debug)
-- ============================================================================
-- Descomenta para ver las políticas creadas:

-- SELECT 
--   schemaname, 
--   tablename, 
--   policyname, 
--   permissive, 
--   roles, 
--   cmd
-- FROM pg_policies 
-- WHERE tablename = 'objects' 
-- AND policyname ILIKE '%evidence%'
-- ORDER BY policyname;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
