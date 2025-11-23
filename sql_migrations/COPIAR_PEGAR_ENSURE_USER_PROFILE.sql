-- ============================================================================
-- 🎯 FIX: Error "users_role_check constraint violation"
-- ============================================================================
-- Crea RPC ensure_user_profile_public() con normalización automática de roles
-- Tiempo: < 5 segundos | Safe to run: no modifica datos existentes
-- ============================================================================

-- Drop existing (permite re-ejecutar el script)
DROP FUNCTION IF EXISTS public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) CASCADE;

-- RPC para asegurar perfil de usuario (idempotente)
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
SET search_path = public
AS $$
DECLARE
  v_exists boolean;
  v_is_email_confirmed boolean := false;
  v_now timestamptz := now();
  v_normalized_role text;
BEGIN
  -- Validar que el usuario existe en auth.users
  IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', format('User ID %s does not exist in auth.users', p_user_id),
      'data', NULL
    );
  END IF;

  -- Obtener estado de confirmación de email
  SELECT (email_confirmed_at IS NOT NULL) INTO v_is_email_confirmed
  FROM auth.users WHERE id = p_user_id;

  -- ✅ NORMALIZAR ROL: español → inglés
  v_normalized_role := CASE lower(trim(coalesce(p_role, '')))
    WHEN 'usuario' THEN 'client'
    WHEN 'cliente' THEN 'client'
    WHEN 'client' THEN 'client'
    WHEN 'restaurante' THEN 'restaurant'
    WHEN 'restaurant' THEN 'restaurant'
    WHEN 'repartidor' THEN 'delivery_agent'
    WHEN 'delivery' THEN 'delivery_agent'
    WHEN 'delivery_agent' THEN 'delivery_agent'
    WHEN 'admin' THEN 'admin'
    ELSE 'client'
  END;

  -- Verificar si el usuario ya existe en public.users
  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;

  IF NOT v_exists THEN
    -- Crear nuevo perfil
    INSERT INTO public.users (
      id, email, name, phone, role, email_confirm, created_at, updated_at
    ) VALUES (
      p_user_id,
      coalesce(nullif(trim(p_email), ''), ''),
      coalesce(nullif(trim(p_name), ''), ''),
      nullif(trim(p_phone), ''),
      v_normalized_role,
      coalesce(v_is_email_confirmed, false),
      v_now,
      v_now
    );
  ELSE
    -- Actualizar perfil existente
    UPDATE public.users u SET
      email = coalesce(nullif(trim(p_email), ''), u.email),
      name = coalesce(nullif(trim(p_name), ''), u.name),
      phone = coalesce(nullif(trim(p_phone), ''), u.phone),
      role = CASE 
        WHEN u.role IN ('client', 'cliente', '') THEN v_normalized_role
        ELSE u.role
      END,
      email_confirm = coalesce(u.email_confirm, v_is_email_confirmed),
      updated_at = v_now
    WHERE u.id = p_user_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', NULL);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);
END;
$$;

-- Grant permisos
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text, text, double precision, double precision, jsonb) TO anon, authenticated, service_role;

-- Verificación
DO $$
BEGIN
  IF EXISTS(SELECT 1 FROM pg_proc WHERE proname = 'ensure_user_profile_public' AND pronamespace = 'public'::regnamespace) THEN
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ RPC ensure_user_profile_public CREADA';
    RAISE NOTICE '========================================';
  ELSE
    RAISE WARNING '❌ Error al crear RPC';
  END IF;
END $$;
