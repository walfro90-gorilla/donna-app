-- ==========================================
-- PASO 5: Probar las funciones RPC (DESPUÉS de ejecutar scripts 1 y 2)
-- ==========================================

-- IMPORTANTE: Reemplaza los UUIDs con valores reales de tu base de datos

-- Primero, obtener algunos IDs reales para la prueba:
SELECT id, name, email FROM users LIMIT 3;
SELECT id, name FROM restaurants LIMIT 3;  
SELECT id, name, price FROM products LIMIT 3;

-- Ejemplo de prueba de create_order_safe (REEMPLAZA LOS UUIDs):
/*
SELECT create_order_safe(
    'REEMPLAZA-CON-USER-ID-REAL'::UUID,
    'REEMPLAZA-CON-RESTAURANT-ID-REAL'::UUID,
    125.50,
    'Calle 123, Ciudad',
    35.0,
    'Sin cebolla por favor',
    'cash'
);
*/

-- Ejemplo de prueba de insert_order_items (DESPUÉS de crear una orden):
/*
SELECT insert_order_items(
    123456789,  -- REEMPLAZA con el ID de orden devuelto por create_order_safe
    '[
        {
            "product_id": "REEMPLAZA-CON-PRODUCT-ID-REAL",
            "quantity": 2,
            "unit_price": 45.25
        },
        {
            "product_id": "REEMPLAZA-CON-OTRO-PRODUCT-ID-REAL", 
            "quantity": 1,
            "unit_price": 35.00
        }
    ]'::JSON
);
*/

-- Para verificar que la orden se creó correctamente:
-- SELECT * FROM orders ORDER BY created_at DESC LIMIT 5;
-- SELECT * FROM order_items WHERE order_id = 123456789;