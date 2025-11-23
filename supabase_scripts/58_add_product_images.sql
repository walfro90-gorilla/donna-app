-- =====================================================
-- 58: AGREGAR SOPORTE DE IMÁGENES PARA PRODUCTOS
-- =====================================================
-- Descripción: Agrega columna para imágenes de productos del menú
-- Autor: Sistema de Onboarding
-- Fecha: 2025

-- Agregar columna de imagen a productos
ALTER TABLE products
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Crear índice para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_products_image_url ON products(image_url);

-- Comentarios
COMMENT ON COLUMN products.image_url IS 'URL de la imagen del producto en Supabase Storage';

-- Log de éxito
DO $$
BEGIN
    RAISE NOTICE '✅ Columna image_url agregada a productos exitosamente';
END $$;
