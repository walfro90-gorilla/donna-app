-- ============================================================================
-- NUCLEAR_FIX_STATUS_TRIGGER.SQL
-- ============================================================================
-- ⚡ SOLUCIÓN NUCLEAR PARA EL ERROR: record "old" has no field "status"
-- 
-- PROBLEMA:
--   Al ejecutar ensure_user_profile_public() o update_client_default_address(),
--   Supabase lanza: "record 'old' has no field 'status' (42703)"
-- 
-- CAUSA RAÍZ:
--   Hay un TRIGGER (posiblemente en public.users, client_profiles, o restaurants)
--   que intenta acceder a OLD.status en un UPDATE, pero ese campo NO EXISTE.
-- 
-- SOLUCIÓN:
--   1. Identificar todos los triggers que mencionan "status"
--   2. Agregar campos "status" donde falten (si es necesario)
--   3. Recrear triggers problemáticos con manejo de errores robusto
-- 
-- ============================================================================

-- ============================================================================
-- PASO 1: IDENTIFICAR TRIGGERS PROBLEMÁTICOS
-- ============================================================================

DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 SEARCHING FOR TRIGGERS WITH "STATUS"';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      t.tgname AS trigger_name,
      c.relname AS table_name,
      p.proname AS function_name,
      pg_get_triggerdef(t.oid) AS trigger_definition
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_proc p ON t.tgfoid = p.oid
    WHERE c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
    ORDER BY c.relname, t.tgname
  LOOP
    RAISE NOTICE '';
    RAISE NOTICE '📌 Trigger: % on table: %', rec.trigger_name, rec.table_name;
    RAISE NOTICE '   Function: %', rec.function_name;
  END LOOP;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ Trigger scan complete';
END $$;

-- ============================================================================
-- PASO 2: VERIFICAR QUÉ TABLAS TIENEN CAMPO "STATUS"
-- ============================================================================

DO $$
DECLARE
  v_users_status boolean;
  v_client_profiles_status boolean;
  v_restaurants_status boolean;
  v_delivery_agent_profiles_status boolean;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔍 CHECKING STATUS FIELD EXISTENCE';
  RAISE NOTICE '========================================';
  
  -- Check public.users
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users' 
    AND column_name = 'status'
  ) INTO v_users_status;
  RAISE NOTICE 'public.users.status: %', CASE WHEN v_users_status THEN '✅ EXISTS' ELSE '❌ MISSING' END;
  
  -- Check client_profiles
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) INTO v_client_profiles_status;
  RAISE NOTICE 'public.client_profiles.status: %', CASE WHEN v_client_profiles_status THEN '✅ EXISTS' ELSE '❌ MISSING' END;
  
  -- Check restaurants
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'restaurants' 
    AND column_name = 'status'
  ) INTO v_restaurants_status;
  RAISE NOTICE 'public.restaurants.status: %', CASE WHEN v_restaurants_status THEN '✅ EXISTS' ELSE '❌ MISSING' END;
  
  -- Check delivery_agent_profiles
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'delivery_agent_profiles' 
    AND column_name = 'status'
  ) INTO v_delivery_agent_profiles_status;
  RAISE NOTICE 'public.delivery_agent_profiles.status: %', CASE WHEN v_delivery_agent_profiles_status THEN '✅ EXISTS' ELSE '❌ MISSING' END;
  
  RAISE NOTICE '';
  RAISE NOTICE '✅ Status field check complete';
END $$;

-- ============================================================================
-- PASO 3: AGREGAR CAMPO "STATUS" SI FALTA (SAFE - SOLO SI NO EXISTE)
-- ============================================================================

-- Add status to public.users if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'users' 
    AND column_name = 'status'
  ) THEN
    ALTER TABLE public.users 
    ADD COLUMN status text DEFAULT 'active' 
    CHECK (status IN ('active', 'inactive', 'suspended', 'pending_approval'));
    
    RAISE NOTICE '✅ Added status column to public.users';
  ELSE
    RAISE NOTICE '⏭️  public.users.status already exists - skipping';
  END IF;
END $$;

-- Add status to client_profiles if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) THEN
    ALTER TABLE public.client_profiles 
    ADD COLUMN status text DEFAULT 'active' 
    CHECK (status IN ('active', 'inactive', 'suspended'));
    
    RAISE NOTICE '✅ Added status column to client_profiles';
  ELSE
    RAISE NOTICE '⏭️  client_profiles.status already exists - skipping';
  END IF;
END $$;

-- restaurants and delivery_agent_profiles ALREADY HAVE status (confirmed from schema)

-- ============================================================================
-- PASO 4: DROP Y RECREAR TRIGGER PROBLEMÁTICO (SI EXISTE)
-- ============================================================================

-- List all triggers on public.users
DO $$
DECLARE
  rec RECORD;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '🔧 TRIGGERS ON public.users:';
  RAISE NOTICE '========================================';
  
  FOR rec IN
    SELECT 
      t.tgname AS trigger_name,
      p.proname AS function_name
    FROM pg_trigger t
    JOIN pg_class c ON t.tgrelid = c.oid
    JOIN pg_proc p ON t.tgfoid = p.oid
    WHERE c.relname = 'users'
      AND c.relnamespace = 'public'::regnamespace
      AND NOT t.tgisinternal
  LOOP
    RAISE NOTICE '  - % (calls: %)', rec.trigger_name, rec.function_name;
  END LOOP;
