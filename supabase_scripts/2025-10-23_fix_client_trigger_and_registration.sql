-- =============================================================
-- FIX CLIENT PROFILE TRIGGER + DELIVERY AGENT REGISTRATION
-- =============================================================
-- Solución híbrida:
-- 1) Actualiza el trigger de auth.users para que solo cree client_profiles
--    si el usuario NO tiene un role especializado (restaurant, delivery_agent, admin)
-- 2) Mantiene el RPC de delivery_agent atómico y limpio
-- 3) Garantiza que cada role crea los perfiles correctos
-- =============================================================

-- ============================================================
-- PARTE 1: Actualizar el trigger de auth.users
-- ============================================================

-- Actualizar la función que maneja nuevos usuarios en auth
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role text;
BEGIN
  -- Esperar un momento para que el RPC pueda insertar el role primero
  -- (esto permite que RPCs especializados corran antes del trigger)
  PERFORM pg_sleep(0.1);
  
  -- Verificar si ya existe un role definido en public.users
  SELECT role INTO v_user_role 
  FROM public.users 
  WHERE id = NEW.id;
  
  -- Solo crear perfil de cliente si:
  -- 1) El usuario NO existe aún en public.users, O
  -- 2) El usuario existe pero tiene role='client' o NULL
  IF v_user_role IS NULL OR v_user_role IN ('client', 'cliente', '') THEN
    -- Crear perfil de cliente por defecto
    PERFORM public.ensure_client_profile_and_account(NEW.id);
  END IF;
  
  RETURN NEW;
END;
$$;

-- Recrear el trigger (si ya existe, se reemplaza)
DROP TRIGGER IF EXISTS trg_handle_new_user_on_auth_users ON auth.users;
CREATE TRIGGER trg_handle_new_user_on_auth_users
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- PARTE 2: Actualizar ensure_client_profile_and_account
-- ============================================================

-- Actualizar la función para que sea más defensiva
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_user_exists boolean;
  v_current_role text;
  v_account_id uuid;
BEGIN
  -- Validar que el usuario existe en auth
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User % not found in auth.users', p_user_id;
  END IF;

  -- Verificar role actual
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id), role
    INTO v_user_exists, v_current_role
  FROM public.users WHERE id = p_user_id;

  -- SOLO crear perfil de cliente si no tiene un role especializado
  IF v_current_role IS NOT NULL AND v_current_role NOT IN ('', 'client', 'cliente') THEN
    -- Ya tiene un role especializado, no hacer nada
    RETURN jsonb_build_object('success', true, 'account_id', NULL, 'skipped', true, 'reason', 'specialized_role');
  END IF;

  -- Crear/actualizar usuario con role='client'
  IF NOT v_user_exists THEN
    INSERT INTO public.users (id, role, created_at, updated_at)
    VALUES (p_user_id, 'client', v_now, v_now)
    ON CONFLICT (id) DO NOTHING;
  ELSE
    -- Solo normalizar a 'client' si actualmente es vacío/cliente
    IF COALESCE(v_current_role, '') IN ('', 'client', 'cliente') THEN
      UPDATE public.users SET role = 'client', updated_at = v_now WHERE id = p_user_id;
    END IF;
  END IF;

  -- Asegurar profile de cliente
  INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', v_now, v_now)
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = EXCLUDED.updated_at;

  -- Asegurar cuenta financiera tipo 'client'
  SELECT id INTO v_account_id
  FROM public.accounts
  WHERE user_id = p_user_id AND account_type = 'client'
  LIMIT 1;
  IF v_account_id IS NULL THEN
    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
    VALUES (p_user_id, 'client', 0.0, v_now, v_now)
    RETURNING id INTO v_account_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);
END;
$$;

-- ============================================================
-- PARTE 3: RPC ATÓMICO PARA DELIVERY AGENT (LIMPIO Y COMPLETO)
-- ============================================================

-- Drop versiones anteriores
DROP FUNCTION IF EXISTS public.register_delivery_agent_atomic CASCADE;
DROP FUNCTION IF EXISTS public.register_delivery_agent_v2 CASCADE;

