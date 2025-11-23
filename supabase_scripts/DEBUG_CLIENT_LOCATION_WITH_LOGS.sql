-- ============================================
-- DEBUG SCRIPT: Agregar logs al RPC ensure_user_profile_public
-- para rastrear el flujo de ubicación en client_profiles
-- ============================================
-- INSTRUCCIONES:
-- 1. Copia y pega este script en el SQL Editor de Supabase
-- 2. Ejecuta el script
-- 3. Realiza un nuevo registro de cliente desde Flutter
-- 4. Revisa los logs en Supabase Dashboard > Database > Logs
-- ============================================

-- Primero, activar RAISE NOTICE para que aparezcan en los logs
SET client_min_messages = 'notice';

-- Reemplazar el RPC ensure_user_profile_public con logs de debug
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_role text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_user_id uuid;
  v_existing_role text;
  v_result jsonb;
BEGIN
  RAISE NOTICE '📍 [RPC DEBUG] ensure_user_profile_public called with:';
  RAISE NOTICE '   - p_user_id: %', p_user_id;
  RAISE NOTICE '   - p_email: %', p_email;
  RAISE NOTICE '   - p_role: %', p_role;
  RAISE NOTICE '   - p_lat: %', p_lat;
  RAISE NOTICE '   - p_lon: %', p_lon;
  RAISE NOTICE '   - p_address: %', p_address;
  RAISE NOTICE '   - p_address_structured: %', p_address_structured;

  -- Check if user exists in public.users
  SELECT id, role INTO v_existing_user_id, v_existing_role
  FROM public.users
  WHERE id = p_user_id;

  IF v_existing_user_id IS NOT NULL THEN
    RAISE NOTICE '✅ [RPC DEBUG] User already exists in public.users with role: %', v_existing_role;
    
    -- User exists, just update if needed
    UPDATE public.users
    SET
      name = COALESCE(NULLIF(p_name, ''), name),
      phone = COALESCE(NULLIF(p_phone, ''), phone),
      address = COALESCE(NULLIF(p_address, ''), address),
      updated_at = now()
    WHERE id = p_user_id;

    RAISE NOTICE '✅ [RPC DEBUG] User profile updated in public.users';

    -- Si el rol es 'client', intentar actualizar client_profiles con ubicación
    IF v_existing_role = 'client' THEN
      RAISE NOTICE '📍 [RPC DEBUG] Attempting to update client_profiles location...';
      RAISE NOTICE '   - User ID: %', p_user_id;
      RAISE NOTICE '   - lat: %', p_lat;
      RAISE NOTICE '   - lon: %', p_lon;
      RAISE NOTICE '   - address: %', p_address;
      RAISE NOTICE '   - address_structured: %', p_address_structured;
      
      UPDATE public.client_profiles
      SET
        lat = COALESCE(p_lat, lat),
        lon = COALESCE(p_lon, lon),
        address = COALESCE(NULLIF(p_address, ''), address),
        address_structured = COALESCE(p_address_structured, address_structured),
        updated_at = now()
      WHERE user_id = p_user_id;

      IF FOUND THEN
        RAISE NOTICE '✅ [RPC DEBUG] client_profiles updated with location data';
      ELSE
        RAISE NOTICE '❌ [RPC DEBUG] client_profiles NOT FOUND for user_id: %', p_user_id;
      END IF;
    END IF;

    v_result := jsonb_build_object(
      'success', true,
      'user_id', p_user_id,
      'action', 'updated'
    );
    RETURN v_result;
  ELSE
    RAISE NOTICE '🆕 [RPC DEBUG] User does NOT exist. Creating new user...';
    
    -- User doesn't exist, create it
    INSERT INTO public.users (id, email, role, name, phone, address, created_at, updated_at)
    VALUES (p_user_id, p_email, p_role, p_name, p_phone, p_address, now(), now());

    RAISE NOTICE '✅ [RPC DEBUG] User created in public.users';

    -- Si el rol es 'client', el trigger handle_new_user_signup_v2 debe crear client_profiles
    -- Pero vamos a verificar que se creó correctamente
    IF p_role = 'client' THEN
      RAISE NOTICE '⏳ [RPC DEBUG] Waiting for trigger to create client_profiles...';
      
      -- Esperar un momento para que el trigger se ejecute
      PERFORM pg_sleep(0.1);
      
      -- Verificar si se creó el registro en client_profiles
      IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = p_user_id) THEN
        RAISE NOTICE '✅ [RPC DEBUG] client_profiles created by trigger';
        
        -- Actualizar con datos de ubicación
        RAISE NOTICE '📍 [RPC DEBUG] Updating client_profiles with location data...';
        RAISE NOTICE '   - lat: %', p_lat;
        RAISE NOTICE '   - lon: %', p_lon;
        RAISE NOTICE '   - address: %', p_address;
        RAISE NOTICE '   - address_structured: %', p_address_structured;
        
        UPDATE public.client_profiles
        SET
          lat = p_lat,
          lon = p_lon,
          address = p_address,
          address_structured = p_address_structured,
          updated_at = now()
        WHERE user_id = p_user_id;

        IF FOUND THEN
          RAISE NOTICE '✅ [RPC DEBUG] client_profiles updated with location';
        ELSE
          RAISE NOTICE '❌ [RPC DEBUG] Failed to update client_profiles';
        END IF;
      ELSE
        RAISE NOTICE '❌ [RPC DEBUG] client_profiles was NOT created by trigger!';
        RAISE NOTICE '   - Attempting manual insertion...';
        
        -- Intento manual de inserción
        INSERT INTO public.client_profiles (
          user_id,
          address,
          lat,
          lon,
          address_structured,
          created_at,
          updated_at
        ) VALUES (
          p_user_id,
          p_address,
          p_lat,
          p_lon,
          p_address_structured,
          now(),
          now()
        );
        
        RAISE NOTICE '✅ [RPC DEBUG] client_profiles manually created with location';
      END IF;
    END IF;

    v_result := jsonb_build_object(
      'success', true,
      'user_id', p_user_id,
      'action', 'created'
    );
    RETURN v_result;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE '❌ [RPC DEBUG] ERROR: %', SQLERRM;
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM
    );
END;
$$;

-- Mensaje final
DO $$
BEGIN
  RAISE NOTICE '✅ Script ejecutado exitosamente';
  RAISE NOTICE '📋 Ahora realiza un registro de cliente desde Flutter y revisa los logs en:';
  RAISE NOTICE '   Supabase Dashboard > Database > Logs (filtro: NOTICE)';
END $$;
