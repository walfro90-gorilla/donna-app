-- =====================================================
-- FASE 3: MIGRACIÓN DE DATOS
-- =====================================================
-- Mueve datos de columnas obsoletas a sus nuevas ubicaciones
-- Tiempo estimado: 10-15 minutos
-- =====================================================

BEGIN;

-- ====================================
-- PASO 1: Agregar columna profile_image_url a client_profiles
-- ====================================
ALTER TABLE public.client_profiles
ADD COLUMN IF NOT EXISTS profile_image_url TEXT;

-- ====================================
-- PASO 2: Migrar avatar_url de users a client_profiles
-- ====================================
-- Solo migrar para usuarios con rol 'cliente' que tengan avatar_url
UPDATE public.client_profiles cp
SET profile_image_url = u.avatar_url
FROM public.users u
WHERE cp.user_id = u.id
  AND u.avatar_url IS NOT NULL
  AND u.role IN ('cliente', 'client');

-- ====================================
-- PASO 3: Crear client_profiles para clientes sin perfil
-- ====================================
-- Asegurar que todos los clientes tengan su perfil
INSERT INTO public.client_profiles (
  user_id,
  profile_image_url,
  created_at,
  updated_at
)
SELECT 
  u.id,
  u.avatar_url,
  NOW(),
  NOW()
FROM public.users u
WHERE u.role IN ('cliente', 'client')
  AND NOT EXISTS (
    SELECT 1 FROM public.client_profiles cp WHERE cp.user_id = u.id
  );

-- ====================================
-- PASO 4: Validar integridad de datos
-- ====================================
-- Verificar que no hay datos huérfanos

-- Usuarios sin perfil según su rol
CREATE TEMP TABLE validation_report AS
SELECT 
  u.id,
  u.email,
  u.role,
  CASE 
    WHEN u.role IN ('cliente', 'client') THEN 
      EXISTS(SELECT 1 FROM client_profiles WHERE user_id = u.id)
    WHEN u.role IN ('restaurante', 'restaurant') THEN 
      EXISTS(SELECT 1 FROM restaurants WHERE user_id = u.id)
    WHEN u.role IN ('repartidor', 'delivery_agent') THEN 
      EXISTS(SELECT 1 FROM delivery_agent_profiles WHERE user_id = u.id)
    ELSE TRUE
  END AS has_profile
FROM public.users u
WHERE u.role != 'admin';

-- Log de validación
INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_MIGRATION',
  'Validación de integridad de datos',
  jsonb_build_object(
    'timestamp', NOW(),
    'total_users', (SELECT COUNT(*) FROM users),
    'users_without_profile', (SELECT COUNT(*) FROM validation_report WHERE NOT has_profile),
    'avatars_migrated', (SELECT COUNT(*) FROM client_profiles WHERE profile_image_url IS NOT NULL)
  )
);

-- ====================================
-- PASO 5: Reporte de migración
-- ====================================
DO $$
DECLARE
  v_total_users INTEGER;
  v_clients INTEGER;
  v_restaurants INTEGER;
  v_delivery_agents INTEGER;
  v_orphans INTEGER;
  v_avatars_migrated INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_total_users FROM users;
  SELECT COUNT(*) INTO v_clients FROM users WHERE role IN ('cliente', 'client');
  SELECT COUNT(*) INTO v_restaurants FROM users WHERE role IN ('restaurante', 'restaurant');
  SELECT COUNT(*) INTO v_delivery_agents FROM users WHERE role IN ('repartidor', 'delivery_agent');
  SELECT COUNT(*) INTO v_orphans FROM validation_report WHERE NOT has_profile;
  SELECT COUNT(*) INTO v_avatars_migrated FROM client_profiles WHERE profile_image_url IS NOT NULL;

  RAISE NOTICE '========================================';
  RAISE NOTICE 'REPORTE DE MIGRACIÓN DE DATOS';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Total usuarios: %', v_total_users;
  RAISE NOTICE 'Clientes: %', v_clients;
  RAISE NOTICE 'Restaurantes: %', v_restaurants;
  RAISE NOTICE 'Repartidores: %', v_delivery_agents;
  RAISE NOTICE 'Usuarios sin perfil: %', v_orphans;
  RAISE NOTICE 'Avatares migrados: %', v_avatars_migrated;
  RAISE NOTICE '========================================';

  IF v_orphans > 0 THEN
    RAISE WARNING 'HAY % USUARIOS SIN PERFIL - REVISAR ANTES DE CONTINUAR', v_orphans;
  END IF;
END $$;

COMMIT;

-- Verificación final: Usuarios sin perfil
SELECT 
  id,
  email,
  role,
  has_profile
FROM validation_report
WHERE NOT has_profile;

-- ✅ Si no hay resultados aquí, la migración fue exitosa
-- ⚠️ Si hay resultados, corregir antes de continuar a FASE 4
