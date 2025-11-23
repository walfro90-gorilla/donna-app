-- =====================================================
-- FASE 5B: RPC DE REGISTRO DE RESTAURANTES
-- =====================================================
-- Proceso atómico y profesional para registro de restaurantes
-- Tiempo estimado: 5 minutos
-- =====================================================

CREATE OR REPLACE FUNCTION public.register_restaurant(
  p_email TEXT,
  p_password TEXT,
  p_owner_name TEXT,
  p_phone TEXT,
  p_restaurant_name TEXT,
  p_restaurant_description TEXT DEFAULT NULL,
  p_address TEXT DEFAULT NULL,
  p_lat DOUBLE PRECISION DEFAULT NULL,
  p_lon DOUBLE PRECISION DEFAULT NULL,
  p_address_structured JSONB DEFAULT NULL,
  p_cuisine_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_restaurant_id UUID;
  v_account_id UUID;
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

  -- Validar password
  IF p_password IS NULL OR LENGTH(p_password) < 6 THEN
    RAISE EXCEPTION 'La contraseña debe tener al menos 6 caracteres';
  END IF;

  -- Validar nombre de restaurante
  IF p_restaurant_name IS NULL OR LENGTH(TRIM(p_restaurant_name)) < 3 THEN
    RAISE EXCEPTION 'El nombre del restaurante debe tener al menos 3 caracteres';
  END IF;

  -- Validar que no exista el email
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = p_email) THEN
    RAISE EXCEPTION 'El email ya está registrado';
  END IF;

  -- Validar que no exista el teléfono
  IF EXISTS (SELECT 1 FROM public.users WHERE phone = p_phone) THEN
    RAISE EXCEPTION 'El teléfono ya está registrado';
  END IF;

  -- Validar que no exista el nombre del restaurante
  IF EXISTS (SELECT 1 FROM public.restaurants WHERE LOWER(name) = LOWER(p_restaurant_name)) THEN
    RAISE EXCEPTION 'Ya existe un restaurante con ese nombre';
  END IF;

  -- ====================================
  -- PASO 1: Crear usuario en auth.users
  -- ====================================
  BEGIN
    v_auth_user := auth.sign_up_v2(
      jsonb_build_object(
        'email', p_email,
        'password', p_password,
        'email_confirm', FALSE,
        'user_metadata', jsonb_build_object(
          'name', p_owner_name,
          'role', 'restaurante',
          'restaurant_name', p_restaurant_name
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
      VALUES ('REGISTER_RESTAURANT_ERROR', 'Error en auth.sign_up_v2', 
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
    p_owner_name,
    p_phone,
    'restaurante',
    FALSE,
    NOW(),
    NOW()
  );

  -- ====================================
  -- PASO 3: Crear registro en restaurants
  -- ====================================
  INSERT INTO public.restaurants (
    id,
    user_id,
    name,
    description,
    status,
    address,
    phone,
    online,
    address_structured,
    location_lat,
    location_lon,
    cuisine_type,
    commission_bps,
    onboarding_completed,
    onboarding_step,
    profile_completion_percentage,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    p_restaurant_name,
    p_restaurant_description,
    'pending', -- Debe ser aprobado por admin
    p_address,
    p_phone,
    FALSE, -- Inicia offline
    p_address_structured,
    p_lat,
    p_lon,
    p_cuisine_type,
    1500, -- 15% comisión default
    FALSE,
    0,
    20, -- 20% de completitud inicial (tiene lo básico)
    NOW(),
    NOW()
  )
  RETURNING id INTO v_restaurant_id;

  -- ====================================
  -- PASO 4: Crear cuenta financiera
  -- ====================================
  INSERT INTO public.accounts (
    id,
    user_id,
    account_type,
    balance,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    'restaurant',
    0.00,
    NOW(),
    NOW()
  )
  RETURNING id INTO v_account_id;

  -- ====================================
  -- PASO 5: Crear preferencias de usuario
  -- ====================================
  INSERT INTO public.user_preferences (
    user_id,
    restaurant_id,
    has_seen_onboarding,
    has_seen_restaurant_welcome,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,
    v_restaurant_id,
    FALSE,
    FALSE,
    NOW(),
    NOW()
  );

  -- ====================================
  -- PASO 6: Crear notificación para admin
  -- ====================================
  INSERT INTO public.admin_notifications (
    target_role,
    category,
    entity_type,
    entity_id,
    title,
    message,
    metadata
  ) VALUES (
    'admin',
    'registration',
    'restaurant',
    v_restaurant_id,
    'Nuevo restaurante registrado',
    'El restaurante "' || p_restaurant_name || '" se ha registrado y está pendiente de aprobación.',
    jsonb_build_object(
      'restaurant_id', v_restaurant_id,
      'user_id', v_user_id,
      'restaurant_name', p_restaurant_name,
      'owner_email', p_email
    )
  );

  -- ====================================
  -- PASO 7: Log de éxito
  -- ====================================
  INSERT INTO debug_logs (scope, message, meta)
  VALUES (
    'REGISTER_RESTAURANT_SUCCESS',
    'Restaurante registrado exitosamente',
    jsonb_build_object(
      'user_id', v_user_id,
      'restaurant_id', v_restaurant_id,
      'account_id', v_account_id,
      'email', p_email,
      'restaurant_name', p_restaurant_name,
      'timestamp', NOW()
    )
  );

  -- ====================================
  -- PASO 8: Construir respuesta
  -- ====================================
  v_result := jsonb_build_object(
    'success', TRUE,
    'user_id', v_user_id,
    'restaurant_id', v_restaurant_id,
    'account_id', v_account_id,
    'email', p_email,
    'name', p_owner_name,
    'restaurant_name', p_restaurant_name,
    'role', 'restaurante',
    'status', 'pending',
    'message', 'Restaurante registrado exitosamente. Tu solicitud está pendiente de aprobación por el administrador.'
  );

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    
    -- Log de error
    INSERT INTO debug_logs (scope, message, meta)
    VALUES (
      'REGISTER_RESTAURANT_ERROR',
      'Error en registro de restaurante',
      jsonb_build_object(
        'error', v_error,
        'email', p_email,
        'restaurant_name', p_restaurant_name,
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
GRANT EXECUTE ON FUNCTION public.register_restaurant TO anon, authenticated;

-- Comentario
COMMENT ON FUNCTION public.register_restaurant IS 
'Registra un nuevo restaurante en el sistema de manera atómica.
Crea usuario, restaurante, cuenta financiera, preferencias y notificación admin.
El restaurante queda en estado "pending" hasta aprobación de admin.
Retorna JSONB con success: true/false y datos completos o error.';

-- Test rápido (comentar después de verificar)
-- SELECT public.register_restaurant(
--   'test_restaurant@example.com',
--   'password123',
--   'Juan Pérez',
--   '+1234567890',
--   'Restaurante Test',
--   'Comida deliciosa'
-- );
