-- ============================================================================
-- FIX URGENTE: Agregar 'confirmed' a get_client_active_orders
-- ============================================================================
-- PROBLEMA: La función RPC get_client_active_orders no incluye el status
--           'confirmed', causando que las órdenes desaparezcan cuando el
--           repartidor las acepta
-- SOLUCIÓN: Actualizar el WHERE clause con todos los status activos correctos
-- FECHA: 2025-11-16
-- ============================================================================

-- DROP si existe
DROP FUNCTION IF EXISTS get_client_active_orders(uuid);

-- Crear función RPC con status correctos
CREATE OR REPLACE FUNCTION get_client_active_orders(client_id_param uuid)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  restaurant_id uuid,
  delivery_agent_id uuid,
  status text,
  total_amount numeric,
  delivery_fee numeric,
  payment_method text,
  delivery_address text,
  delivery_latlng text,
  delivery_lat double precision,
  delivery_lon double precision,
  delivery_place_id text,
  delivery_address_structured jsonb,
  pickup_code character varying,
  confirm_code character varying,
  order_notes text,
  assigned_at timestamptz,
  delivery_time timestamptz,
  pickup_time timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  -- Campos del delivery agent
  delivery_user_name text,
  delivery_user_phone text
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    o.id,
    o.user_id,
    o.restaurant_id,
    o.delivery_agent_id,
    o.status,
    o.total_amount,
    o.delivery_fee,
    o.payment_method,
    o.delivery_address,
    o.delivery_latlng,
    o.delivery_lat,
    o.delivery_lon,
    o.delivery_place_id,
    o.delivery_address_structured,
    o.pickup_code,
    o.confirm_code,
    o.order_notes,
    o.assigned_at,
    o.delivery_time,
    o.pickup_time,
    o.created_at,
    o.updated_at,
    -- Delivery agent info desde users
    u.name AS delivery_user_name,
    u.phone AS delivery_user_phone
  FROM orders o
  -- LEFT JOIN con users para obtener nombre y teléfono del delivery agent
  LEFT JOIN users u ON u.id = o.delivery_agent_id
  WHERE 
    o.user_id = client_id_param
    -- ✅ FIXED: Ahora incluye 'confirmed' y todos los status activos
    AND o.status IN ('pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'on_the_way')
  ORDER BY o.created_at DESC;
END;
$$;

-- Otorgar permisos
GRANT EXECUTE ON FUNCTION get_client_active_orders(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_client_active_orders(uuid) TO anon;

-- ============================================================================
-- VERIFICACIÓN
-- ============================================================================
-- Ejecutar con tu user_id para verificar:
-- SELECT * FROM get_client_active_orders('c7c5e7d1-4511-4690-91a9-127831e26f7e');
