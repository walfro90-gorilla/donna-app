-- =====================================================
-- FIX: restaurant-images policies sin EXISTS subquery
-- =====================================================
-- Causa del 403: la política usaba EXISTS (...FROM public.restaurants r...)
-- lo cual falla porque la RLS de public.restaurants impide que la consulta
-- de storage pueda ver la fila desde ese contexto.
--
-- Solución: usar userId en el path (ya hecho en Dart) y validar solo con
-- split_part(name,'/',1) = auth.uid()::text, igual que profile-images.
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- =====================================================

-- Eliminar las 3 políticas de restaurant-images que usan EXISTS
DROP POLICY IF EXISTS "restaurant_images_upload" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_update" ON storage.objects;
DROP POLICY IF EXISTS "restaurant_images_delete" ON storage.objects;

-- Recrear sin EXISTS (path = <userId>/logo_*.jpg, cover_*.jpg, etc.)
CREATE POLICY "restaurant_images_upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "restaurant_images_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

CREATE POLICY "restaurant_images_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'restaurant-images'
    AND split_part(name, '/', 1) = (SELECT auth.uid()::text)
  );

-- Verificar: deben seguir siendo 16 políticas en total
SELECT policyname, cmd
FROM pg_policies
WHERE tablename = 'objects' AND schemaname = 'storage'
ORDER BY cmd, policyname;
