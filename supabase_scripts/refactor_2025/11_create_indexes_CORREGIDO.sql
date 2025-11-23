-- =====================================================================
-- 11_create_indexes_CORREGIDO.sql
-- =====================================================================
-- Crea indices para optimizar queries de la aplicacion
-- Basado en DATABASE_SCHEMA.sql actualizado
-- =====================================================================

-- ====================================
-- INDICES PARA TABLA: users
-- ====================================

-- Busqueda por email (login, registro)
DROP INDEX IF EXISTS idx_users_email;
CREATE INDEX idx_users_email ON public.users(email);

-- Busqueda por role (listar usuarios por tipo)
DROP INDEX IF EXISTS idx_users_role;
CREATE INDEX idx_users_role ON public.users(role);

-- Busqueda por phone (validaciones)
DROP INDEX IF EXISTS idx_users_phone;
CREATE INDEX idx_users_phone ON public.users(phone);

-- Busqueda por email_confirm (usuarios pendientes de verificacion)
DROP INDEX IF EXISTS idx_users_email_confirm;
CREATE INDEX idx_users_email_confirm ON public.users(email_confirm);

-- Ordenar por fecha de creacion
DROP INDEX IF EXISTS idx_users_created_at;
CREATE INDEX idx_users_created_at ON public.users(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: client_profiles
-- ====================================

-- Busqueda geografica (buscar clientes cerca)
DROP INDEX IF EXISTS idx_client_profiles_location;
CREATE INDEX idx_client_profiles_location ON public.client_profiles(lat, lon);

-- ====================================
-- INDICES PARA TABLA: restaurants
-- ====================================

-- Busqueda por user_id (obtener restaurante de un usuario)
DROP INDEX IF EXISTS idx_restaurants_user_id;
CREATE INDEX idx_restaurants_user_id ON public.restaurants(user_id);

-- Filtrar por status (restaurantes activos/pendientes/rechazados)
DROP INDEX IF EXISTS idx_restaurants_status;
CREATE INDEX idx_restaurants_status ON public.restaurants(status);

-- Busqueda geografica (buscar restaurantes cerca)
DROP INDEX IF EXISTS idx_restaurants_location;
CREATE INDEX idx_restaurants_location ON public.restaurants(lat, lon);

-- Ordenar por rating
DROP INDEX IF EXISTS idx_restaurants_rating;
CREATE INDEX idx_restaurants_rating ON public.restaurants(average_rating DESC);

-- Ordenar por fecha de creacion
DROP INDEX IF EXISTS idx_restaurants_created_at;
CREATE INDEX idx_restaurants_created_at ON public.restaurants(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: delivery_agent_profiles
-- ====================================

-- Filtrar por status (repartidores activos/offline/pending)
DROP INDEX IF EXISTS idx_delivery_agent_status;
CREATE INDEX idx_delivery_agent_status ON public.delivery_agent_profiles(status);

-- Filtrar por account_state (aprobados/rechazados/pendientes)
DROP INDEX IF EXISTS idx_delivery_agent_account_state;
CREATE INDEX idx_delivery_agent_account_state ON public.delivery_agent_profiles(account_state);

-- Filtrar por onboarding_completed
DROP INDEX IF EXISTS idx_delivery_agent_onboarding;
CREATE INDEX idx_delivery_agent_onboarding ON public.delivery_agent_profiles(onboarding_completed);

-- ====================================
-- INDICES PARA TABLA: orders
-- ====================================

-- Buscar ordenes por cliente
DROP INDEX IF EXISTS idx_orders_user_id;
CREATE INDEX idx_orders_user_id ON public.orders(user_id);

-- Buscar ordenes por restaurante
DROP INDEX IF EXISTS idx_orders_restaurant_id;
CREATE INDEX idx_orders_restaurant_id ON public.orders(restaurant_id);

-- Buscar ordenes por repartidor
DROP INDEX IF EXISTS idx_orders_delivery_agent_id;
CREATE INDEX idx_orders_delivery_agent_id ON public.orders(delivery_agent_id);

-- Filtrar por status (pendientes, confirmadas, en transito, etc)
DROP INDEX IF EXISTS idx_orders_status;
CREATE INDEX idx_orders_status ON public.orders(status);

-- Ordenar por fecha de creacion
DROP INDEX IF EXISTS idx_orders_created_at;
CREATE INDEX idx_orders_created_at ON public.orders(created_at DESC);

-- Ordenar por fecha de actualizacion
DROP INDEX IF EXISTS idx_orders_updated_at;
CREATE INDEX idx_orders_updated_at ON public.orders(updated_at DESC);

-- Busqueda geografica (ordenes cerca de ubicacion)
DROP INDEX IF EXISTS idx_orders_delivery_location;
CREATE INDEX idx_orders_delivery_location ON public.orders(delivery_lat, delivery_lon);

-- Indice compuesto: restaurante + status (ordenes activas de un restaurante)
DROP INDEX IF EXISTS idx_orders_restaurant_status;
CREATE INDEX idx_orders_restaurant_status ON public.orders(restaurant_id, status);

-- Indice compuesto: repartidor + status (ordenes activas de un repartidor)
DROP INDEX IF EXISTS idx_orders_delivery_agent_status;
CREATE INDEX idx_orders_delivery_agent_status ON public.orders(delivery_agent_id, status);

-- ====================================
-- INDICES PARA TABLA: order_items
-- ====================================

-- Buscar items de una orden
DROP INDEX IF EXISTS idx_order_items_order_id;
CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);

-- Buscar items por producto (analytics)
DROP INDEX IF EXISTS idx_order_items_product_id;
CREATE INDEX idx_order_items_product_id ON public.order_items(product_id);

-- ====================================
-- INDICES PARA TABLA: order_status_updates
-- ====================================

-- Buscar historial de estados de una orden
DROP INDEX IF EXISTS idx_order_status_updates_order_id;
CREATE INDEX idx_order_status_updates_order_id ON public.order_status_updates(order_id);

-- Ordenar por fecha
DROP INDEX IF EXISTS idx_order_status_updates_created_at;
CREATE INDEX idx_order_status_updates_created_at ON public.order_status_updates(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: products
-- ====================================

-- Buscar productos de un restaurante
DROP INDEX IF EXISTS idx_products_restaurant_id;
CREATE INDEX idx_products_restaurant_id ON public.products(restaurant_id);

-- Filtrar productos activos/inactivos
DROP INDEX IF EXISTS idx_products_available;
CREATE INDEX idx_products_available ON public.products(available);

-- Indice compuesto: restaurante + disponibilidad (productos activos de un restaurante)
DROP INDEX IF EXISTS idx_products_restaurant_available;
CREATE INDEX idx_products_restaurant_available ON public.products(restaurant_id, available);

-- ====================================
-- INDICES PARA TABLA: accounts
-- ====================================

-- Buscar cuenta por usuario
DROP INDEX IF EXISTS idx_accounts_user_id;
CREATE INDEX idx_accounts_user_id ON public.accounts(user_id);

-- Filtrar por tipo de cuenta
DROP INDEX IF EXISTS idx_accounts_type;
CREATE INDEX idx_accounts_type ON public.accounts(account_type);

-- Indice compuesto: usuario + tipo (obtener cuenta especifica de usuario)
DROP INDEX IF EXISTS idx_accounts_user_type;
CREATE INDEX idx_accounts_user_type ON public.accounts(user_id, account_type);

-- ====================================
-- INDICES PARA TABLA: account_transactions
-- ====================================

-- Buscar transacciones de una cuenta
DROP INDEX IF EXISTS idx_account_transactions_account_id;
CREATE INDEX idx_account_transactions_account_id ON public.account_transactions(account_id);

-- Buscar transacciones de una orden
DROP INDEX IF EXISTS idx_account_transactions_order_id;
CREATE INDEX idx_account_transactions_order_id ON public.account_transactions(order_id);

-- Buscar transacciones de un settlement
DROP INDEX IF EXISTS idx_account_transactions_settlement_id;
CREATE INDEX idx_account_transactions_settlement_id ON public.account_transactions(settlement_id);

-- Filtrar por tipo de transaccion
DROP INDEX IF EXISTS idx_account_transactions_type;
CREATE INDEX idx_account_transactions_type ON public.account_transactions(type);

-- Ordenar por fecha
DROP INDEX IF EXISTS idx_account_transactions_created_at;
CREATE INDEX idx_account_transactions_created_at ON public.account_transactions(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: settlements
-- ====================================

-- Buscar settlements por usuario
DROP INDEX IF EXISTS idx_settlements_user_id;
CREATE INDEX idx_settlements_user_id ON public.settlements(user_id);

-- Filtrar por status
DROP INDEX IF EXISTS idx_settlements_status;
CREATE INDEX idx_settlements_status ON public.settlements(status);

-- Ordenar por fecha de creacion
DROP INDEX IF EXISTS idx_settlements_created_at;
CREATE INDEX idx_settlements_created_at ON public.settlements(created_at DESC);

-- Indice compuesto: usuario + status
DROP INDEX IF EXISTS idx_settlements_user_status;
CREATE INDEX idx_settlements_user_status ON public.settlements(user_id, status);

-- ====================================
-- INDICES PARA TABLA: reviews
-- ====================================

-- Buscar reviews de un restaurante
DROP INDEX IF EXISTS idx_reviews_restaurant_id;
CREATE INDEX idx_reviews_restaurant_id ON public.reviews(restaurant_id);

-- Buscar reviews de un cliente
DROP INDEX IF EXISTS idx_reviews_user_id;
CREATE INDEX idx_reviews_user_id ON public.reviews(user_id);

-- Buscar reviews de una orden
DROP INDEX IF EXISTS idx_reviews_order_id;
CREATE INDEX idx_reviews_order_id ON public.reviews(order_id);

-- Ordenar por fecha
DROP INDEX IF EXISTS idx_reviews_created_at;
CREATE INDEX idx_reviews_created_at ON public.reviews(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: courier_locations_latest
-- ====================================

-- Busqueda geografica (repartidores cerca)
DROP INDEX IF EXISTS idx_courier_locations_latest_location;
CREATE INDEX idx_courier_locations_latest_location ON public.courier_locations_latest(lat, lon);

-- Buscar ubicacion por order_id
DROP INDEX IF EXISTS idx_courier_locations_latest_order_id;
CREATE INDEX idx_courier_locations_latest_order_id ON public.courier_locations_latest(order_id);

-- Ordenar por ultima actualizacion
DROP INDEX IF EXISTS idx_courier_locations_latest_last_seen;
CREATE INDEX idx_courier_locations_latest_last_seen ON public.courier_locations_latest(last_seen_at DESC);

-- ====================================
-- INDICES PARA TABLA: courier_locations_history
-- ====================================

-- Buscar historial por usuario
DROP INDEX IF EXISTS idx_courier_locations_history_user_id;
CREATE INDEX idx_courier_locations_history_user_id ON public.courier_locations_history(user_id);

-- Buscar historial por orden
DROP INDEX IF EXISTS idx_courier_locations_history_order_id;
CREATE INDEX idx_courier_locations_history_order_id ON public.courier_locations_history(order_id);

-- Ordenar por fecha de registro
DROP INDEX IF EXISTS idx_courier_locations_history_recorded_at;
CREATE INDEX idx_courier_locations_history_recorded_at ON public.courier_locations_history(recorded_at DESC);

-- ====================================
-- INDICES PARA TABLA: admin_notifications
-- ====================================

-- Filtrar por leido/no leido
DROP INDEX IF EXISTS idx_admin_notifications_is_read;
CREATE INDEX idx_admin_notifications_is_read ON public.admin_notifications(is_read);

-- Filtrar por categoria
DROP INDEX IF EXISTS idx_admin_notifications_category;
CREATE INDEX idx_admin_notifications_category ON public.admin_notifications(category);

-- Filtrar por entity_type
DROP INDEX IF EXISTS idx_admin_notifications_entity_type;
CREATE INDEX idx_admin_notifications_entity_type ON public.admin_notifications(entity_type);

-- Buscar por entity_id
DROP INDEX IF EXISTS idx_admin_notifications_entity_id;
CREATE INDEX idx_admin_notifications_entity_id ON public.admin_notifications(entity_id);

-- Ordenar por fecha
DROP INDEX IF EXISTS idx_admin_notifications_created_at;
CREATE INDEX idx_admin_notifications_created_at ON public.admin_notifications(created_at DESC);

-- ====================================
-- INDICES PARA TABLA: user_preferences
-- ====================================

-- Buscar preferencias por usuario (ya existe PK, pero por si acaso)
DROP INDEX IF EXISTS idx_user_preferences_user_id;
CREATE INDEX idx_user_preferences_user_id ON public.user_preferences(user_id);

-- ====================================
-- INDICES PARA TABLA: product_combos
-- ====================================

-- Buscar combos por producto
DROP INDEX IF EXISTS idx_product_combos_product_id;
CREATE INDEX idx_product_combos_product_id ON public.product_combos(product_id);

-- Buscar combos por restaurante
DROP INDEX IF EXISTS idx_product_combos_restaurant_id;
CREATE INDEX idx_product_combos_restaurant_id ON public.product_combos(restaurant_id);

-- ====================================
-- INDICES PARA TABLA: product_combo_items
-- ====================================

-- Buscar items de un combo
DROP INDEX IF EXISTS idx_product_combo_items_combo_id;
CREATE INDEX idx_product_combo_items_combo_id ON public.product_combo_items(combo_id);

-- Buscar combos que contengan un producto
DROP INDEX IF EXISTS idx_product_combo_items_product_id;
CREATE INDEX idx_product_combo_items_product_id ON public.product_combo_items(product_id);

-- ====================================
-- INDICES PARA TABLA: payments
-- ====================================

-- Buscar pagos de una orden
DROP INDEX IF EXISTS idx_payments_order_id;
CREATE INDEX idx_payments_order_id ON public.payments(order_id);

-- Filtrar por status
DROP INDEX IF EXISTS idx_payments_status;
CREATE INDEX idx_payments_status ON public.payments(status);

-- Buscar por stripe_payment_id
DROP INDEX IF EXISTS idx_payments_stripe_id;
CREATE INDEX idx_payments_stripe_id ON public.payments(stripe_payment_id);

-- ====================================
-- RESUMEN DE INDICES CREADOS
-- ====================================

SELECT 
  '[INFO] Total de indices creados exitosamente' as resultado,
  COUNT(*) as total_indices
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%';

SELECT 
  '[INFO] Indices creados por tabla' as resultado,
  tablename,
  COUNT(*) as num_indices
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
GROUP BY tablename
ORDER BY num_indices DESC, tablename;
