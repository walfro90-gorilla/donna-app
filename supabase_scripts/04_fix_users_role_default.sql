-- ============================================================================
-- 🔧 FIX: DEFAULT ROLE VALUE
-- ============================================================================
-- Objetivo: Corregir el valor por defecto de users.role de 'cliente' a 'client'.
-- Esto asegura que los nuevos usuarios se creen con el rol correcto en inglés.
-- ============================================================================

BEGIN;

-- 1. Cambiar el default a 'client' (Inglés)
ALTER TABLE public.users 
ALTER COLUMN role SET DEFAULT 'client';

-- 2. Asegurar que la documentación refleje el cambio
COMMENT ON COLUMN public.users.role IS 'ENUM (English): client, restaurant, delivery_agent, admin. Default: client.';

COMMIT;
