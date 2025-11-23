-- =============================================================
-- Fix RLS recursion on public.users
--
-- Purpose:
--   Elimina políticas SELECT recursivas en public.users y crea
--   una política mínima y segura para autenticados.
--
-- Por qué:
--   El error "infinite recursion detected in policy for relation 'users'"
--   ocurre cuando alguna política hace subconsultas que vuelven a tocar
--   public.users (directa o indirectamente). Con este script removemos
--   todas las políticas SELECT existentes en public.users y añadimos
--   una sola política simple que no usa subconsultas.
--
-- Cómo usar:
--   1) Copiar y pegar en el editor SQL de Supabase y ejecutar.
--   2) No requiere variables ni privilegios especiales (rol propietario del esquema público).
--
-- Idempotencia:
--   - El bloque DO elimina todas las políticas SELECT existentes en users.
--   - La política nueva se crea sólo si no existe, usando verificación previa.
-- =============================================================

-- Asegura que la tabla existe en el esquema esperado
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND c.relname = 'users'
  ) THEN
    RAISE EXCEPTION 'Tabla public.users no existe en este proyecto';
  END IF;
END $$;

-- 1) Eliminar TODAS las políticas de tipo SELECT en public.users
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN (
    SELECT policyname
    FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND cmd = 'SELECT'
  ) LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.users', r.policyname);
  END LOOP;
END $$;

-- 2) Crear una política SELECT mínima para autenticados (sin subconsultas)
--    Nota: Evitamos hacer JOINs o EXISTS dentro de USING para no reintroducir recursión.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND policyname = 'users_select_authenticated_basic'
  ) THEN
    EXECUTE $$
      CREATE POLICY "users_select_authenticated_basic"
      ON public.users
      FOR SELECT
      TO authenticated
      USING (auth.uid() IS NOT NULL)
    $$;
  END IF;
END $$;

-- 3) (Opcional) Si necesitas que los servicios (service_role) también lean sin RLS
--    no es necesario crear política, service_role bypass RLS.

-- 4) Asegurar que RLS esté habilitado (no cambia si ya lo está)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- 5) Recomendación: Evita políticas adicionales SELECT que hagan EXISTS/JOIN a orders/restaurants
--    Si necesitas restricciones más finas, hazlas a nivel de columnas o con vistas dedicadas.

-- Fin del script
