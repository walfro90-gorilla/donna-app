-- =====================================================================
-- 11_create_indexes_OPTIMIZADO.sql
-- =====================================================================
-- Crea índices para optimizar queries comunes en la aplicación
-- Basado en DATABASE_SCHEMA.sql y patrones de uso típicos
-- =====================================================================

-- ====================================
-- ÍNDICES EN public.users
-- ====================================
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON public.users(created_at DESC);

-- ====================================
-- ÍNDICES EN client_profiles
-- ====================================
CREATE INDEX IF NOT EXISTS idx_client_profiles_user_id ON public.client_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_client_profiles_lat_lon ON public.client_profiles(lat, lon);

-- ====================================
-- ÍNDICES EN restaurants
-- ====================================
CREATE INDEX IF NOT EXISTS idx_restaurants_user_id ON public.restaurants(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_status ON public.restaurants(status);
CREATE INDEX IF NOT EXISTS idx_restaurants_online ON public.restaurants(online) WHERE online = true;
CREATE INDEX IF NOT EXISTS idx_restaurants_location ON public.restaurants(location_lat, location_lon);
CREATE INDEX IF NOT EXISTS idx_restaurants_name ON public.restaurants(name);
CREATE INDEX IF NOT EXISTS idx_restaurants_created_at ON public.restaurants(created_at DESC);

-- ====================================
-- ÍNDICES EN delivery_agent_profiles
-- ====================================
CREATE INDEX IF NOT EXISTS idx_delivery_agent_profiles_user_id ON public.delivery_agent_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_delivery_agent_profiles_status ON public.delivery_agent_profiles(status);
CREATE INDEX IF NOT EXISTS idx_delivery_agent_profiles_account_state ON public.delivery_agent_profiles(account_state);
CREATE INDEX IF NOT EXISTS idx_delivery_agent_profiles_vehicle_type ON public.delivery_agent_profiles(vehicle_type);

-- ====================================
-- ÍNDICES EN orders
-- ====================================
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_id ON public.orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_agent_id ON public.orders(delivery_agent_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_location ON public.orders(delivery_lat, delivery_lon);

-- Índice compuesto para queries del dashboard de restaurante
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status_created ON public.orders(restaurant_id, status, created_at DESC);

-- Índice compuesto para queries del dashboard de repartidor
CREATE INDEX IF NOT EXISTS idx_orders_delivery_status_created ON public.orders(delivery_agent_id, status, created_at DESC) WHERE delivery_agent_id IS NOT NULL;

-- ====================================
-- ÍNDICES EN order_items
-- ====================================
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items(product_id);

-- ====================================
-- ÍNDICES EN products
-- ====================================
CREATE INDEX IF NOT EXISTS idx_products_restaurant_id ON public.products(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON public.products(is_available) WHERE is_available = true;
CREATE INDEX IF NOT EXISTS idx_products_type ON public.products(type);

-- ====================================
-- ÍNDICES EN reviews
-- ====================================
CREATE INDEX IF NOT EXISTS idx_reviews_order_id ON public.reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_author_id ON public.reviews(author_id);
CREATE INDEX IF NOT EXISTS idx_reviews_subject_user_id ON public.reviews(subject_user_id);
CREATE INDEX IF NOT EXISTS idx_reviews_subject_restaurant_id ON public.reviews(subject_restaurant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_created_at ON public.reviews(created_at DESC);

-- ====================================
-- ÍNDICES EN accounts
-- ====================================
CREATE INDEX IF NOT EXISTS idx_accounts_user_id ON public.accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_account_type ON public.accounts(account_type);

-- ====================================
-- ÍNDICES EN account_transactions
-- ====================================
CREATE INDEX IF NOT EXISTS idx_account_transactions_account_id ON public.account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_order_id ON public.account_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_settlement_id ON public.account_transactions(settlement_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_type ON public.account_transactions(type);
CREATE INDEX IF NOT EXISTS idx_account_transactions_created_at ON public.account_transactions(created_at DESC);

-- ====================================
-- ÍNDICES EN settlements
-- ====================================
CREATE INDEX IF NOT EXISTS idx_settlements_payer_account_id ON public.settlements(payer_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_receiver_account_id ON public.settlements(receiver_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON public.settlements(status);
CREATE INDEX IF NOT EXISTS idx_settlements_initiated_at ON public.settlements(initiated_at DESC);

-- ====================================
-- ÍNDICES EN admin_notifications
-- ====================================
CREATE INDEX IF NOT EXISTS idx_admin_notifications_target_role ON public.admin_notifications(target_role);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_category ON public.admin_notifications(category);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_entity_type ON public.admin_notifications(entity_type);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_is_read ON public.admin_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_admin_notifications_created_at ON public.admin_notifications(created_at DESC);

-- ====================================
-- ÍNDICES EN user_preferences
-- ====================================
CREATE INDEX IF NOT EXISTS idx_user_preferences_user_id ON public.user_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_preferences_restaurant_id ON public.user_preferences(restaurant_id);

-- ====================================
-- ÍNDICES EN courier_locations_latest
-- ====================================
CREATE INDEX IF NOT EXISTS idx_courier_locations_latest_user_id ON public.courier_locations_latest(user_id);
CREATE INDEX IF NOT EXISTS idx_courier_locations_latest_order_id ON public.courier_locations_latest(order_id);
CREATE INDEX IF NOT EXISTS idx_courier_locations_latest_location ON public.courier_locations_latest(lat, lon);

-- ====================================
-- ÍNDICES EN courier_locations_history
-- ====================================
CREATE INDEX IF NOT EXISTS idx_courier_locations_history_user_id ON public.courier_locations_history(user_id);
CREATE INDEX IF NOT EXISTS idx_courier_locations_history_order_id ON public.courier_locations_history(order_id);
CREATE INDEX IF NOT EXISTS idx_courier_locations_history_recorded_at ON public.courier_locations_history(recorded_at DESC);

-- ====================================
-- ÍNDICES EN order_status_updates
-- ====================================
CREATE INDEX IF NOT EXISTS idx_order_status_updates_order_id ON public.order_status_updates(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_updates_created_at ON public.order_status_updates(created_at DESC);

-- ====================================
-- VERIFICACIÓN
-- ====================================
SELECT 
  '✅ ÍNDICES CREADOS EXITOSAMENTE' as status,
  COUNT(*) as total_indices
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%';

-- Ver todos los índices creados
SELECT 
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
