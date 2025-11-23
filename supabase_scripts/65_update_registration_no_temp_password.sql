-- =====================================================
-- ACTUALIZACIÓN: Eliminar contraseña temporal del registro
-- =====================================================
-- Los usuarios ahora establecen su propia contraseña durante
-- el registro. Ya no necesitamos el parámetro is_temp_password.
-- =====================================================

-- 1. ACTUALIZAR FUNCIÓN RPC: create_user_profile_public
-- Eliminar parámetro p_is_temp_password y campo metadata
CREATE OR REPLACE FUNCTION public.create_user_profile_public(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_phone TEXT,
  p_address TEXT,
  p_role TEXT,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Bypass RLS
AS $$
DECLARE
  v_result JSONB;
BEGIN
  -- Validar que el user_id existe en auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- Validar que no existe ya el perfil
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile already exists';
  END IF;

  -- Insertar perfil de usuario (sin metadata)
  INSERT INTO public.users (
    id,
    email,
    name,
    phone,
    address,
    role,
    email_confirm,
    lat,
    lon,
    address_structured,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_email,
    p_name,
    p_phone,
    p_address,
    p_role,
    false, -- Email no confirmado aún
    p_lat,
    p_lon,
    p_address_structured,
    NOW(),
    NOW()
  );

  -- Retornar resultado exitoso
  v_result := jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'message', 'User profile created successfully'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    -- Retornar error
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

-- =====================================================
-- 2. LIMPIAR datos existentes (opcional)
-- =====================================================
-- Si deseas limpiar el campo metadata.is_temp_password de usuarios existentes:

-- UPDATE public.users 
-- SET metadata = metadata - 'is_temp_password'
-- WHERE metadata ? 'is_temp_password';

-- =====================================================
-- ✅ ACTUALIZACIÓN COMPLETADA
-- =====================================================
-- Ahora los usuarios establecen su propia contraseña
-- durante el registro y no hay contraseñas temporales.
-- =====================================================
