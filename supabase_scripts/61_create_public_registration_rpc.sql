-- =====================================================
-- SOLUCIÓN DEFINITIVA: RPC Functions para Registro Público
-- =====================================================
-- Problema: Usuarios recién registrados no pueden insertar
-- directamente en users/restaurants/accounts debido a RLS
-- Solución: Crear funciones RPC con SECURITY DEFINER que
-- bypasean RLS y validan que el user_id pertenece a auth.users
-- =====================================================

-- =====================================================
-- 1. FUNCIÓN RPC: Crear perfil de usuario (bypasses RLS)
-- =====================================================

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

  -- Insertar perfil de usuario
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
-- 2. FUNCIÓN RPC: Crear restaurante (bypasses RLS)
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_restaurant_public(
  p_user_id UUID,
  p_name TEXT,
  p_status TEXT DEFAULT 'pending',
  p_location_lat DOUBLE PRECISION DEFAULT NULL,
  p_location_lon DOUBLE PRECISION DEFAULT NULL,
  p_location_place_id TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL,
  p_phone TEXT DEFAULT NULL,
  p_online BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Bypass RLS
AS $$
DECLARE
  v_restaurant_id UUID;
  v_result JSONB;
BEGIN
  -- Validar que el user_id existe en auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- Validar que el user_id existe en public.users
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist. Create user profile first.';
  END IF;

  -- Validar que no existe ya un restaurante para este usuario
  IF EXISTS (SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Restaurant already exists for this user';
  END IF;

  -- Insertar restaurante
  INSERT INTO public.restaurants (
    user_id,
    name,
    status,
    location_lat,
    location_lon,
    location_place_id,
    address,
    address_structured,
    phone,
    online,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_name,
    p_status,
    p_location_lat,
    p_location_lon,
    p_location_place_id,
    p_address,
    p_address_structured,
    p_phone,
    p_online,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_restaurant_id;

  -- Retornar resultado exitoso
  v_result := jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'message', 'Restaurant created successfully'
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
-- 3. FUNCIÓN RPC: Crear cuenta financiera (bypasses RLS)
-- =====================================================

CREATE OR REPLACE FUNCTION public.create_account_public(
  p_user_id UUID,
  p_account_type TEXT,
  p_balance NUMERIC DEFAULT 0.00
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER -- Bypass RLS
AS $$
DECLARE
  v_account_id UUID;
  v_result JSONB;
BEGIN
  -- Validar que el user_id existe en auth.users
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User ID does not exist in auth.users';
  END IF;

  -- Validar que el user_id existe en public.users
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User profile does not exist';
  END IF;

  -- Validar que no existe ya una cuenta para este usuario
  IF EXISTS (SELECT 1 FROM public.accounts WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'Account already exists for this user';
  END IF;

  -- Insertar cuenta financiera
  INSERT INTO public.accounts (
    user_id,
    account_type,
    balance,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_account_type,
    p_balance,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_account_id;

  -- Retornar resultado exitoso
  v_result := jsonb_build_object(
    'success', true,
    'account_id', v_account_id,
    'message', 'Account created successfully'
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
-- 4. OTORGAR PERMISOS A USUARIOS ANÓNIMOS
-- =====================================================

-- Permitir que usuarios anónimos ejecuten estas funciones
GRANT EXECUTE ON FUNCTION public.create_user_profile_public TO anon;
GRANT EXECUTE ON FUNCTION public.create_restaurant_public TO anon;
GRANT EXECUTE ON FUNCTION public.create_account_public TO anon;

-- Permitir también a usuarios autenticados
GRANT EXECUTE ON FUNCTION public.create_user_profile_public TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_restaurant_public TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_account_public TO authenticated;

-- =====================================================
-- ✅ FUNCIONES RPC CREADAS Y PERMISOS OTORGADOS
-- =====================================================

-- Verificar funciones creadas
SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname IN ('create_user_profile_public', 'create_restaurant_public', 'create_account_public')
ORDER BY p.proname;
