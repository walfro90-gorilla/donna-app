-- ============================================================================
-- ✅ FIX COMPLETO - Delivery Agent Registration Trigger
-- ============================================================================
-- Este script arregla el trigger que se dispara cuando se inserta un registro
-- en 'accounts' con account_type = 'delivery_agent'
--
-- PROBLEMA:
-- El trigger intenta llamar a 'ensure_delivery_agent_role_and_profile()'
-- pero la función no existe o usa valores de enum incorrectos
--
-- SOLUCIÓN:
-- Crear/actualizar la función con sintaxis PostgreSQL correcta
-- y valores de enum correctos según DATABASE_SCHEMA.sql
--
-- INSTRUCCIONES:
-- 1. Copia TODO este archivo (Ctrl+A / Cmd+A)
-- 2. Pega en Supabase SQL Editor
-- 3. Ejecuta
-- 4. Hot Restart de la app en Dreamflow
-- 5. Prueba el registro de delivery agent desde /nuevo-repartidor
-- ============================================================================

-- DROP function y trigger si existen (para recrear limpiamente)
DROP TRIGGER IF EXISTS trg_handle_delivery_agent_account_insert ON public.accounts CASCADE;
DROP TRIGGER IF EXISTS trg_handle_delivery_agent_account_update ON public.accounts CASCADE;
DROP FUNCTION IF EXISTS public.handle_delivery_agent_account_insert() CASCADE;
DROP FUNCTION IF EXISTS public.ensure_delivery_agent_role_and_profile(uuid) CASCADE;

-- ============================================================================
-- 1) Función: ensure_delivery_agent_role_and_profile
-- ============================================================================
-- Crea/actualiza el perfil de delivery agent cuando se crea una cuenta
-- financiera con account_type = 'delivery_agent'
--
CREATE OR REPLACE FUNCTION public.ensure_delivery_agent_role_and_profile(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
BEGIN
  -- 1. Actualizar role a 'delivery_agent' si es diferente
  UPDATE public.users
  SET 
    role = 'delivery_agent',
    updated_at = v_now
  WHERE id = p_user_id 
    AND COALESCE(role, '') != 'delivery_agent';

  -- 2. Crear perfil mínimo en delivery_agent_profiles
  --    (permite que el usuario complete su perfil dentro de la app)
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    status,
    account_state,
    onboarding_completed,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'pending'::delivery_agent_status,              -- Enum correcto según DATABASE_SCHEMA.sql
    'pending'::delivery_agent_account_state,       -- Enum correcto según DATABASE_SCHEMA.sql
    false,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;  -- Si ya existe, no hacer nada

  -- 3. Crear user_preferences si no existe
  INSERT INTO public.user_preferences (
    user_id,
    has_seen_onboarding,
    has_seen_delivery_welcome,
    delivery_welcome_seen_at,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    false,
    false,
    NULL,
    v_now,
    v_now
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', p_user_id,
    'created_at', v_now
  );

EXCEPTION WHEN OTHERS THEN
  -- Log error pero no fallar el trigger principal
  RAISE WARNING 'ensure_delivery_agent_role_and_profile ERROR: % | SQLSTATE: %', SQLERRM, SQLSTATE;
  
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'sqlstate', SQLSTATE
  );
END;
$$;

-- Grant permisos
GRANT EXECUTE ON FUNCTION public.ensure_delivery_agent_role_and_profile(uuid) 
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.ensure_delivery_agent_role_and_profile IS 
'Crea perfil mínimo de delivery agent cuando se crea una cuenta financiera.
Actualiza role en users, crea registro en delivery_agent_profiles y user_preferences.
Safe to call multiple times (idempotent).';

-- ============================================================================
-- 2) Función del Trigger: handle_delivery_agent_account_insert
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_delivery_agent_account_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Solo ejecutar si account_type es 'delivery_agent'
  IF NEW.account_type = 'delivery_agent' THEN
    PERFORM public.ensure_delivery_agent_role_and_profile(NEW.user_id);
  END IF;
  
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_delivery_agent_account_insert IS 
'Trigger function que asegura la creación del perfil de delivery agent
cuando se inserta o actualiza una cuenta con account_type = delivery_agent.';

-- ============================================================================
-- 3) Triggers: Insertar y Actualizar en accounts
-- ============================================================================

-- Trigger AFTER INSERT
CREATE TRIGGER trg_handle_delivery_agent_account_insert
AFTER INSERT ON public.accounts
FOR EACH ROW
EXECUTE FUNCTION public.handle_delivery_agent_account_insert();

-- Trigger AFTER UPDATE (solo cuando cambia account_type a 'delivery_agent')
CREATE TRIGGER trg_handle_delivery_agent_account_update
AFTER UPDATE OF account_type ON public.accounts
FOR EACH ROW
WHEN (
  NEW.account_type = 'delivery_agent' 
  AND COALESCE(OLD.account_type, '') != 'delivery_agent'
)
EXECUTE FUNCTION public.handle_delivery_agent_account_insert();

-- ============================================================================
-- 4) Backfill: Arreglar registros existentes que no tienen perfil
-- ============================================================================
DO $$
DECLARE 
  r RECORD;
  v_count integer := 0;
BEGIN
  -- Buscar cuentas de delivery_agent sin perfil o con role incorrecto
  FOR r IN
    SELECT a.user_id, u.role, p.user_id as has_profile
    FROM public.accounts a
    LEFT JOIN public.users u ON u.id = a.user_id
    LEFT JOIN public.delivery_agent_profiles p ON p.user_id = a.user_id
    WHERE a.account_type = 'delivery_agent'
      AND (u.role IS DISTINCT FROM 'delivery_agent' OR p.user_id IS NULL)
  LOOP
    -- Ejecutar la función de ensure para cada registro
    PERFORM public.ensure_delivery_agent_role_and_profile(r.user_id);
    v_count := v_count + 1;
  END LOOP;

  IF v_count > 0 THEN
    RAISE NOTICE '✅ Backfill completado: % registros actualizados', v_count;
  ELSE
    RAISE NOTICE 'ℹ️ No hay registros que necesiten backfill';
  END IF;
END $$;

-- ============================================================================
-- ✅ COMPLETADO
-- ============================================================================
-- Ahora cuando 'delivery_signup_screen.dart' llame a 'ensureFinancialAccount()',
-- el trigger se disparará correctamente y creará:
-- 1. delivery_agent_profiles (perfil mínimo)
-- 2. user_preferences
-- 3. Actualizará el role a 'delivery_agent'
--
-- El usuario podrá completar su perfil dentro de la app
-- ============================================================================
