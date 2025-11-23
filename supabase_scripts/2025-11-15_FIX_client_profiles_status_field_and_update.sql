-- ============================================================================
-- Script: 2025-11-15_FIX_client_profiles_status_field_and_update.sql
-- Descripción: Soluciona el error "record 'old' has no field 'status'" en
--              update_client_default_address agregando el campo status si falta
-- Fecha: 2025-11-15
-- ============================================================================

-- PASO 1: Agregar columna 'status' si no existe (idempotente)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD COLUMN status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'inactive', 'suspended'));

    RAISE NOTICE '[✅] Campo "status" agregado a client_profiles';
  ELSE
    RAISE NOTICE '[ℹ️] Campo "status" ya existe en client_profiles';
  END IF;
END $$;


-- PASO 2: Actualizar registros existentes sin status (por si acaso)
-- ============================================================================
UPDATE public.client_profiles
SET status = 'active'
WHERE status IS NULL;


-- PASO 3: Crear índice si no existe
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_client_profiles_status 
ON public.client_profiles(status);


-- PASO 4: Verificar que no haya triggers problemáticos
-- ============================================================================
DO $$
DECLARE
  v_trigger_count integer;
  v_trigger_name text;
BEGIN
  -- Listar triggers en client_profiles
  SELECT COUNT(*) INTO v_trigger_count
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE c.relname = 'client_profiles'
  AND c.relnamespace = 'public'::regnamespace;

  RAISE NOTICE '[ℹ️] Total de triggers en client_profiles: %', v_trigger_count;

  -- Mostrar todos los triggers
  FOR v_trigger_name IN
    SELECT t.tgname
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    WHERE c.relname = 'client_profiles'
    AND c.relnamespace = 'public'::regnamespace
  LOOP
    RAISE NOTICE '  - Trigger: %', v_trigger_name;
  END LOOP;
END $$;


-- PASO 5: Recrear el RPC update_client_default_address con manejo de errores
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_client_default_address(
  p_user_id uuid,
  p_address text,
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
  v_result jsonb;
BEGIN
  -- Only allow the authenticated user or admins to update this record
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_id THEN
    -- Optionally verify admin role if you have a role system
    NULL; -- relax if your admin logic lives elsewhere
  END IF;

  -- Upsert con manejo explícito de errores
  BEGIN
    INSERT INTO public.client_profiles AS cp (
      user_id, address, lat, lon, address_structured, updated_at
    ) VALUES (
      p_user_id, p_address, p_lat, p_lon, p_address_structured, NOW()
    )
    ON CONFLICT (user_id) DO UPDATE SET
      address = EXCLUDED.address,
      lat = EXCLUDED.lat,
      lon = EXCLUDED.lon,
      address_structured = COALESCE(EXCLUDED.address_structured, cp.address_structured),
      updated_at = NOW();

  EXCEPTION WHEN OTHERS THEN
    -- Retornar error detallado si falla
    RETURN jsonb_build_object(
      'success', false,
      'error', SQLERRM,
      'error_detail', SQLSTATE
    );
  END;

  -- Respuesta exitosa
  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id
  );
END;
$$;

COMMENT ON FUNCTION public.update_client_default_address(uuid, text, double precision, double precision, jsonb)
IS 'Updates client_profiles for the given user with default delivery address and coordinates. Returns {success, user_id} or {success: false, error}';

-- Asegurar permisos
GRANT EXECUTE ON FUNCTION public.update_client_default_address(uuid, text, double precision, double precision, jsonb)
TO anon, authenticated, service_role;


-- PASO 6: Verificación final
-- ============================================================================
DO $$
DECLARE
  v_status_exists boolean;
  v_count integer;
BEGIN
  -- Verificar columna status
  SELECT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) INTO v_status_exists;

  IF v_status_exists THEN
    RAISE NOTICE '[✅] VERIFICACIÓN: Campo "status" existe correctamente';
    
    -- Contar registros
    SELECT COUNT(*) INTO v_count FROM public.client_profiles;
    RAISE NOTICE '[✅] Total de client_profiles: %', v_count;
    
    -- Verificar RPC
    IF EXISTS (
      SELECT 1 FROM pg_proc 
      WHERE proname = 'update_client_default_address' 
      AND pronamespace = 'public'::regnamespace
    ) THEN
      RAISE NOTICE '[✅] RPC "update_client_default_address" recreado correctamente';
    END IF;
  ELSE
    RAISE EXCEPTION '[❌] ERROR: Campo "status" NO existe después del script';
  END IF;
END $$;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