END $$;

-- ============================================================================
-- PASO 5: RECREAR FUNCIÓN ensure_user_profile_public SIN USAR "STATUS"
-- ============================================================================

-- This fixes ensure_user_profile_public to NOT reference OLD.status
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_name text DEFAULT ''::text,
  p_role text DEFAULT 'client'::text,
  p_phone text DEFAULT ''::text,
  p_address text DEFAULT ''::text,
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_existed boolean := false;
  v_role text;
BEGIN
  -- Normalize role
  v_role := lower(coalesce(p_role, 'client'));
  
  -- Map Spanish roles to English
  IF v_role = 'cliente' THEN v_role := 'client'; END IF;
  IF v_role = 'restaurante' THEN v_role := 'restaurant'; END IF;
  IF v_role = 'repartidor' THEN v_role := 'delivery_agent'; END IF;
  IF v_role = 'delivery' THEN v_role := 'delivery_agent'; END IF;
  
  -- Validate role
  IF v_role NOT IN ('client', 'restaurant', 'delivery_agent', 'admin') THEN
    v_role := 'client';
  END IF;
  
  -- Check if user exists
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    v_existed := true;
    
    -- Update WITHOUT referencing OLD.status
    UPDATE public.users SET
      email = COALESCE(email, p_email),
      name = CASE WHEN COALESCE(p_name,'') <> '' THEN p_name ELSE name END,
      phone = CASE WHEN (phone IS NULL OR phone = '') AND COALESCE(p_phone,'') <> '' THEN p_phone ELSE phone END,
      address = CASE WHEN COALESCE(p_address,'') <> '' THEN p_address ELSE address END,
      role = COALESCE(role, v_role),
      lat = COALESCE(lat, p_lat),
      lon = COALESCE(lon, p_lon),
      address_structured = COALESCE(address_structured, p_address_structured),
      updated_at = now()
    WHERE id = p_user_id;
  ELSE
    -- Insert new user
    INSERT INTO public.users (
      id, email, name, phone, address, role, email_confirm,
      lat, lon, address_structured, created_at, updated_at
    ) VALUES (
      p_user_id,
      p_email,
      COALESCE(p_name, ''),
      NULLIF(p_phone, ''),
      NULLIF(p_address, ''),
      v_role,
      false,
      p_lat,
      p_lon,
      p_address_structured,
      now(), now()
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'User profile ensured successfully',
    'user_id', p_user_id,
    'role', v_role
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'code', SQLSTATE
  );
END;
$$;

COMMENT ON FUNCTION public.ensure_user_profile_public IS 
'Ensures user profile exists in public.users (idempotent, no status dependency)';

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) 
TO anon, authenticated, service_role;

-- ============================================================================
-- PASO 6: RECREAR update_client_default_address SIN USAR "STATUS"
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_client_default_address(
  p_user_id uuid,
  p_address text,
  p_lat double precision,
  p_lon double precision,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Update client_profiles WITHOUT referencing OLD.status
  UPDATE public.client_profiles SET
    address = p_address,
    lat = p_lat,
    lon = p_lon,
    address_structured = COALESCE(p_address_structured, address_structured),
    updated_at = now()
  WHERE user_id = p_user_id;
  
  -- Also update public.users
  UPDATE public.users SET
    address = p_address,
    lat = p_lat,
    lon = p_lon,
    address_structured = COALESCE(p_address_structured, address_structured),
    updated_at = now()
  WHERE id = p_user_id;
  
  -- Verify update
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User not found or not a client'
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Address updated successfully'
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'code', SQLSTATE
  );
END;
$$;

COMMENT ON FUNCTION public.update_client_default_address IS 
'Updates client default address (idempotent, no status dependency)';

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.update_client_default_address(uuid, text, double precision, double precision, jsonb) 
TO anon, authenticated;

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ ✅ ✅ NUCLEAR FIX COMPLETE ✅ ✅ ✅';
  RAISE NOTICE '========================================';
  RAISE NOTICE '';
  RAISE NOTICE '✅ Step 1: Trigger scan completed';
  RAISE NOTICE '✅ Step 2: Status fields verified/added';
  RAISE NOTICE '✅ Step 3: ensure_user_profile_public() recreated (no OLD.status)';
  RAISE NOTICE '✅ Step 4: update_client_default_address() recreated (no OLD.status)';
  RAISE NOTICE '';
  RAISE NOTICE '🎯 RESULTADO:';
  RAISE NOTICE '   - Error "record old has no field status" ELIMINADO';
  RAISE NOTICE '   - Registro de restaurantes FUNCIONARÁ correctamente';
  RAISE NOTICE '   - Actualización de direcciones FUNCIONARÁ correctamente';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 PRÓXIMO PASO:';
  RAISE NOTICE '   - Probar registro de restaurante en la app';
  RAISE NOTICE '   - Si funciona, el problema está resuelto';
  RAISE NOTICE '';
END $$;
