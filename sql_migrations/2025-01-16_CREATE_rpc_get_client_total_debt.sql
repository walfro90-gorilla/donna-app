-- ========================================================
-- FECHA: 2025-01-16
-- DESCRIPCIÓN: Crear RPC para obtener el adeudo total de un cliente
-- ========================================================
-- Este script crea una función RPC que retorna el adeudo total pendiente de un cliente
-- basándose en la tabla client_debts con status = 'pending'
-- ========================================================

-- Drop si existe
DROP FUNCTION IF EXISTS public.get_client_total_debt(uuid);

-- Crear función RPC
CREATE OR REPLACE FUNCTION public.get_client_total_debt(p_client_id uuid)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_debt numeric;
BEGIN
  -- Sumar todas las deudas pendientes del cliente
  SELECT COALESCE(SUM(amount), 0)
  INTO v_total_debt
  FROM client_debts
  WHERE client_id = p_client_id
    AND status = 'pending';
  
  RETURN v_total_debt;
END;
$$;

-- Grant execute a usuarios autenticados
GRANT EXECUTE ON FUNCTION public.get_client_total_debt(uuid) TO authenticated;

-- Comentario
COMMENT ON FUNCTION public.get_client_total_debt(uuid) IS 
'Retorna el adeudo total pendiente de un cliente (suma de client_debts con status = pending)';

-- ========================================================
-- VERIFICACIÓN
-- ========================================================
-- Ejemplo de uso:
-- SELECT get_client_total_debt('client-uuid-aqui');
-- 
-- Si el cliente tiene deudas pendientes, retornará el total
-- Si no tiene deudas, retornará 0
-- ========================================================
