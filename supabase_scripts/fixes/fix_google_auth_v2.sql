-- ============================================================================
-- SCRIPT: FIX_GOOGLE_AUTH_METADATA_AND_AVATAR.sql
-- ============================================================================
-- OBJETIVO: 
--   1. Reparar la captura de 'name' y 'email' en la tabla 'users' para Google Auth.
--   2. Capturar la URL del avatar de Google y guardarla en 'client_profiles'.
--
-- PROBLEMA ORIGINAL:
--   La función ignoraba 'full_name' (común en Google) y no leía 'avatar_url'/'picture'.
-- ============================================================================

-- ============================================================================
-- PASO 1: Actualizar función handle_new_user_signup_v2
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user_signup_v2()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_email TEXT;
  v_role TEXT;
  v_name TEXT;
  v_phone TEXT;
  v_address TEXT;
  v_lat DOUBLE PRECISION;
  v_lon DOUBLE PRECISION;
  v_address_structured JSONB;
  v_metadata JSONB;
  -- Nueva variable para el avatar
  v_avatar_url TEXT;
BEGIN
  -- ========================================================================
  -- PASO 0: Extraer metadata del usuario en auth.users
  -- ========================================================================
  
  v_email := NEW.email;
  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  
  -- Normalización de ROL
  v_role := COALESCE(v_metadata->>'role', 'cliente');
  v_role := CASE lower(v_role)
    WHEN 'client' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'restaurant' THEN 'restaurant'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'delivery_agent' THEN 'delivery_agent'
    WHEN 'delivery' THEN 'delivery_agent'
    WHEN 'repartidor' THEN 'delivery_agent'
    WHEN 'admin' THEN 'admin'
    ELSE 'client'
  END;

  -- 🔥 FIX 1: Extracción robusta de NOMBRE (Google usa 'full_name' o 'name')
  v_name := COALESCE(
    v_metadata->>'full_name', 
    v_metadata->>'name', 
    v_metadata->>'description', -- Fallback raro
    split_part(v_email, '@', 1) -- Último recurso: parte del email
  );
  
  v_phone := v_metadata->>'phone';
  
  -- 🔥 FIX 2: Extracción de AVATAR (Google usa 'avatar_url' o 'picture')
  v_avatar_url := COALESCE(
    v_metadata->>'avatar_url',
    v_metadata->>'picture',
    v_metadata->>'image'
  );

  -- Extracción de ubicación (existente)
  v_address := v_metadata->>'address';
  
  -- Conversión segura de lat/lon
  BEGIN
    v_lat := CASE 
      WHEN v_metadata->>'lat' IS NOT NULL AND v_metadata->>'lat' != '' 
      THEN (v_metadata->>'lat')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lat := NULL;
  END;
  
  BEGIN
    v_lon := CASE 
      WHEN v_metadata->>'lon' IS NOT NULL AND v_metadata->>'lon' != '' 
      THEN (v_metadata->>'lon')::DOUBLE PRECISION
      ELSE NULL
    END;
  EXCEPTION WHEN OTHERS THEN
    v_lon := NULL;
  END;
  
  v_address_structured := CASE
    WHEN v_metadata->'address_structured' IS NOT NULL 
    THEN v_metadata->'address_structured'
    ELSE NULL
  END;

  -- Log START
  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
  VALUES ('handle_new_user_signup_v2', 'START_V2_FIX', v_role, NEW.id, v_email, 
          jsonb_build_object(
            'input_name', v_metadata->>'name',
            'input_full_name', v_metadata->>'full_name',
            'resolved_name', v_name,
            'resolved_avatar', v_avatar_url
          ));

  -- ========================================================================
  -- PASO 1: Upsert en public.users (Corregimos name y email)
  -- ========================================================================
  
  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)
  VALUES (
    NEW.id, 
    v_email, 
    v_role, 
    v_name, 
    v_phone, 
    now(), 
    now(), 
    NEW.email_confirmed_at IS NOT NULL
  )
  ON CONFLICT (id) DO UPDATE
  SET 
    email = EXCLUDED.email,
    role = EXCLUDED.role,
    name = EXCLUDED.name, -- Ahora sí se actualiza con el nombre correcto
    phone = EXCLUDED.phone,
    email_confirm = EXCLUDED.email_confirm,
    updated_at = now();

  -- ========================================================================
  -- PASO 2: Crear profile según el rol
  -- ========================================================================
  
  CASE v_role
    
    -- ======================================================================
    -- ROL: CLIENT (Con Avatar y Ubicación)
    -- ======================================================================
    WHEN 'client' THEN
      
      INSERT INTO public.client_profiles (
        user_id, 
        status, 
        address,
        lat,
        lon,
        address_structured,
        profile_image_url, -- 🔥 Nuevo campo
        created_at, 
        updated_at
      )
      VALUES (
        NEW.id, 
        'active',
        v_address,
        v_lat,
        v_lon,
        v_address_structured,
        v_avatar_url, -- 🔥 Guardamos avatar aquí
        now(), 
        now()
      )
      ON CONFLICT (user_id) DO UPDATE 
      SET 
        address = COALESCE(EXCLUDED.address, client_profiles.address),
        lat = COALESCE(EXCLUDED.lat, client_profiles.lat),
        lon = COALESCE(EXCLUDED.lon, client_profiles.lon),
        address_structured = COALESCE(EXCLUDED.address_structured, client_profiles.address_structured),
        -- Solo actualizamos avatar si llega uno nuevo y no tenemos uno ya (o forzamos update)
        profile_image_url = COALESCE(EXCLUDED.profile_image_url, client_profiles.profile_image_url),
        updated_at = now();

      -- Crear account y preferencias (igual que antes)
      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)
      VALUES (NEW.id, 'client', 0.0, now(), now()) ON CONFLICT DO NOTHING;

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now()) ON CONFLICT DO NOTHING;

    -- ======================================================================
    -- ROL: RESTAURANT
    -- ======================================================================
    WHEN 'restaurant' THEN
      INSERT INTO public.restaurants (user_id, name, status, created_at, updated_at)
      VALUES (NEW.id, v_name, 'pending', now(), now())
      ON CONFLICT (user_id) DO NOTHING;

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now()) ON CONFLICT DO NOTHING;

    -- ======================================================================
    -- ROL: DELIVERY_AGENT
    -- ======================================================================
    WHEN 'delivery_agent' THEN
      INSERT INTO public.delivery_agent_profiles (user_id, status, account_state, created_at, updated_at)
      VALUES (NEW.id, 'pending', 'pending', now(), now())
      ON CONFLICT (user_id) DO NOTHING;

      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now()) ON CONFLICT DO NOTHING;

    -- ======================================================================
    -- ROL: ADMIN
    -- ======================================================================
    WHEN 'admin' THEN
      INSERT INTO public.user_preferences (user_id, created_at, updated_at)
      VALUES (NEW.id, now(), now()) ON CONFLICT DO NOTHING;

  END CASE;

  RETURN NEW;

EXCEPTION
  WHEN OTHERS THEN
    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)
    VALUES ('handle_new_user_signup_v2', 'ERROR_V2_FIX', v_role, NEW.id, v_email, 
            jsonb_build_object('error', SQLERRM));
    RAISE;
END;
$function$;

-- ============================================================================
-- PASO 2: Verificar Trigger
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'on_auth_user_created' 
    AND tgrelid = 'auth.users'::regclass
  ) THEN
    CREATE TRIGGER on_auth_user_created
      AFTER INSERT ON auth.users
      FOR EACH ROW
      EXECUTE FUNCTION public.handle_new_user_signup_v2();
  END IF;
  
  RAISE NOTICE '✅ FIX COMPLETADO: handle_new_user_signup_v2 actualizado con soporte para full_name y avatar_url';
END $$;
