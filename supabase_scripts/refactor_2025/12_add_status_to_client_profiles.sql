-- ============================================================================
-- Script: 12_add_status_to_client_profiles.sql
-- Descripcion: Agrega campo 'status' a la tabla client_profiles
-- Autor: Sistema
-- Fecha: 2025-01-XX
-- ============================================================================

-- PASO 1: Agregar columna 'status' a client_profiles
-- ============================================================================
ALTER TABLE public.client_profiles 
ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active'
CHECK (status IN ('active', 'inactive', 'suspended'));

COMMENT ON COLUMN public.client_profiles.status IS 
'Estado del perfil del cliente: active (activo), inactive (inactivo), suspended (suspendido por admin)';


-- PASO 2: Crear índice para búsquedas por status
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_client_profiles_status 
ON public.client_profiles(status);


-- PASO 3: Actualizar todos los registros existentes a 'active'
-- ============================================================================
UPDATE public.client_profiles
SET status = 'active'
WHERE status IS NULL;


-- PASO 4: Verificar la estructura actualizada
-- ============================================================================
DO $$
DECLARE
  v_column_exists boolean;
  v_count integer;
BEGIN
  -- Verificar que la columna existe
  SELECT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'client_profiles' 
    AND column_name = 'status'
  ) INTO v_column_exists;

  IF v_column_exists THEN
    RAISE NOTICE '[OK] Columna status existe en client_profiles';
    
    -- Contar registros
    SELECT COUNT(*) INTO v_count FROM public.client_profiles;
    RAISE NOTICE '[OK] Total de client_profiles: %', v_count;
    
    -- Mostrar distribución por status
    RAISE NOTICE '[INFO] Distribucion por status:';
    FOR v_count IN 
      SELECT status, COUNT(*) as total 
      FROM public.client_profiles 
      GROUP BY status
    LOOP
      RAISE NOTICE '  - %: % registros', v_count, v_count;
    END LOOP;
  ELSE
    RAISE EXCEPTION '[ERROR] La columna status NO fue creada correctamente';
  END IF;
END $$;


-- ============================================================================
-- FIN DEL SCRIPT
-- ============================================================================
