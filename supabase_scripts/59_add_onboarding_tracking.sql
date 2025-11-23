-- =====================================================
-- 59: SISTEMA DE RASTREO DE ONBOARDING
-- =====================================================
-- Descripción: Rastrea si el usuario ya completó el tour de onboarding
-- Autor: Sistema de Onboarding
-- Fecha: 2025

-- Agregar columnas de onboarding a users
ALTER TABLE users
ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS onboarding_completed_at TIMESTAMP WITH TIME ZONE;

-- Agregar columnas de onboarding a restaurants
ALTER TABLE restaurants
ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS onboarding_step INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS profile_completion_percentage INTEGER DEFAULT 0;

-- Crear índices
CREATE INDEX IF NOT EXISTS idx_users_onboarding ON users(onboarding_completed);
CREATE INDEX IF NOT EXISTS idx_restaurants_onboarding ON restaurants(onboarding_completed);
CREATE INDEX IF NOT EXISTS idx_restaurants_completion ON restaurants(profile_completion_percentage);

-- Comentarios
COMMENT ON COLUMN users.onboarding_completed IS 'Si el usuario completó el tour inicial';
COMMENT ON COLUMN users.onboarding_completed_at IS 'Fecha cuando completó el onboarding';
COMMENT ON COLUMN restaurants.onboarding_completed IS 'Si el restaurante completó el setup wizard';
COMMENT ON COLUMN restaurants.onboarding_step IS 'Último paso completado del wizard (0-5)';
COMMENT ON COLUMN restaurants.profile_completion_percentage IS 'Porcentaje de completado del perfil (0-100)';

-- Función para calcular el porcentaje de completado de un restaurante
CREATE OR REPLACE FUNCTION calculate_restaurant_completion(restaurant_id UUID)
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
    WHERE id = restaurant_id;
    
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
    SELECT COUNT(*) INTO product_count
    FROM products
    WHERE restaurant_id = restaurant_id AND is_available = true;
    
    IF product_count > 0 THEN
        completion_score := completion_score + 1;
    END IF;
    
    -- Calcular porcentaje
    RETURN (completion_score * 100) / total_fields;
END;
$$ LANGUAGE plpgsql;

-- Trigger para actualizar automáticamente el porcentaje de completado
CREATE OR REPLACE FUNCTION update_restaurant_completion_trigger()
RETURNS TRIGGER AS $$
BEGIN
    NEW.profile_completion_percentage := calculate_restaurant_completion(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Crear trigger
DROP TRIGGER IF EXISTS trg_update_restaurant_completion ON restaurants;
CREATE TRIGGER trg_update_restaurant_completion
BEFORE INSERT OR UPDATE ON restaurants
FOR EACH ROW
EXECUTE FUNCTION update_restaurant_completion_trigger();

-- Trigger para actualizar cuando se agregan/eliminan productos
CREATE OR REPLACE FUNCTION update_restaurant_completion_on_product_change()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE restaurants
    SET profile_completion_percentage = calculate_restaurant_completion(COALESCE(NEW.restaurant_id, OLD.restaurant_id))
    WHERE id = COALESCE(NEW.restaurant_id, OLD.restaurant_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_update_restaurant_on_product ON products;
CREATE TRIGGER trg_update_restaurant_on_product
AFTER INSERT OR UPDATE OR DELETE ON products
FOR EACH ROW
EXECUTE FUNCTION update_restaurant_completion_on_product_change();

-- Log de éxito
DO $$
BEGIN
    RAISE NOTICE '✅ Sistema de rastreo de onboarding creado exitosamente';
    RAISE NOTICE '✅ Función calculate_restaurant_completion() creada';
    RAISE NOTICE '✅ Triggers automáticos configurados';
END $$;
