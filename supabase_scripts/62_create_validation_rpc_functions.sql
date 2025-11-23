-- =====================================================
-- 62_create_validation_rpc_functions.sql
-- =====================================================
-- Crear funciones RPC para validar disponibilidad de datos únicos
-- sin requerir autenticación (bypass RLS)
-- =====================================================

-- 1️⃣ Función para verificar disponibilidad de email
-- =====================================================
CREATE OR REPLACE FUNCTION public.check_email_availability(p_email TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  -- Verificar si el email ya existe (case-insensitive)
  SELECT EXISTS(
    SELECT 1 FROM public.users 
    WHERE LOWER(email) = LOWER(TRIM(p_email))
  ) INTO v_exists;

  -- Retornar TRUE si está disponible (no existe)
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_email_availability IS 
'Verifica si un email está disponible (no registrado). Retorna TRUE si está disponible.';


-- 2️⃣ Función para verificar disponibilidad de teléfono
-- =====================================================
CREATE OR REPLACE FUNCTION public.check_phone_availability(p_phone TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
  v_clean_phone TEXT;
BEGIN
  -- Limpiar el teléfono (solo números y +)
  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\d+]', '', 'g');

  -- Verificar si el teléfono ya existe
  SELECT EXISTS(
    SELECT 1 FROM public.users 
    WHERE phone = v_clean_phone
  ) INTO v_exists;

  -- Retornar TRUE si está disponible (no existe)
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_phone_availability IS 
'Verifica si un teléfono está disponible (no registrado). Retorna TRUE si está disponible.';


-- 3️⃣ Función para verificar disponibilidad de nombre de restaurante
-- =====================================================
CREATE OR REPLACE FUNCTION public.check_restaurant_name_availability(p_name TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exists BOOLEAN;
BEGIN
  -- Verificar si el nombre ya existe (case-insensitive)
  SELECT EXISTS(
    SELECT 1 FROM public.restaurants 
    WHERE LOWER(name) = LOWER(TRIM(p_name))
  ) INTO v_exists;

  -- Retornar TRUE si está disponible (no existe)
  RETURN NOT v_exists;
END;
$$;

COMMENT ON FUNCTION public.check_restaurant_name_availability IS 
'Verifica si un nombre de restaurante está disponible. Retorna TRUE si está disponible.';


-- 4️⃣ Otorgar permisos de ejecución a usuarios anónimos
-- =====================================================
GRANT EXECUTE ON FUNCTION public.check_email_availability TO anon;
GRANT EXECUTE ON FUNCTION public.check_email_availability TO authenticated;

GRANT EXECUTE ON FUNCTION public.check_phone_availability TO anon;
GRANT EXECUTE ON FUNCTION public.check_phone_availability TO authenticated;

GRANT EXECUTE ON FUNCTION public.check_restaurant_name_availability TO anon;
GRANT EXECUTE ON FUNCTION public.check_restaurant_name_availability TO authenticated;
