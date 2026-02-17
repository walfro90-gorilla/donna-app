-- =====================================================
-- TRIGGER: Calcular automáticamente el porcentaje de 
-- completitud del perfil del restaurante
-- =====================================================

-- Función que calcula el porcentaje de completitud
CREATE OR REPLACE FUNCTION calculate_restaurant_profile_completion()
RETURNS TRIGGER AS $$
DECLARE
  total_fields INTEGER := 15; -- Total de campos importantes
  completed_fields INTEGER := 0;
  completion_percentage INTEGER;
BEGIN
  -- Campos obligatorios básicos (siempre cuentan)
  IF NEW.name IS NOT NULL AND LENGTH(TRIM(NEW.name)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  -- Campos opcionales pero importantes
  IF NEW.description IS NOT NULL AND LENGTH(TRIM(NEW.description)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.logo_url IS NOT NULL AND LENGTH(TRIM(NEW.logo_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.cover_image_url IS NOT NULL AND LENGTH(TRIM(NEW.cover_image_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.cuisine_type IS NOT NULL AND LENGTH(TRIM(NEW.cuisine_type)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.address IS NOT NULL AND LENGTH(TRIM(NEW.address)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.phone IS NOT NULL AND LENGTH(TRIM(NEW.phone)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.location_lat IS NOT NULL AND NEW.location_lon IS NOT NULL THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.business_hours IS NOT NULL THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.delivery_radius_km IS NOT NULL AND NEW.delivery_radius_km > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.min_order_amount IS NOT NULL AND NEW.min_order_amount >= 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  -- Redes sociales (opcionales pero suman)
  IF NEW.facebook_url IS NOT NULL AND LENGTH(TRIM(NEW.facebook_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.instagram_url IS NOT NULL AND LENGTH(TRIM(NEW.instagram_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  IF NEW.website_url IS NOT NULL AND LENGTH(TRIM(NEW.website_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  -- Permisos de negocio
  IF NEW.business_permit_url IS NOT NULL AND LENGTH(TRIM(NEW.business_permit_url)) > 0 THEN
    completed_fields := completed_fields + 1;
  END IF;

  -- Calcular porcentaje
  completion_percentage := (completed_fields * 100) / total_fields;

  -- Asignar el porcentaje calculado
  NEW.profile_completion_percentage := completion_percentage;

  -- Marcar onboarding como completado si el perfil está al 100%
  IF completion_percentage >= 100 THEN
    NEW.onboarding_completed := true;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Eliminar trigger existente si existe
DROP TRIGGER IF EXISTS trigger_calculate_restaurant_profile_completion ON public.restaurants;

-- Crear trigger que se ejecuta ANTES de INSERT o UPDATE
CREATE TRIGGER trigger_calculate_restaurant_profile_completion
  BEFORE INSERT OR UPDATE ON public.restaurants
  FOR EACH ROW
  EXECUTE FUNCTION calculate_restaurant_profile_completion();

-- Comentario para documentación
COMMENT ON FUNCTION calculate_restaurant_profile_completion() IS 
'Calcula automáticamente el porcentaje de completitud del perfil del restaurante basándose en 15 campos clave. Se ejecuta antes de cada INSERT o UPDATE en la tabla restaurants.';
