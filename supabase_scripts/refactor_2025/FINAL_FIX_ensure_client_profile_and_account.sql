-- =============================================================================
-- SOLUCIÓN DEFINITIVA: Actualizar ensure_client_profile_and_account() 
--                      para incluir campo 'status'
-- =============================================================================
-- Problema: La función no incluye 'status' en el INSERT, 
--           pero la tabla client_profiles tiene status NOT NULL DEFAULT 'active'
-- Solución: Recrear la función con el campo 'status' incluido
-- =============================================================================

-- 1. ELIMINAR función vieja (todas las variantes)
DROP FUNCTION IF EXISTS public.ensure_client_profile_and_account(uuid);

-- 2. RECREAR función con campo 'status' incluido
CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- ✅ Incluir 'status' con valor 'active' por defecto
  INSERT INTO public.client_profiles AS cp (user_id, status, created_at, updated_at)
  VALUES (p_user_id, 'active', now(), now())
  ON CONFLICT (user_id) DO UPDATE 
  SET updated_at = excluded.updated_at;

  -- Asegurar registro en accounts con tipo 'client'
  INSERT INTO public.accounts AS a (user_id, account_type, balance)
  VALUES (p_user_id, 'client', 0.00)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  -- Log detallado del error
  RAISE WARNING 'ensure_client_profile_and_account failed for user %: % (DETAIL: %)', 
    p_user_id, SQLERRM, SQLSTATE;
  RAISE;
END;
$$;

COMMENT ON FUNCTION public.ensure_client_profile_and_account(uuid) IS 
  'Ensures client_profiles row (with status=active) and client financial account exist for given user_id';

GRANT EXECUTE ON FUNCTION public.ensure_client_profile_and_account(uuid) TO anon, authenticated, service_role;

-- =============================================================================
-- 3. VERIFICACIÓN RÁPIDA (opcional - puedes descomentar para testing)
-- =============================================================================
-- SELECT pg_get_functiondef('public.ensure_client_profile_and_account(uuid)'::regprocedure);

-- =============================================================================
-- LISTO PARA EJECUTAR
-- =============================================================================
-- Este script:
-- ✅ Elimina la función vieja que NO incluía 'status'
-- ✅ Recrea la función con 'status' = 'active' por defecto
-- ✅ Agrega logging detallado en caso de error
-- ✅ Mantiene compatibilidad con trigger handle_new_user()
-- =============================================================================
