-- ============================================================================
-- FIX DELIVERY AGENT REGISTRATION - COMPLETE ATOMIC PROCESS
-- ============================================================================
-- Este script actualiza el RPC register_delivery_agent_atomic() para crear
-- TODOS los registros necesarios de forma atómica:
-- 1. delivery_agent_profiles (con TODOS los campos)
-- 2. accounts (cuenta financiera)
-- 3. user_preferences
--
-- ALINEADO CON: DATABASE_SCHEMA.sql
-- SINTAXIS: PostgreSQL 15+
-- ============================================================================

-- ============================================================================
-- PASO 1: DROP y RECREAR el RPC con la firma completa
-- ============================================================================

DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic(
  uuid, text, text, text, text, text, text, text
) CASCADE;

DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic CASCADE;

-- ============================================================================
-- PASO 2: CREAR la función actualizada con TODOS los parámetros
-- ============================================================================

CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(
  -- User basic info
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text,
  -- Address info
  p_address text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_place_id text DEFAULT NULL,
  -- Vehicle info
  p_vehicle_type text DEFAULT NULL,
  p_vehicle_plate text DEFAULT NULL,
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  -- Emergency contact
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  -- Document URLs
  p_profile_image_url text DEFAULT NULL,
  p_id_document_front_url text DEFAULT NULL,
  p_id_document_back_url text DEFAULT NULL,
  p_vehicle_photo_url text DEFAULT NULL,
  p_vehicle_registration_url text DEFAULT NULL,
  p_vehicle_insurance_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_account_id uuid;
  v_existing_account_id uuid;
BEGIN
  -- ============================================================================
  -- PASO 1: Verificar que el usuario existe en public.users
  -- ============================================================================
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Usuario no existe en public.users: %', p_user_id;
  END IF;

  -- ============================================================================
  -- PASO 2: Actualizar role en public.users si es necesario
  -- ============================================================================
  UPDATE public.users
  SET 
    role = 'delivery_agent',
    updated_at = v_now
  WHERE id = p_user_id 
    AND COALESCE(role, '') != 'delivery_agent';

  -- ============================================================================
  -- PASO 3: Crear/Actualizar delivery_agent_profiles con TODOS los campos
  -- ============================================================================
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    profile_image_url,
    id_document_front_url,
    id_document_back_url,
    vehicle_type,
    vehicle_plate,
    vehicle_model,
    vehicle_color,
    vehicle_registration_url,
    vehicle_insurance_url,
    vehicle_photo_url,
    emergency_contact_name,
    emergency_contact_phone,
    onboarding_completed,
    onboarding_completed_at,
    status,
    account_state,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_profile_image_url,
    p_id_document_front_url,
    p_id_document_back_url,
    p_vehicle_type::text,
    p_vehicle_plate,
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_registration_url,
    p_vehicle_insurance_url,
    p_vehicle_photo_url,
    p_emergency_contact_name,
    p_emergency_contact_phone,
    false, -- onboarding_completed
    NULL,  -- onboarding_completed_at
    'pending', -- status (delivery_agent_status enum)
    'pending', -- account_state (delivery_agent_account_state enum)
    v_now,
    v_now
  )
  ON CONFLICT (user_id) 
  DO UPDATE SET
    profile_image_url = COALESCE(EXCLUDED.profile_image_url, delivery_agent_profiles.profile_image_url),
    id_document_front_url = COALESCE(EXCLUDED.id_document_front_url, delivery_agent_profiles.id_document_front_url),
    id_document_back_url = COALESCE(EXCLUDED.id_document_back_url, delivery_agent_profiles.id_document_back_url),
    vehicle_type = COALESCE(EXCLUDED.vehicle_type, delivery_agent_profiles.vehicle_type),
    vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, delivery_agent_profiles.vehicle_plate),
    vehicle_model = COALESCE(EXCLUDED.vehicle_model, delivery_agent_profiles.vehicle_model),
    vehicle_color = COALESCE(EXCLUDED.vehicle_color, delivery_agent_profiles.vehicle_color),
    vehicle_registration_url = COALESCE(EXCLUDED.vehicle_registration_url, delivery_agent_profiles.vehicle_registration_url),
    vehicle_insurance_url = COALESCE(EXCLUDED.vehicle_insurance_url, delivery_agent_profiles.vehicle_insurance_url),
    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, delivery_agent_profiles.vehicle_photo_url),
    emergency_contact_name = COALESCE(EXCLUDED.emergency_contact_name, delivery_agent_profiles.emergency_contact_name),
    emergency_contact_phone = COALESCE(EXCLUDED.emergency_contact_phone, delivery_agent_profiles.emergency_contact_phone),
    updated_at = v_now;

  -- ============================================================================
  -- PASO 4: Crear cuenta financiera (accounts) si no existe
  -- ============================================================================
  
  -- Verificar si ya existe una cuenta
  SELECT id INTO v_existing_account_id
  FROM public.accounts
  WHERE user_id = p_user_id 
    AND account_type = 'delivery_agent';

  IF v_existing_account_id IS NOT NULL THEN
    -- Ya existe, usar la existente
    v_account_id := v_existing_account_id;
  ELSE
    -- Crear nueva cuenta
    INSERT INTO public.accounts (
      user_id,
      account_type,
      balance,
      created_at,
      updated_at
    ) VALUES (
      p_user_id,
      'delivery_agent',
      0.00,
      v_now,
      v_now
    )
    RETURNING id INTO v_account_id;
  END IF;

  -- ============================================================================
  -- PASO 5: Crear user_preferences si no existe
  -- ============================================================================
  INSERT INTO public.user_preferences (
    user_id,
    has_seen_onboarding,
    has_seen_delivery_welcome,
    delivery_welcome_seen_at,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    false,
    false,
    NULL,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- ============================================================================
  -- PASO 6: Retornar resultado exitoso
  -- ============================================================================
  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'account_id', v_account_id,
    'created_at', v_now
  );

EXCEPTION WHEN OTHERS THEN
  -- Log del error
  RAISE WARNING 'register_delivery_agent_atomic ERROR: % | SQLSTATE: %', SQLERRM, SQLSTATE;
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'sqlstate', SQLSTATE
  );
END;
$$;

-- ============================================================================
-- PASO 3: GRANT permisos para anon y authenticated
-- ============================================================================

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(
  uuid, text, text, text,
  text, double precision, double precision, jsonb, text,
  text, text, text, text,
  text, text,
  text, text, text, text, text, text
) TO anon, authenticated, service_role;

-- ============================================================================
-- PASO 4: COMENTARIO de documentación
-- ============================================================================

COMMENT ON FUNCTION public.register_delivery_agent_atomic IS 
'Registro atómico completo de delivery agent.
Crea/actualiza: delivery_agent_profiles, accounts, user_preferences.
Requiere que el usuario ya exista en public.users (creado por ensure_user_profile_public).
Alineado con DATABASE_SCHEMA.sql - Sintaxis PostgreSQL 15+';

-- ============================================================================
-- VERIFICACIÓN: Mostrar la firma de la función
-- ============================================================================

SELECT 
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname = 'register_delivery_agent_atomic';

-- ============================================================================
-- ✅ FIN DEL SCRIPT
-- ============================================================================
-- Después de ejecutar este script:
-- 1. Hot Restart de la app
-- 2. Probar el registro de delivery agent
-- 3. Verificar en Supabase que se crearon todos los registros
-- ============================================================================
