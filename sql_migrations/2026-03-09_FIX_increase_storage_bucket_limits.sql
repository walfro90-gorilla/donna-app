-- Ampliar límite de tamaño de archivos en los buckets de imágenes a 10MB
-- Ejecutar en Supabase SQL Editor (requiere permisos de servicio)

UPDATE storage.buckets
SET file_size_limit = 10485760  -- 10 MB en bytes
WHERE id IN ('restaurant-images', 'profile-images', 'documents', 'vehicle-images');

-- Verificar resultado
SELECT id, name, file_size_limit, (file_size_limit / 1048576.0)::numeric(5,1) AS limit_mb
FROM storage.buckets
ORDER BY id;
