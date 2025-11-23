-- =====================================================
-- LIMPIEZA COMPLETA DE POLÍTICAS RLS
-- =====================================================
-- Este script elimina TODAS las políticas RLS existentes
-- en las tablas afectadas por la refactorización
-- Ejecutar ANTES del script 09_update_rls_policies.sql
-- =====================================================

DO $$
DECLARE
  pol RECORD;
BEGIN
  -- ====================================
  -- Eliminar TODAS las políticas de users
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'users'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de users', pol.policyname;
  END LOOP;

  -- ====================================
  -- Eliminar TODAS las políticas de client_profiles
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'client_profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.client_profiles CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de client_profiles', pol.policyname;
  END LOOP;

  -- ====================================
  -- Eliminar TODAS las políticas de restaurants
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'restaurants'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.restaurants CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de restaurants', pol.policyname;
  END LOOP;

  -- ====================================
  -- Eliminar TODAS las políticas de delivery_agent_profiles
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'delivery_agent_profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.delivery_agent_profiles CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de delivery_agent_profiles', pol.policyname;
  END LOOP;

  -- ====================================
  -- Eliminar TODAS las políticas de accounts
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'accounts'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.accounts CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de accounts', pol.policyname;
  END LOOP;

  -- ====================================
  -- Eliminar TODAS las políticas de user_preferences
  -- ====================================
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'user_preferences'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_preferences CASCADE', pol.policyname);
    RAISE NOTICE 'Eliminada política: % de user_preferences', pol.policyname;
  END LOOP;

  -- Log de éxito
  INSERT INTO public.debug_logs (scope, message, meta)
  VALUES (
    'REFACTOR_2025_CLEANUP_POLICIES',
    'Todas las políticas RLS eliminadas exitosamente',
    jsonb_build_object(
      'timestamp', NOW(),
      'tables', ARRAY['users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'accounts', 'user_preferences']
    )
  );

  RAISE NOTICE '✅ Todas las políticas RLS han sido eliminadas exitosamente';
END $$;

-- Verificación: Confirmar que no queden políticas
SELECT 
  tablename,
  COUNT(*) as remaining_policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('users', 'client_profiles', 'restaurants', 'delivery_agent_profiles', 'accounts', 'user_preferences')
GROUP BY tablename;

-- Si no hay resultados, significa que todas las políticas fueron eliminadas correctamente
