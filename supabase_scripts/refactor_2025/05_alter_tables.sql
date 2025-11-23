-- =====================================================
-- FASE 4: MODIFICACIÓN DE TABLAS
-- =====================================================
-- Elimina columnas obsoletas y simplifica estructura
-- Tiempo estimado: 10 minutos
-- ⚠️ PUNTO DE NO RETORNO FÁCIL - Asegurar backup en FASE 1
-- =====================================================

BEGIN;

-- ====================================
-- PASO 1: Eliminar columnas de public.users
-- ====================================

-- Eliminar avatar_url (ya migrado a client_profiles)
ALTER TABLE public.users
DROP COLUMN IF EXISTS avatar_url CASCADE;

-- Eliminar status (redundante con estado en perfiles específicos)
ALTER TABLE public.users
DROP COLUMN IF EXISTS status CASCADE;

-- Eliminar campos de rating (se calculan desde reviews)
ALTER TABLE public.users
DROP COLUMN IF EXISTS average_rating CASCADE;

ALTER TABLE public.users
DROP COLUMN IF EXISTS total_reviews CASCADE;

-- Eliminar campos de ubicación (ya existen en courier_locations_latest)
ALTER TABLE public.users
DROP COLUMN IF EXISTS current_location CASCADE;

ALTER TABLE public.users
DROP COLUMN IF EXISTS current_heading CASCADE;

-- ====================================
-- PASO 2: Normalizar roles en users
-- ====================================
-- Asegurar que solo existan los 4 roles permitidos

-- Actualizar roles legacy a los nuevos valores
UPDATE public.users
SET role = 'cliente'
WHERE role IN ('client', 'usuario', 'user');

UPDATE public.users
SET role = 'restaurante'
WHERE role IN ('restaurant');

UPDATE public.users
SET role = 'repartidor'
WHERE role IN ('delivery_agent', 'delivery', 'rider', 'courier');

-- ====================================
-- PASO 3: Actualizar constraint de roles
-- ====================================
-- Eliminar constraint viejo
ALTER TABLE public.users
DROP CONSTRAINT IF EXISTS users_role_check CASCADE;

-- Crear constraint nuevo con solo los 4 roles permitidos
ALTER TABLE public.users
ADD CONSTRAINT users_role_check 
CHECK (role IN ('cliente', 'restaurante', 'repartidor', 'admin'));

-- ====================================
-- PASO 4: Crear índices optimizados
-- ====================================

-- Índice para búsquedas por email (ya existe UNIQUE, pero mejoramos)
DROP INDEX IF EXISTS idx_users_email;
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email) 
WHERE email IS NOT NULL;

-- Índice para búsquedas por rol
DROP INDEX IF EXISTS idx_users_role;
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);

-- Índice para búsquedas por teléfono
DROP INDEX IF EXISTS idx_users_phone;
CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone) 
WHERE phone IS NOT NULL;

-- Índice compuesto para auth rápida
DROP INDEX IF EXISTS idx_users_email_role;
CREATE INDEX IF NOT EXISTS idx_users_email_role ON public.users(email, role);

-- ====================================
-- PASO 5: Índices en client_profiles
-- ====================================
CREATE INDEX IF NOT EXISTS idx_client_profiles_user_id 
ON public.client_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_client_profiles_location 
ON public.client_profiles(lat, lon)
WHERE lat IS NOT NULL AND lon IS NOT NULL;

-- ====================================
-- PASO 6: Validar estructura final
-- ====================================
DO $$
DECLARE
  v_users_columns INTEGER;
  v_expected_columns INTEGER := 8; -- id, email, name, phone, role, email_confirm, created_at, updated_at
BEGIN
  SELECT COUNT(*) INTO v_users_columns
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'users';

  RAISE NOTICE '========================================';
  RAISE NOTICE 'VALIDACIÓN DE ESTRUCTURA';
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Columnas en users: % (esperadas: %)', v_users_columns, v_expected_columns;
  RAISE NOTICE '========================================';

  IF v_users_columns != v_expected_columns THEN
    RAISE WARNING 'La tabla users tiene % columnas, se esperaban %', v_users_columns, v_expected_columns;
  END IF;
END $$;

-- Log de alteraciones
INSERT INTO public.debug_logs (scope, message, meta)
VALUES (
  'REFACTOR_2025_ALTER',
  'Tablas alteradas exitosamente',
  jsonb_build_object(
    'timestamp', NOW(),
    'fase', '4',
    'columnas_eliminadas', 6,
    'indices_creados', 7
  )
);

COMMIT;

-- Verificación: Ver estructura final de users
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'users'
ORDER BY ordinal_position;

-- ✅ Deberías ver exactamente 8 columnas:
-- id, email, name, phone, role, email_confirm, created_at, updated_at
