-- ============================================================================
-- FUNCIÓN RPC OPTIMIZADA: get_order_full_details
-- ============================================================================
-- PROPÓSITO: Obtener una orden específica con TODA la información relacionada
--            (restaurant, delivery agent, order items con productos) en formato JSON
--            para ser consumida directamente por DoaOrder.fromJson()
-- FECHA: 2025-11-17
-- AUTOR: Hologram  
-- APEGADO A: DATABASE_SCHEMA.sql
-- ============================================================================

-- DROP si existe
DROP FUNCTION IF EXISTS get_order_full_details(uuid);

-- Crear función RPC que devuelve JSON completo
CREATE OR REPLACE FUNCTION get_order_full_details(order_id_param uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  order_json jsonb;
BEGIN
  -- Construir JSON completo con todos los joins necesarios
  SELECT jsonb_build_object(
    -- Campos principales de la orden
    'id', o.id,
    'user_id', o.user_id,
    'restaurant_id', o.restaurant_id,
    'delivery_agent_id', o.delivery_agent_id,
    'status', o.status,
    'total_amount', o.total_amount,
    'delivery_fee', o.delivery_fee,
    'payment_method', o.payment_method,
    'delivery_address', o.delivery_address,
    'delivery_latlng', o.delivery_latlng,
    'delivery_lat', o.delivery_lat,
    'delivery_lon', o.delivery_lon,
    'delivery_place_id', o.delivery_place_id,
    'delivery_address_structured', o.delivery_address_structured,
    'pickup_code', o.pickup_code,
    'confirm_code', o.confirm_code,
    'order_notes', o.order_notes,
    'assigned_at', o.assigned_at,
    'delivery_time', o.delivery_time,
    'pickup_time', o.pickup_time,
    'created_at', o.created_at,
    'updated_at', o.updated_at,
    'subtotal', o.subtotal,
    'cancellation_reason', o.cancellation_reason,
    
    -- Restaurant completo con user info
    'restaurant', CASE 
      WHEN r.id IS NOT NULL THEN
        jsonb_build_object(
          'id', r.id,
          'user_id', r.user_id,
          'name', r.name,
          'description', r.description,
          'logo_url', r.logo_url,
          'cover_image_url', r.cover_image_url,
          'menu_image_url', r.menu_image_url,
          'status', r.status,
          'online', r.online,
          'address', r.address,
          'phone', r.phone,
          'average_rating', r.average_rating,
          'total_reviews', r.total_reviews,
          'latitude', r.location_lat,
          'longitude', r.location_lon,
          'location_place_id', r.location_place_id,
          'address_structured', r.address_structured,
          'delivery_time', r.delivery_time,
          'delivery_fee', r.delivery_fee,
          'min_order_amount', r.min_order_amount,
          'created_at', r.created_at,
          'updated_at', r.updated_at,
          -- User del restaurante
          'user', CASE 
            WHEN ru.id IS NOT NULL THEN
              jsonb_build_object(
                'id', ru.id,
                'email', ru.email,
                'name', ru.name,
                'phone', ru.phone,
                'role', ru.role,
                'created_at', ru.created_at
              )
            ELSE NULL
          END
        )
      ELSE NULL
    END,
    
    -- Delivery Agent completo
    'delivery_agent', CASE 
      WHEN du.id IS NOT NULL THEN
        jsonb_build_object(
          'id', du.id,
          'email', du.email,
          'name', du.name,
          'phone', du.phone,
          'role', du.role,
          'created_at', du.created_at,
          -- Datos del perfil de delivery
          'profile', CASE 
            WHEN dap.user_id IS NOT NULL THEN
              jsonb_build_object(
                'vehicle_type', dap.vehicle_type,
                'vehicle_plate', dap.vehicle_plate,
                'vehicle_model', dap.vehicle_model,
                'vehicle_color', dap.vehicle_color,
                'status', dap.status::text,
                'account_state', dap.account_state::text,
                'onboarding_completed', dap.onboarding_completed
              )
            ELSE NULL
          END
        )
      ELSE NULL
    END,
    
    -- Order Items con productos completos
    'order_items', COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'id', oi.id,
            'order_id', oi.order_id,
            'product_id', oi.product_id,
            'quantity', oi.quantity,
            'price_at_time_of_order', oi.price_at_time_of_order,
            'unit_price', oi.unit_price,
            'created_at', oi.created_at,
            -- Producto completo
            'product', CASE 
              WHEN p.id IS NOT NULL THEN
                jsonb_build_object(
                  'id', p.id,
                  'restaurant_id', p.restaurant_id,
                  'name', p.name,
                  'description', p.description,
                  'price', p.price,
                  'image_url', p.image_url,
                  'is_available', p.is_available,
                  'type', p.type::text,
                  'contains', p.contains,
                  'created_at', p.created_at,
                  'updated_at', p.updated_at
                )
              ELSE NULL
            END
          )
        )
        FROM order_items oi
        LEFT JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    )
  )
  INTO order_json
  FROM orders o
  -- JOIN restaurant con su user
  LEFT JOIN restaurants r ON r.id = o.restaurant_id
  LEFT JOIN users ru ON ru.id = r.user_id
  -- JOIN delivery agent con su perfil
  LEFT JOIN users du ON du.id = o.delivery_agent_id
  LEFT JOIN delivery_agent_profiles dap ON dap.user_id = du.id
  WHERE o.id = order_id_param;
  
  RETURN order_json;
END;
$$;

-- Otorgar permisos
GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_order_full_details(uuid) TO anon;

-- ============================================================================
-- COMENTARIO: Esta función devuelve un JSON completo que puede ser consumido
--             directamente por DoaOrder.fromJson() sin necesidad de conversiones
--             adicionales. Incluye TODOS los datos relacionados en una sola llamada.
-- ============================================================================

-- ============================================================================
-- TEST: Verificar que la función funciona correctamente
-- ============================================================================
-- Descomenta para probar con un order_id real:
-- SELECT get_order_full_details('TU_ORDER_ID_AQUI');
