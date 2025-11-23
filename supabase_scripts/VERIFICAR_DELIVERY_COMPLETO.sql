-- =============================================================
-- SCRIPT DE VERIFICACIÓN: DELIVERY AGENT REGISTRATION
-- =============================================================
-- Ejecutar DESPUÉS de registrar un delivery agent para verificar
-- que TODOS los registros se crearon correctamente
-- =============================================================

-- ============================================================
-- 1) VERIFICAR QUE LA FUNCIÓN RPC EXISTE Y TIENE PERMISOS
-- ============================================================

SELECT 
  p.proname AS "Nombre Función",
  pg_get_function_identity_arguments(p.oid) AS "Parámetros",
  d.description AS "Descripción",
  pg_catalog.array_to_string(p.proacl, E'\n') AS "Permisos"
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
LEFT JOIN pg_description d ON d.objoid = p.oid
WHERE n.nspname = 'public' 
  AND p.proname = 'register_delivery_agent_atomic';

-- ============================================================
-- 2) VERIFICAR QUE EL TRIGGER ESTÁ DESACTIVADO
-- ============================================================

SELECT 
  tgname AS "Trigger Name",
  CASE tgenabled
    WHEN 'O' THEN 'ENABLED'
    WHEN 'D' THEN 'DISABLED'
    ELSE 'UNKNOWN'
  END AS "Status"
FROM pg_trigger
WHERE tgrelid = 'auth.users'::regclass
  AND tgname = 'trg_handle_new_user_on_auth_users';
-- Debería retornar 0 filas (trigger eliminado)

-- ============================================================
-- 3) VERIFICAR REGISTROS DE UN DELIVERY AGENT ESPECÍFICO
-- ============================================================
-- IMPORTANTE: Reemplaza 'usuario@ejemplo.com' con el email real del 
-- delivery agent que acabas de registrar

DO $$
DECLARE
  v_test_email text := 'walfro90.dev@gmail.com'; -- ⭐ CAMBIAR ESTE EMAIL
  v_user_id uuid;
BEGIN
  -- Buscar el user_id por email
  SELECT id INTO v_user_id 
  FROM auth.users 
  WHERE email = v_test_email;

  IF v_user_id IS NULL THEN
    RAISE NOTICE '❌ No se encontró usuario con email: %', v_test_email;
    RETURN;
  END IF;

  RAISE NOTICE '✅ Usuario encontrado: %', v_user_id;
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'VERIFICACIÓN DE REGISTROS';
  RAISE NOTICE '========================================';

  -- Verificar auth.users
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_user_id) THEN
    RAISE NOTICE '✅ auth.users: EXISTS';
  ELSE
    RAISE NOTICE '❌ auth.users: MISSING';
  END IF;

  -- Verificar public.users con role correcto
  DECLARE
    v_role text;
  BEGIN
    SELECT role INTO v_role FROM public.users WHERE id = v_user_id;
    IF v_role IS NOT NULL THEN
      IF v_role = 'delivery_agent' THEN
        RAISE NOTICE '✅ public.users: EXISTS (role: %)', v_role;
      ELSE
        RAISE NOTICE '⚠️  public.users: EXISTS pero role incorrecto: % (esperado: delivery_agent)', v_role;
      END IF;
    ELSE
      RAISE NOTICE '❌ public.users: MISSING';
    END IF;
  END;

  -- Verificar delivery_agent_profiles
  IF EXISTS (SELECT 1 FROM public.delivery_agent_profiles WHERE user_id = v_user_id) THEN
    RAISE NOTICE '✅ delivery_agent_profiles: EXISTS';
  ELSE
    RAISE NOTICE '❌ delivery_agent_profiles: MISSING';
  END IF;

  -- Verificar accounts con tipo correcto
  DECLARE
    v_account_type text;
    v_balance numeric;
  BEGIN
    SELECT account_type, balance INTO v_account_type, v_balance 
    FROM public.accounts 
    WHERE user_id = v_user_id AND account_type = 'delivery_agent';
    
    IF v_account_type IS NOT NULL THEN
      RAISE NOTICE '✅ accounts: EXISTS (type: %, balance: %)', v_account_type, v_balance;
    ELSE
      RAISE NOTICE '❌ accounts (delivery_agent): MISSING';
    END IF;
  END;

  -- Verificar user_preferences
  IF EXISTS (SELECT 1 FROM public.user_preferences WHERE user_id = v_user_id) THEN
    RAISE NOTICE '✅ user_preferences: EXISTS';
  ELSE
    RAISE NOTICE '❌ user_preferences: MISSING';
  END IF;

  -- Verificar que NO exista client_profiles (debería estar limpio)
  IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = v_user_id) THEN
    RAISE NOTICE '⚠️  client_profiles: EXISTS (NO DEBERÍA EXISTIR para delivery_agent)';
  ELSE
    RAISE NOTICE '✅ client_profiles: CORRECTAMENTE AUSENTE';
  END IF;

  RAISE NOTICE '========================================';
END $$;

-- ============================================================
-- 4) LISTAR TODOS LOS DELIVERY AGENTS REGISTRADOS
-- ============================================================

SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  dap.status AS "delivery_status",
  dap.account_state,
  dap.vehicle_type,
  dap.vehicle_plate,
  a.balance,
  u.created_at
FROM public.users u
JOIN public.delivery_agent_profiles dap ON dap.user_id = u.id
LEFT JOIN public.accounts a ON a.user_id = u.id AND a.account_type = 'delivery_agent'
WHERE u.role = 'delivery_agent'
ORDER BY u.created_at DESC;

-- ============================================================
-- 5) DETECTAR REGISTROS INCONSISTENTES (LIMPIEZA)
-- ============================================================

-- Buscar usuarios con role='delivery_agent' pero sin perfil de delivery
SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  '❌ Falta delivery_agent_profiles' AS issue
FROM public.users u
WHERE u.role = 'delivery_agent'
  AND NOT EXISTS (
    SELECT 1 FROM public.delivery_agent_profiles dap WHERE dap.user_id = u.id
  );

-- Buscar usuarios con perfil de delivery pero role incorrecto
SELECT 
  u.id,
  u.email,
  u.name,
  u.role,
  '⚠️  Role incorrecto (debería ser delivery_agent)' AS issue
FROM public.users u
WHERE EXISTS (
    SELECT 1 FROM public.delivery_agent_profiles dap WHERE dap.user_id = u.id
  )
  AND u.role != 'delivery_agent';
