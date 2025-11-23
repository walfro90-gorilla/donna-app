-- ============================================================================
-- FIX QUIRÚRGICO: Guardar ubicación en client_profiles
-- ============================================================================
-- PROBLEMA: La tabla 'client_profiles' no guarda lat, lon, address_structured
-- SOLUCIÓN: Actualizar el RPC 'ensure_user_profile_public()' para extraer
--           datos de ubicación desde raw_user_meta_data y actualizar client_profiles
-- ============================================================================
-- INSTRUCCIONES:
-- 1. Copia todo este script
-- 2. Pégalo en Supabase SQL Editor
-- 3. Ejecuta (Run)
-- ============================================================================

-- Eliminar función existente
DROP FUNCTION IF EXISTS public.ensure_user_profile_public(uuid, text, text, text, text);

-- Crear función actualizada con soporte para ubicación de clientes
CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(
  p_user_id uuid,
  p_email text,
  p_role text,
  p_name text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_user record;
  v_user_meta jsonb;
  v_lat double precision;
  v_lon double precision;
  v_address_structured jsonb;
  v_result json;
BEGIN
  -- Validar rol
  IF p_role NOT IN ('client', 'restaurant', 'delivery_agent', 'admin') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be one of: client, restaurant, delivery_agent, admin', p_role;
  END IF;

  -- Obtener metadata del usuario desde auth.users
  SELECT raw_user_meta_data INTO v_user_meta
  FROM auth.users
  WHERE id = p_user_id;

  -- Extraer datos de ubicación (para clientes)
  IF p_role = 'client' AND v_user_meta IS NOT NULL THEN
    v_lat := (v_user_meta->>'lat')::double precision;
    v_lon := (v_user_meta->>'lon')::double precision;
    v_address_structured := v_user_meta->'address_structured';
  END IF;

  -- Buscar usuario existente
  SELECT * INTO v_existing_user
  FROM public.users
  WHERE id = p_user_id;

  IF v_existing_user IS NULL THEN
    -- Crear nuevo usuario
    INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at)
    VALUES (p_user_id, p_email, p_role, p_name, p_phone, now(), now());

    -- Si es cliente, crear client_profiles con ubicación
    IF p_role = 'client' THEN
      INSERT INTO public.client_profiles (
        user_id,
        lat,
        lon,
        address_structured,
        created_at,
        updated_at
      )
      VALUES (
        p_user_id,
        v_lat,
        v_lon,
        v_address_structured,
        now(),
        now()
      );
    END IF;

    -- Crear user_preferences
    INSERT INTO public.user_preferences (user_id, created_at, updated_at)
    VALUES (p_user_id, now(), now())
    ON CONFLICT (user_id) DO NOTHING;

    v_result := json_build_object(
      'user_id', p_user_id,
      'created', true,
      'role', p_role
    );
  ELSE
    -- Usuario existe: actualizar datos
    UPDATE public.users
    SET 
      email = p_email,
      role = p_role,
      name = COALESCE(p_name, name),
      phone = COALESCE(p_phone, phone),
      updated_at = now()
    WHERE id = p_user_id;

    -- Si es cliente, actualizar ubicación en client_profiles
    IF p_role = 'client' THEN
      UPDATE public.client_profiles
      SET
        lat = COALESCE(v_lat, lat),
        lon = COALESCE(v_lon, lon),
        address_structured = COALESCE(v_address_structured, address_structured),
        updated_at = now()
      WHERE user_id = p_user_id;
    END IF;

    -- Asegurar user_preferences existe
    INSERT INTO public.user_preferences (user_id, created_at, updated_at)
    VALUES (p_user_id, now(), now())
    ON CONFLICT (user_id) DO NOTHING;

    v_result := json_build_object(
      'user_id', p_user_id,
      'created', false,
      'updated', true,
      'role', p_role
    );
  END IF;

  RETURN v_result;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Error in ensure_user_profile_public: %', SQLERRM;
END;
$$;

-- Otorgar permisos
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_user_profile_public(uuid, text, text, text, text) TO anon;

-- ============================================================================
-- ✅ SCRIPT COMPLETADO
-- ============================================================================
-- Este script actualiza ÚNICAMENTE el RPC 'ensure_user_profile_public()'
-- para que guarde correctamente la ubicación en 'client_profiles'.
-- 
-- NO afecta otras funciones, triggers o tablas.
-- ============================================================================
