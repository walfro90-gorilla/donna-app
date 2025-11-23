-- =============================================
-- RPC: has_active_couriers()
-- Devuelve TRUE si existe al menos 1 repartidor con
-- status = 'online' y account_state = 'approved'.
-- Implementada como SECURITY DEFINER para bypass de RLS
-- en delivery_agent_profiles. Otorga EXECUTE a authenticated/anon.
-- =============================================

DO $$ BEGIN
  -- Borrar versión previa si existe
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE p.proname = 'has_active_couriers'
      AND n.nspname = 'public'
  ) THEN
    DROP FUNCTION public.has_active_couriers();
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.has_active_couriers()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _exists BOOLEAN;
BEGIN
  -- Importante: usar EXISTS para que sea rápido y sólo lea 1 fila.
  SELECT EXISTS (
    SELECT 1
    FROM public.delivery_agent_profiles p
    WHERE p.status = 'online'
      AND p.account_state = 'approved'
  ) INTO _exists;

  RETURN COALESCE(_exists, FALSE);
END;
$$;

-- Permisos de ejecución para clientes web y usuarios autenticados
GRANT EXECUTE ON FUNCTION public.has_active_couriers() TO anon;
GRANT EXECUTE ON FUNCTION public.has_active_couriers() TO authenticated;

COMMENT ON FUNCTION public.has_active_couriers() IS 'Returns true if there is at least one delivery agent with status=online and account_state=approved. SECURITY DEFINER to bypass RLS.';