-- RPC principal para registro de delivery agents
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
BEGIN
  -- 1) Limpiar cualquier perfil/cuenta de cliente creado por el trigger
  --    (esto maneja el caso de race condition entre trigger y RPC)
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;
  DELETE FROM public.accounts WHERE user_id = p_user_id AND account_type = 'client';

  -- 2) Crear/actualizar usuario con role='delivery_agent' EXPLÍCITAMENTE
  INSERT INTO public.users (
    id, email, name, phone, address, role, 
    lat, lon, address_structured, email_confirm,
    created_at, updated_at
  ) VALUES (
    p_user_id,
    p_email,
    p_name,
    COALESCE(p_phone, ''),
    COALESCE(p_address, ''),
    'delivery_agent',  -- ROLE FORZADO
    p_lat,
    p_lon,
    p_address_structured,
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
    SET email = COALESCE(NULLIF(EXCLUDED.email, ''), public.users.email),
        name = COALESCE(NULLIF(EXCLUDED.name, ''), public.users.name),
        phone = COALESCE(NULLIF(EXCLUDED.phone, ''), public.users.phone),
        address = COALESCE(NULLIF(EXCLUDED.address, ''), public.users.address),
        role = 'delivery_agent',  -- SIEMPRE forzar delivery_agent
        lat = COALESCE(EXCLUDED.lat, public.users.lat),
        lon = COALESCE(EXCLUDED.lon, public.users.lon),
        address_structured = COALESCE(EXCLUDED.address_structured, public.users.address_structured),
        updated_at = now();

  -- 3) Crear delivery_agent_profiles (idempotente)
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
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_model,
    p_vehicle_color,
    p_vehicle_registration_url,
    p_vehicle_insurance_url,
    p_vehicle_photo_url,
    p_emergency_contact_name,
    p_emergency_contact_phone,
    'pending',
    'pending',
    false,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET profile_image_url = COALESCE(EXCLUDED.profile_image_url, public.delivery_agent_profiles.profile_image_url),
        id_document_front_url = COALESCE(EXCLUDED.id_document_front_url, public.delivery_agent_profiles.id_document_front_url),
        id_document_back_url = COALESCE(EXCLUDED.id_document_back_url, public.delivery_agent_profiles.id_document_back_url),
        vehicle_type = COALESCE(EXCLUDED.vehicle_type, public.delivery_agent_profiles.vehicle_type),
        vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, public.delivery_agent_profiles.vehicle_plate),
        vehicle_model = COALESCE(EXCLUDED.vehicle_model, public.delivery_agent_profiles.vehicle_model),
        vehicle_color = COALESCE(EXCLUDED.vehicle_color, public.delivery_agent_profiles.vehicle_color),
        vehicle_registration_url = COALESCE(EXCLUDED.vehicle_registration_url, public.delivery_agent_profiles.vehicle_registration_url),
        vehicle_insurance_url = COALESCE(EXCLUDED.vehicle_insurance_url, public.delivery_agent_profiles.vehicle_insurance_url),
        vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, public.delivery_agent_profiles.vehicle_photo_url),
        emergency_contact_name = COALESCE(EXCLUDED.emergency_contact_name, public.delivery_agent_profiles.emergency_contact_name),
        emergency_contact_phone = COALESCE(EXCLUDED.emergency_contact_phone, public.delivery_agent_profiles.emergency_contact_phone),
        updated_at = now()
  RETURNING user_id INTO v_delivery_agent_id;

  -- 4) Crear cuenta financiera tipo 'delivery_agent' (idempotente)
  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
  VALUES (p_user_id, 'delivery_agent', 0.0, now(), now())
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = EXCLUDED.updated_at
  RETURNING id INTO v_account_id;

  -- 5) Crear user_preferences (idempotente, sin restaurant_id)
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, now(), now())
  ON CONFLICT (user_id) DO UPDATE
    SET updated_at = now();

  -- 6) Retornar éxito con IDs
  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'delivery_agent_id', v_delivery_agent_id,
      'account_id', v_account_id
    ),
    'error', NULL
  );

EXCEPTION WHEN OTHERS THEN
  -- Retornar error con detalles
  RETURN jsonb_build_object(
    'success', false,
    'data', NULL,
    'error', SQLERRM
  );
END;
$$;

-- Grant permisos de ejecución
GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(
  uuid, text, text, text, text, double precision, double precision, jsonb,
  text, text, text, text, text, text, text, text, text, text, text, text, text
) TO anon, authenticated, service_role;

-- Comentario útil
COMMENT ON FUNCTION public.register_delivery_agent_atomic IS 
'Atomic registration for delivery agents. Creates user profile, delivery_agent_profiles, accounts, and user_preferences in a single transaction. Role is forced to delivery_agent.';

-- ============================================================
-- VERIFICACIÓN: Listar funciones clave
-- ============================================================
-- Descomentar para verificar:
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) args
-- FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname IN (
--   'handle_new_user',
--   'ensure_client_profile_and_account',
--   'register_delivery_agent_atomic'
-- ) ORDER BY 1;
