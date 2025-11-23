-- =============================================================
-- Desactivar trigger automático en auth.users
-- 
-- RAZÓN: El trigger handle_new_user() crea automáticamente perfiles
-- de cliente para TODOS los usuarios nuevos, causando conflictos
-- cuando registramos restaurantes o delivery agents.
-- 
-- SOLUCIÓN: Los RPCs atómicos (register_restaurant_v2, 
-- register_delivery_agent_atomic) ya crean todos los registros
-- necesarios según el role correcto. El trigger es redundante
-- y causa errores 500.
-- =============================================================

-- 1) Eliminar trigger en auth.users si existe
DROP TRIGGER IF EXISTS trg_handle_new_user_on_auth_users ON auth.users;

-- 2) Mantener la función por compatibilidad pero sin trigger
-- (por si algún código legacy la usa explícitamente)
-- La función handle_new_user() permanece pero no se ejecuta automáticamente

-- 3) Verificación: mostrar triggers activos en auth.users
SELECT tgname, tgenabled
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'auth' AND c.relname = 'users';
