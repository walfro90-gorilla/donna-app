-- =====================================================
-- 2025-11-02_02_add_restaurant_uniqueness_rpcs.sql
-- =====================================================
-- RPCs para validar unicidad de nombre y teléfono en public.restaurants
-- Mantiene funciones base sin exclude_id y agrega variantes para actualización
-- Cumple con SECURITY DEFINER y bypass de RLS
-- =====================================================

-- 1) Disponibilidad de nombre (nuevo restaurante)
CREATE OR REPLACE FUNCTION public.check_restaurant_name_availability(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.restaurants r
    WHERE LOWER(r.name) = LOWER(TRIM(p_name))
  ) INTO v_exists;
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_restaurant_name_availability IS 'TRUE si el nombre no existe en restaurants.';

-- 2) Disponibilidad de nombre (actualización con exclusión por id)
CREATE OR REPLACE FUNCTION public.check_restaurant_name_available_for_update(p_name TEXT, p_exclude_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.restaurants r
    WHERE LOWER(r.name) = LOWER(TRIM(p_name))
      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)
  ) INTO v_exists;
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_restaurant_name_available_for_update IS 'TRUE si el nombre no existe en restaurants, excluyendo el id dado.';

-- 3) Disponibilidad de teléfono (nuevo restaurante)
CREATE OR REPLACE FUNCTION public.check_restaurant_phone_availability(p_phone TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
  v_clean_phone TEXT;
BEGIN
  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\d+]', '', 'g');
  IF v_clean_phone IS NULL OR v_clean_phone = '' THEN
    RETURN TRUE; -- teléfono opcional, considerar disponible
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.restaurants r
    WHERE r.phone = v_clean_phone
  ) INTO v_exists;
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_restaurant_phone_availability IS 'TRUE si el teléfono no existe en restaurants (usa formato canónico).';

-- 4) Disponibilidad de teléfono (actualización con exclusión por id)
CREATE OR REPLACE FUNCTION public.check_restaurant_phone_available_for_update(p_phone TEXT, p_exclude_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
  v_clean_phone TEXT;
BEGIN
  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\d+]', '', 'g');
  IF v_clean_phone IS NULL OR v_clean_phone = '' THEN
    RETURN TRUE; -- teléfono opcional
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.restaurants r
    WHERE r.phone = v_clean_phone
      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)
  ) INTO v_exists;
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_restaurant_phone_available_for_update IS 'TRUE si el teléfono no existe en restaurants, excluyendo el id dado.';

-- Permisos
GRANT EXECUTE ON FUNCTION public.check_restaurant_name_availability(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_restaurant_name_available_for_update(TEXT, UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_restaurant_phone_availability(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_restaurant_phone_available_for_update(TEXT, UUID) TO anon, authenticated;
