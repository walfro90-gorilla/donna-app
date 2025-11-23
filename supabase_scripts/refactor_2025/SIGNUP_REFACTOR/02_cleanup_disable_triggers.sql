-- ============================================================================
-- FASE 1 - SCRIPT 02: DESACTIVAR TRIGGERS OBSOLETOS
-- ============================================================================
-- Descripción: Desactiva triggers conflictivos que causan problemas en signup.
--              NO los elimina, solo los desactiva para poder reactivarlos
--              si es necesario hacer rollback.
-- ============================================================================

-- ============================================================================
-- DESACTIVAR TRIGGERS EN delivery_agent_profiles
-- ============================================================================

-- 1. audit_delivery_agent_insert
-- Problema: BLOQUEA inserciones si el rol no es 'repartidor'
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'audit_delivery_agent_insert' 
    AND tgrelid = 'public.delivery_agent_profiles'::regclass
  ) THEN
    ALTER TABLE public.delivery_agent_profiles 
      DISABLE TRIGGER audit_delivery_agent_insert;
    RAISE NOTICE '✅ Trigger desactivado: audit_delivery_agent_insert';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: audit_delivery_agent_insert (ya fue eliminado)';
  END IF;
END $$;

-- 2. delivery_agent_profiles_guard
-- Problema: Otro guardia redundante que previene inserciones
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'delivery_agent_profiles_guard' 
    AND tgrelid = 'public.delivery_agent_profiles'::regclass
  ) THEN
    ALTER TABLE public.delivery_agent_profiles 
      DISABLE TRIGGER delivery_agent_profiles_guard;
    RAISE NOTICE '✅ Trigger desactivado: delivery_agent_profiles_guard';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: delivery_agent_profiles_guard (ya fue eliminado)';
  END IF;
END $$;

-- 3. guard_delivery_profile_role_trigger (si existe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'guard_delivery_profile_role_trigger' 
    AND tgrelid = 'public.delivery_agent_profiles'::regclass
  ) THEN
    ALTER TABLE public.delivery_agent_profiles 
      DISABLE TRIGGER guard_delivery_profile_role_trigger;
    RAISE NOTICE '✅ Trigger desactivado: guard_delivery_profile_role_trigger';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: guard_delivery_profile_role_trigger (ya fue eliminado)';
  END IF;
END $$;

-- 4. audit_and_block_delivery_agent_insert (si existe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'audit_and_block_delivery_agent_insert' 
    AND tgrelid = 'public.delivery_agent_profiles'::regclass
  ) THEN
    ALTER TABLE public.delivery_agent_profiles 
      DISABLE TRIGGER audit_and_block_delivery_agent_insert;
    RAISE NOTICE '✅ Trigger desactivado: audit_and_block_delivery_agent_insert';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: audit_and_block_delivery_agent_insert (ya fue eliminado)';
  END IF;
END $$;

-- ============================================================================
-- DESACTIVAR TRIGGERS EN public.users
-- ============================================================================

-- 5. create_account_on_user_approval
-- Problema: Crea accounts cuando status='approved', pero puede causar duplicados
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'create_account_on_user_approval' 
    AND tgrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users 
      DISABLE TRIGGER create_account_on_user_approval;
    RAISE NOTICE '✅ Trigger desactivado: create_account_on_user_approval';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: create_account_on_user_approval (ya fue eliminado)';
  END IF;
END $$;

-- 6. create_account_on_approval (si existe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'create_account_on_approval' 
    AND tgrelid = 'public.users'::regclass
  ) THEN
    ALTER TABLE public.users 
      DISABLE TRIGGER create_account_on_approval;
    RAISE NOTICE '✅ Trigger desactivado: create_account_on_approval';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: create_account_on_approval (ya fue eliminado)';
  END IF;
END $$;

-- ============================================================================
-- DESACTIVAR TRIGGERS EN client_profiles (si causan conflictos)
-- ============================================================================

-- 7. _trg_call_ensure_client_profile_and_account (si existe)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = '_trg_call_ensure_client_profile_and_account' 
    AND tgrelid = 'public.client_profiles'::regclass
  ) THEN
    ALTER TABLE public.client_profiles 
      DISABLE TRIGGER _trg_call_ensure_client_profile_and_account;
    RAISE NOTICE '✅ Trigger desactivado: _trg_call_ensure_client_profile_and_account';
  ELSE
    RAISE NOTICE '⚠️  Trigger no encontrado: _trg_call_ensure_client_profile_and_account (ya fue eliminado)';
  END IF;
END $$;

-- ============================================================================
-- MANTENER TRIGGERS ÚTILES (NO DESACTIVAR)
-- ============================================================================

-- ✅ NO DESACTIVAR: trg_users_normalize_role
--    Este trigger normaliza roles (client→cliente, restaurant→restaurante)
--    Es útil y NO causa conflictos.

-- ✅ NO DESACTIVAR: fn_notify_admin_on_new_*
--    Estos triggers envían notificaciones al admin.
--    Son útiles y NO causan conflictos.

-- ✅ NO DESACTIVAR: update_updated_at_column
--    Actualiza automáticamente la columna updated_at.
--    Es útil y NO causa conflictos.

-- ✅ NO DESACTIVAR: handle_user_email_confirmation
--    Actualiza email_confirm cuando el usuario confirma su email.
--    Es útil y NO causa conflictos.

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================

DO $$
DECLARE
  v_disabled_count INT;
BEGIN
  SELECT COUNT(*) INTO v_disabled_count
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  WHERE t.tgenabled = 'D' -- 'D' = Disabled, 'O' = Enabled
    AND c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('delivery_agent_profiles', 'users', 'client_profiles');
  
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ TRIGGERS DESACTIVADOS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Total de triggers desactivados en tablas críticas: %', v_disabled_count;
  RAISE NOTICE '';
  RAISE NOTICE '📋 Para ver todos los triggers desactivados:';
  RAISE NOTICE 'SELECT c.relname as tabla, t.tgname as trigger_name';
  RAISE NOTICE 'FROM pg_trigger t';
  RAISE NOTICE 'JOIN pg_class c ON c.oid = t.tgrelid';
  RAISE NOTICE 'WHERE t.tgenabled = ''D'' AND c.relnamespace = ''public''::regnamespace;';
  RAISE NOTICE '';
  RAISE NOTICE '✅ Puedes continuar con el script 03_cleanup_drop_rpcs.sql';
END $$;
