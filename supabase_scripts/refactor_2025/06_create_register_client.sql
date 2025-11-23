-- =====================================================
-- FASE 5A: RPC DE REGISTRO DE CLIENTES
-- =====================================================
-- Proceso atómico y profesional para registro de clientes
-- Tiempo estimado: 5 minutos
-- =====================================================

CREATE OR REPLACE FUNCTION public.register_client(
  p_email TEXT,
  p_password TEXT,
  p_name TEXT,
  p_phone TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_auth_user JSONB;
  v_result JSONB;
  v_error TEXT;
BEGIN
  -- ====================================
  -- VALIDACIONES PREVIAS
  -- ====================================
  
  -- Validar email
  IF p_email IS NULL OR p_email !~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$' THEN
    RAISE EXCEPTION 'Email inválido: %', p_email;
  END IF;

  -- Validar password (mínimo 6 caracteres)
  IF p_password IS NULL OR LENGTH(p_password) < 6 THEN
    RAISE EXCEPTION 'La contraseña debe tener al menos 6 caracteres';
  END IF;

  -- Validar que no exista el email
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
    RAISE EXCEPTION 'El email ya está registrado';
  END IF;

  -- Validar que no exista el teléfono (si se proporciona)
  IF p_phone IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.users WHERE phone = p_phone
  ) THEN
    RAISE EXCEPTION 'El teléfono ya está registrado';
  END IF;

  -- ====================================
  -- PASO 1: Crear usuario en auth.users
  -- ====================================
  BEGIN
    -- Usar la función de Supabase para crear usuario
    v_auth_user := auth.sign_up_v2(
      jsonb_build_object(
        'email', p_email,
        'password', p_password,
        'email_confirm', FALSE,
        'user_metadata', jsonb_build_object(
          'name', p_name,
          'role', 'cliente'
        )
      )
    );

    v_user_id := (v_auth_user->>'id')::UUID;

    IF v_user_id IS NULL THEN
      RAISE EXCEPTION 'Error al crear usuario en auth.users';
    END IF;

  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
      INSERT INTO debug_logs (scope, message, meta)
      VALUES ('REGISTER_CLIENT_ERROR', 'Error en auth.sign_up_v2', 
              jsonb_build_object('error', v_error, 'email', p_email));
      RAISE EXCEPTION 'Error al crear usuario: %', v_error;
  END;

  -- ====================================
  -- PASO 2: Crear registro en public.users
  -- ====================================
  INSERT INTO public.users (
    id,
    email,
    name,
    phone,
    role,
    email_confirm,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    p_email,
    p_name,
    p_phone,
    'cliente',
    FALSE,
    NOW(),
    NOW()
  );

  -- ====================================
  -- PASO 3: Crear perfil de cliente
  -- ====================================
  INSERT INTO public.client_profiles (
    user_id,
    address,
    lat,
    lon,
    address_structured,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    p_address,
    p_lat,
    p_lon,
    p_address_structured,
    NOW(),
    NOW()
  );

  -- ====================================
  -- PASO 4: Crear preferencias de usuario
  -- ====================================
  INSERT INTO public.user_preferences (
    user_id,
    has_seen_onboarding,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    FALSE,
    NOW(),
    NOW()
  );

  -- ====================================
  -- PASO 5: Log de éxito
  -- ====================================
  INSERT INTO debug_logs (scope, message, meta)
  VALUES (
    'REGISTER_CLIENT_SUCCESS',
    'Cliente registrado exitosamente',
    jsonb_build_object(
      'user_id', v_user_id,
      'email', p_email,
      'timestamp', NOW()
    )
  );

  -- ====================================
  -- PASO 6: Construir respuesta
  -- ====================================
  v_result := jsonb_build_object(
    'success', TRUE,
    'user_id', v_user_id,
    'email', p_email,
    'name', p_name,
    'role', 'cliente',
    'message', 'Cliente registrado exitosamente. Por favor verifica tu email.'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    
    -- Log de error
    INSERT INTO debug_logs (scope, message, meta)
    VALUES (
      'REGISTER_CLIENT_ERROR',
      'Error en registro de cliente',
      jsonb_build_object(
        'error', v_error,
        'email', p_email,
        'timestamp', NOW()
      )
    );

    -- Retornar error
    RETURN jsonb_build_object(
      'success', FALSE,
      'error', v_error
    );
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.register_client TO anon, authenticated;

-- Comentario
COMMENT ON FUNCTION public.register_client IS 
'Registra un nuevo cliente en el sistema de manera atómica.
Crea usuario en auth.users, public.users, client_profiles y user_preferences.
Retorna JSONB con success: true/false y datos del usuario o error.';

-- Test rápido (comentar después de verificar)
-- SELECT public.register_client(
--   'test_client@example.com',
--   'password123',
--   'Cliente Test',
--   '+1234567890'
-- );
