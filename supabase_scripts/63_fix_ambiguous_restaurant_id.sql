-- =====================================================
-- 63: CORRECCIÓN DE ERROR "restaurant_id is ambiguous"
-- =====================================================
-- Descripción: Corrige el error de referencia ambigua en la función calculate_restaurant_completion
-- Autor: Sistema de Corrección
-- Fecha: 2025

-- Eliminar la función existente con el bug
DROP FUNCTION IF EXISTS calculate_restaurant_completion(UUID);

-- Recrear la función con el parámetro renombrado para evitar ambigüedad
CREATE OR REPLACE FUNCTION calculate_restaurant_completion(p_restaurant_id UUID)
RETURNS INTEGER AS $$
DECLARE
    completion_score INTEGER := 0;
    total_fields INTEGER := 10;
    restaurant_record RECORD;
    product_count INTEGER;
BEGIN
    -- Obtener datos del restaurante
    SELECT * INTO restaurant_record
    FROM restaurants
    WHERE id = p_restaurant_id;
    
    IF NOT FOUND THEN
        RETURN 0;
    END IF;
    
    -- Campo obligatorio: nombre (10%)
    IF restaurant_record.name IS NOT NULL AND LENGTH(restaurant_record.name) > 0 THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo obligatorio: descripción (10%)
    IF restaurant_record.description IS NOT NULL AND LENGTH(restaurant_record.description) > 0 THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo obligatorio: logo (15%)
    IF restaurant_record.logo_url IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: imagen de portada (10%)
    IF restaurant_record.cover_image_url IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: imagen del menú (10%)
    IF restaurant_record.menu_image_url IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: tipo de cocina (5%)
    IF restaurant_record.cuisine_type IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: horarios (10%)
    IF restaurant_record.business_hours IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: radio de entrega (5%)
    IF restaurant_record.delivery_radius_km IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo recomendado: tiempo estimado (5%)
    IF restaurant_record.estimated_delivery_time_minutes IS NOT NULL THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Campo crítico: al menos 1 producto (20%)
    -- ✅ CORRECCIÓN: Usar p_restaurant_id en lugar de restaurant_id para evitar ambigüedad
    SELECT COUNT(*) INTO product_count
    FROM products
    WHERE restaurant_id = p_restaurant_id AND is_available = true;
    
    IF product_count > 0 THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Calcular porcentaje
    RETURN (completion_score * 100) / total_fields;
END;
$$ LANGUAGE plpgsql;

-- Comentario
COMMENT ON FUNCTION calculate_restaurant_completion IS 'Calcula el porcentaje de completado del perfil de un restaurante (0-100%)';

-- Log de éxito
DO $$
BEGIN
    RAISE NOTICE '✅ Función calculate_restaurant_completion() corregida exitosamente';
    RAISE NOTICE '✅ Bug de referencia ambigua "restaurant_id" resuelto';
END $$;
