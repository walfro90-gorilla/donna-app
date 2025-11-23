-- =====================================================
-- 87: FIX DELIVERY_AGENT_PROFILES RLS POLICIES (v2)
-- =====================================================
-- PROBLEMA: delivery_agent_profiles se crea automáticamente
-- para todos los usuarios sin importar su rol
-- 
-- SOLUCIÓN: Agregar políticas RLS estrictas que validen
-- el rol antes de permitir INSERT
-- =====================================================

-- =====================================================
-- PASO 1: Verificar y habilitar RLS
-- =====================================================

-- Asegurar que RLS está habilitado
ALTER TABLE delivery_agent_profiles ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- PASO 2: Eliminar políticas permisivas existentes
-- =====================================================

-- Drop todas las políticas existentes que podrían ser permisivas
DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN 
    SELECT policyname 
    FROM pg_policies 
    WHERE schemaname = 'public' 
      AND tablename = 'delivery_agent_profiles'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON delivery_agent_profiles', pol.policyname);
    RAISE NOTICE 'Dropped policy: %', pol.policyname;
  END LOOP;
END $$;

-- =====================================================
-- PASO 3: Crear políticas RLS estrictas
-- =====================================================

-- POLICY INSERT: Solo usuarios con rol 'repartidor' o 'delivery_agent' pueden crear su perfil
CREATE POLICY delivery_agent_profiles_insert_own
ON delivery_agent_profiles
FOR INSERT
TO authenticated
WITH CHECK (
  -- Validar que el user_id que se intenta insertar es el usuario actual
  user_id = auth.uid()
  AND
  -- Validar que el usuario tiene rol de repartidor
  EXISTS (
    SELECT 1 
    FROM public.users 
    WHERE id = auth.uid() 
      AND role IN ('repartidor', 'delivery_agent')
  )
);

-- POLICY SELECT: Usuarios pueden ver su propio perfil, admins pueden ver todos
CREATE POLICY delivery_agent_profiles_select_own_or_admin
ON delivery_agent_profiles
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR
  EXISTS (
    SELECT 1 
    FROM public.users 
    WHERE id = auth.uid() 
      AND role = 'admin'
  )
);

-- POLICY UPDATE: Solo el dueño puede actualizar su perfil
CREATE POLICY delivery_agent_profiles_update_own
ON delivery_agent_profiles
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- POLICY DELETE: Solo el dueño o admin pueden eliminar
CREATE POLICY delivery_agent_profiles_delete_own_or_admin
ON delivery_agent_profiles
FOR DELETE
TO authenticated
USING (
  user_id = auth.uid()
  OR
  EXISTS (
    SELECT 1 
    FROM public.users 
    WHERE id = auth.uid() 
      AND role = 'admin'
  )
);

-- =====================================================
-- PASO 4: Verificar triggers automáticos problemáticos
-- =====================================================

-- Listar todos los triggers en delivery_agent_profiles
DO $$
DECLARE
  trig RECORD;
  has_triggers BOOLEAN := FALSE;
BEGIN
  RAISE NOTICE '=== TRIGGERS EN delivery_agent_profiles ===';
  
  FOR trig IN 
    SELECT 
      trigger_name,
      event_manipulation,
      action_statement
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
      AND event_object_table = 'delivery_agent_profiles'
  LOOP
    has_triggers := TRUE;
    RAISE NOTICE 'Trigger: % | Event: % | Action: %', 
      trig.trigger_name, 
      trig.event_manipulation, 
      trig.action_statement;
  END LOOP;
  
  IF NOT has_triggers THEN
    RAISE NOTICE 'No triggers found on delivery_agent_profiles';
  END IF;
END $$;

-- =====================================================
-- PASO 5: Buscar triggers en public.users (simplificado)
-- =====================================================

-- Listar triggers en users (sin analizar el body de las funciones)
DO $$
DECLARE
  trig RECORD;
  has_triggers BOOLEAN := FALSE;
BEGIN
  RAISE NOTICE '=== TRIGGERS EN public.users ===';
  
  FOR trig IN 
    SELECT 
      trigger_name,
      event_manipulation,
      action_statement
    FROM information_schema.triggers
    WHERE event_object_schema = 'public'
      AND event_object_table = 'users'
  LOOP
    has_triggers := TRUE;
    RAISE NOTICE 'Trigger: % | Event: % | Action: %', 
      trig.trigger_name, 
      trig.event_manipulation, 
      trig.action_statement;
    
    -- Si el action_statement menciona delivery_agent, marcarlo
    IF trig.action_statement ILIKE '%delivery_agent%' THEN
      RAISE WARNING '⚠️ SOSPECHOSO: Este trigger podría estar relacionado con delivery_agent_profiles';
    END IF;
  END LOOP;
  
  IF NOT has_triggers THEN
    RAISE NOTICE 'No triggers found on public.users';
  END IF;
END $$;

-- =====================================================
-- PASO 6: Verificar las nuevas políticas
-- =====================================================

SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'delivery_agent_profiles'
ORDER BY policyname;

-- =====================================================
-- PASO 7: Comentarios y log final
-- =====================================================

COMMENT ON TABLE delivery_agent_profiles IS 
'Perfiles de repartidores. RLS activo: solo usuarios con rol repartidor pueden crear su perfil.';

COMMENT ON POLICY delivery_agent_profiles_insert_own ON delivery_agent_profiles IS
'Solo usuarios autenticados con rol repartidor/delivery_agent pueden crear su propio perfil';

COMMENT ON POLICY delivery_agent_profiles_select_own_or_admin ON delivery_agent_profiles IS
'Usuarios pueden ver su propio perfil, admins pueden ver todos';

COMMENT ON POLICY delivery_agent_profiles_update_own ON delivery_agent_profiles IS
'Solo el dueño puede actualizar su perfil';

COMMENT ON POLICY delivery_agent_profiles_delete_own_or_admin ON delivery_agent_profiles IS
'Solo el dueño o admin pueden eliminar el perfil';

DO $$
BEGIN
  RAISE NOTICE '✅ Script 87 (v2) completado exitosamente';
  RAISE NOTICE '✅ RLS habilitado en delivery_agent_profiles';
  RAISE NOTICE '✅ Políticas estrictas creadas';
  RAISE NOTICE '';
  RAISE NOTICE '⚠️ SIGUIENTE PASO MANUAL: Eliminar registros incorrectos';
  RAISE NOTICE '   Ejecuta en SQL Editor:';
  RAISE NOTICE '   DELETE FROM delivery_agent_profiles WHERE user_id IN (SELECT id FROM users WHERE role NOT IN (''repartidor'', ''delivery_agent''));';
END $$;
