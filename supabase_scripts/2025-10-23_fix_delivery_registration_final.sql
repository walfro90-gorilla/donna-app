-- =============================================================
-- FIX DELIVERY AGENT REGISTRATION - SOLUCIÓN FINAL Y QUIRÚRGICA
-- =============================================================
-- Problema diagnosticado:
-- 1. El auth.user se crea primero por Supabase Auth
-- 2. El trigger handle_new_user() se dispara y crea client_profiles
-- 3. El RPC register_delivery_agent_atomic se llama después
-- 4. El RPC limpia client_profiles pero NO garantiza crear TODOS los registros
--
-- Solución quirúrgica:
-- 1. Desactivar completamente el trigger para evitar race conditions
-- 2. El RPC se encarga de crear TODOS los registros de forma atómica
-- 3. Para clientes normales, llamar manualmente ensure_client_profile_and_account
-- =============================================================

-- ============================================================
-- PASO 1: DESACTIVAR EL TRIGGER COMPLETAMENTE
-- ============================================================
-- El trigger causa race conditions. Lo desactivamos y dejamos que
-- los RPCs especializados manejen todo.

DROP TRIGGER IF EXISTS trg_handle_new_user_on_auth_users ON auth.users;

-- Opcional: mantener la función por si queremos reactivarla después
-- pero el trigger está desactivado

-- ============================================================
-- PASO 2: RPC ATÓMICO Y COMPLETO PARA DELIVERY AGENT
-- ============================================================

DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic CASCADE;

CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_vehicle_type text DEFAULT 'motocicleta',
  p_vehicle_plate text DEFAULT '',
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  p_emergency_contact_name text DEFAULT NULL,
  p_emergency_contact_phone text DEFAULT NULL,
  p_place_id text DEFAULT NULL,
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
  v_delivery_agent_id uuid;
  v_account_id uuid;
  v_now timestamptz := now();
BEGIN
  -- Validar que el auth.user existe
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'data', NULL,
      'error', 'auth.user does not exist'
    );
  END IF;

  -- 1) LIMPIAR cualquier perfil/cuenta de cliente creado por trigger o error anterior
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;
  DELETE FROM public.accounts WHERE user_id = p_user_id AND account_type = 'client';

  -- 2) CREAR/ACTUALIZAR usuario en public.users con role='delivery_agent'
  INSERT INTO public.users (
    id, 
    email, 
    name, 
    phone, 
    address, 
    role, 
    lat, 
    lon, 
    address_structured, 
    email_confirm,
    created_at, 
    updated_at
  ) VALUES (
    p_user_id,
    p_email,
    p_name,
    COALESCE(p_phone, ''),
    COALESCE(p_address, ''),
    'delivery_agent',  -- ⭐ ROLE FORZADO
    p_lat,
    p_lon,
    p_address_structured,
    false,
    v_now,
    v_now
  )
  ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        name = EXCLUDED.name,
        phone = EXCLUDED.phone,
        address = EXCLUDED.address,
        role = 'delivery_agent',  -- ⭐ SIEMPRE forzar delivery_agent
        lat = EXCLUDED.lat,
        lon = EXCLUDED.lon,
        address_structured = EXCLUDED.address_structured,
        updated_at = v_now;

  -- 3) CREAR delivery_agent_profiles (con RETURNING para capturar el ID)
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
    status,
    account_state,
    onboarding_completed,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_profile_image_url,
    p_id_document_front_url,
    p_id_document_back_url,
    COALESCE(p_vehicle_type, 'motocicleta'),
    COALESCE(p_vehicle_plate, ''),
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_registration_url,
    p_vehicle_insurance_url,
    p_vehicle_photo_url,
    p_emergency_contact_name,
    p_emergency_contact_phone,
    'pending',        -- Estado inicial: pendiente de aprobación
    'pending',        -- Account state: pendiente
    false,            -- Onboarding no completado aún
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE
    SET profile_image_url = EXCLUDED.profile_image_url,
        id_document_front_url = EXCLUDED.id_document_front_url,
        id_document_back_url = EXCLUDED.id_document_back_url,
        vehicle_type = EXCLUDED.vehicle_type,
        vehicle_plate = EXCLUDED.vehicle_plate,
        vehicle_model = EXCLUDED.vehicle_model,
        vehicle_color = EXCLUDED.vehicle_color,
        vehicle_registration_url = EXCLUDED.vehicle_registration_url,
        vehicle_insurance_url = EXCLUDED.vehicle_insurance_url,
        vehicle_photo_url = EXCLUDED.vehicle_photo_url,
        emergency_contact_name = EXCLUDED.emergency_contact_name,
        emergency_contact_phone = EXCLUDED.emergency_contact_phone,
        updated_at = v_now
  RETURNING user_id INTO v_delivery_agent_id;

  -- 4) CREAR cuenta financiera tipo 'delivery_agent'
  INSERT INTO public.accounts (
    user_id, 
    account_type, 
    balance, 
    created_at, 
    updated_at
  ) VALUES (
    p_user_id, 
    'delivery_agent', 
    0.0, 
    v_now, 
    v_now
  )
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = v_now
  RETURNING id INTO v_account_id;

  -- 5) CREAR user_preferences (sin restaurant_id para delivery agents)
  INSERT INTO public.user_preferences (
    user_id, 
    has_seen_onboarding,
    created_at, 
    updated_at
  ) VALUES (
    p_user_id, 
    false,
    v_now, 
    v_now
  )
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = v_now;

  -- 6) RETORNAR éxito con todos los IDs
  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'delivery_agent_id', v_delivery_agent_id,
      'account_id', v_account_id,
      'role', 'delivery_agent'
    ),
    'error', NULL
  );

EXCEPTION WHEN OTHERS THEN
  -- Retornar error detallado
  RETURN jsonb_build_object(
    'success', false,
    'data', NULL,
    'error', SQLERRM
  );
END;
$$;

-- ============================================================
-- PASO 3: GRANT PERMISOS
-- ============================================================

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(
  uuid, text, text, text, text, double precision, double precision, jsonb,
  text, text, text, text, text, text, text, text, text, text, text, text, text
) TO anon, authenticated, service_role;

-- ============================================================
-- PASO 4: COMENTARIOS Y DOCUMENTACIÓN
-- ============================================================

COMMENT ON FUNCTION public.register_delivery_agent_atomic IS 
'Atomic registration for delivery agents. Creates:
1. users table record with role=delivery_agent
2. delivery_agent_profiles record
3. accounts record with account_type=delivery_agent
4. user_preferences record
All in a single transaction. Cleans up any client profiles created by mistake.';

-- ============================================================
-- VERIFICACIÓN: Ejecutar para confirmar que la función existe
-- ============================================================

SELECT 
  p.proname AS function_name,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  d.description
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN pg_description d ON d.objoid = p.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'register_delivery_agent_atomic';

-- ============================================================
-- VERIFICACIÓN: Confirmar que el trigger está desactivado
-- ============================================================

SELECT 
  tgname AS trigger_name,
  tgenabled AS enabled_status
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname = 'trg_handle_new_user_on_auth_users';
-- Debería retornar 0 filas (trigger eliminado)
