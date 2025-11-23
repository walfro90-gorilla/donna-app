-- ============================================
-- RESTAURAR FUNCIÓN ORIGINAL + LOGS DE DEBUG
-- Esta función SÍ guardaba nombre y teléfono correctamente
-- SOLO agregamos logs para debug de geolocalización
-- ============================================
-- INSTRUCCIONES:
-- 1. Copia y pega este script en el SQL Editor de Supabase
-- 2. Ejecuta el script
-- 3. Realiza un nuevo registro de cliente desde Flutter
-- 4. Revisa los logs en Supabase Dashboard > Database > Logs
-- ============================================

-- Primero, eliminar la función existente
DROP FUNCTION IF EXISTS public.ensure_user_profile_public(uuid,text,text,text,text,text,double precision,double precision,jsonb);

-- Crear la función ORIGINAL con LOGS AGREGADOS
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
  -- ===============================================
  -- LOGS DE DEBUG AGREGADOS
  -- ===============================================
  RAISE NOTICE '========================================';
  RAISE NOTICE '📍 [DEBUG] ensure_user_profile_public() llamado';
  RAISE NOTICE '   - p_user_id: %', p_user_id;
  RAISE NOTICE '   - p_email: %', p_email;
  RAISE NOTICE '   - p_name: %', p_name;
  RAISE NOTICE '   - p_role: %', p_role;
  RAISE NOTICE '   - p_phone: %', p_phone;
  RAISE NOTICE '   - p_address: %', p_address;
  RAISE NOTICE '   - p_lat: %', p_lat;
  RAISE NOTICE '   - p_lon: %', p_lon;
  RAISE NOTICE '   - p_address_structured: %', p_address_structured;
  RAISE NOTICE '========================================';

  -- Check if user exists in public.users
  SELECT id, role INTO v_existing_user_id, v_existing_role
  FROM public.users
  WHERE id = p_user_id;

  IF v_existing_user_id IS NOT NULL THEN
    RAISE NOTICE '✅ [DEBUG] Usuario YA existe en public.users (role: %)', v_existing_role;
    
    -- ===============================================
    -- ACTUALIZAR USUARIO EXISTENTE
    -- ===============================================
    UPDATE public.users
    SET
      name = COALESCE(p_name, name),
      phone = COALESCE(p_phone, phone),
      address = COALESCE(p_address, address),
      updated_at = now()
    WHERE id = p_user_id;

    RAISE NOTICE '✅ [DEBUG] Usuario actualizado en public.users';

    -- Si es cliente, actualizar ubicación en client_profiles
    IF v_existing_role = 'client' THEN
      RAISE NOTICE '📍 [DEBUG] Actualizando ubicación en client_profiles...';
      
      UPDATE public.client_profiles
      SET
        lat = COALESCE(p_lat, lat),
        lon = COALESCE(p_lon, lon),
        address = COALESCE(p_address, address),
        address_structured = COALESCE(p_address_structured, address_structured),
        updated_at = now()
      WHERE user_id = p_user_id;

      IF FOUND THEN
        RAISE NOTICE '✅ [DEBUG] client_profiles actualizado con ubicación';
      ELSE
        RAISE NOTICE '❌ [DEBUG] NO se encontró client_profiles para user_id: %', p_user_id;
      END IF;
    END IF;

    v_result := jsonb_build_object(
      'success', true,
      'user_id', p_user_id,
      'action', 'updated'
    );
    RETURN v_result;
  ELSE
    RAISE NOTICE '🆕 [DEBUG] Usuario NO existe. Creando nuevo usuario...';
    RAISE NOTICE '   - Insertando en public.users:';
    RAISE NOTICE '     * id: %', p_user_id;
    RAISE NOTICE '     * email: %', p_email;
    RAISE NOTICE '     * name: %', p_name;
    RAISE NOTICE '     * role: %', p_role;
    RAISE NOTICE '     * phone: %', p_phone;
    RAISE NOTICE '     * address: %', p_address;
    
    -- ===============================================
    -- CREAR NUEVO USUARIO (LÓGICA ORIGINAL RESTAURADA)
    -- ===============================================
    INSERT INTO public.users (id, email, role, name, phone, address, created_at, updated_at)
    VALUES (p_user_id, p_email, p_role, p_name, p_phone, p_address, now(), now());

    RAISE NOTICE '✅ [DEBUG] Usuario creado exitosamente en public.users';

    -- Si es cliente, el trigger debe crear client_profiles
    IF p_role = 'client' THEN
      RAISE NOTICE '⏳ [DEBUG] Esperando que trigger cree client_profiles...';
      
      -- Esperar un momento para el trigger
      PERFORM pg_sleep(0.1);
      
      -- Verificar si se creó
      IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = p_user_id) THEN
        RAISE NOTICE '✅ [DEBUG] client_profiles fue creado por el trigger';
        
        -- ===============================================
        -- ACTUALIZAR UBICACIÓN EN client_profiles
        -- ===============================================
        RAISE NOTICE '📍 [DEBUG] Actualizando ubicación en client_profiles...';
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
          RAISE NOTICE '✅ [DEBUG] ¡Ubicación guardada exitosamente en client_profiles!';
          
          -- Verificar valores guardados
          DECLARE
            v_saved_lat double precision;
            v_saved_lon double precision;
            v_saved_address text;
          BEGIN
            SELECT lat, lon, address INTO v_saved_lat, v_saved_lon, v_saved_address
            FROM public.client_profiles
            WHERE user_id = p_user_id;
            
            RAISE NOTICE '🔍 [DEBUG] Valores verificados en DB:';
            RAISE NOTICE '   - lat guardado: %', v_saved_lat;
            RAISE NOTICE '   - lon guardado: %', v_saved_lon;
            RAISE NOTICE '   - address guardado: %', v_saved_address;
          END;
        ELSE
          RAISE NOTICE '❌ [DEBUG] ERROR: No se pudo actualizar client_profiles';
        END IF;
      ELSE
        RAISE NOTICE '❌ [DEBUG] ERROR: client_profiles NO fue creado por el trigger';
        RAISE NOTICE '   - Intentando crear manualmente...';
        
        -- Crear manualmente si el trigger falló
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
        
        RAISE NOTICE '✅ [DEBUG] client_profiles creado manualmente con ubicación';
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
    RAISE NOTICE '❌ [DEBUG] EXCEPCIÓN: %', SQLERRM;
    RAISE NOTICE '   - SQLSTATE: %', SQLSTATE;
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$;

-- Permisos
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid,text,text,text,text,text,double precision,double precision,jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid,text,text,text,text,text,double precision,double precision,jsonb) TO authenticated;

-- Mensaje final
DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅✅✅ Script ejecutado exitosamente ✅✅✅';
  RAISE NOTICE '';
  RAISE NOTICE '📋 PRÓXIMOS PASOS:';
  RAISE NOTICE '   1. Realiza un registro de cliente desde Flutter';
  RAISE NOTICE '   2. Revisa los logs en: Supabase Dashboard > Database > Logs';
  RAISE NOTICE '   3. Busca logs que empiecen con [DEBUG]';
  RAISE NOTICE '';
END $$;
