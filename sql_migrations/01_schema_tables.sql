-- ============================================================================
-- SCHEMA PRINCIPAL - TABLAS BASE
-- Sistema de delivery para Doa Repartos
-- ============================================================================

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- TABLA: users
-- Almacena información de todos los usuarios del sistema
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  email text UNIQUE NOT NULL,
  name text,
  phone text,
  address text,
  role text NOT NULL DEFAULT 'client' CHECK (role IN ('client', 'restaurant', 'delivery_agent', 'admin')),
  status text DEFAULT 'offline' CHECK (status IN ('offline', 'online', 'busy')),
  is_active boolean DEFAULT true,
  email_confirm boolean DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Ubicación (legacy, se usa address_structured para nuevos registros)
  lat double precision,
  lon double precision,
  
  -- Dirección estructurada (nuevo formato con todos los detalles)
  address_structured jsonb,
  
  -- Imágenes de perfil
  profile_image_url text,
  id_document_front_url text,
  id_document_back_url text,
  
  -- Información de vehículo (para repartidores)
  vehicle_type text,
  vehicle_plate text,
  vehicle_model text,
  vehicle_color text,
  vehicle_registration_url text,
  vehicle_insurance_url text,
  vehicle_photo_url text,
  
  -- Contacto de emergencia
  emergency_contact_name text,
  emergency_contact_phone text
);

CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_phone ON public.users(phone);

-- ============================================================================
-- TABLA: client_profiles
-- Perfil extendido para clientes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.client_profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  address text,
  lat double precision,
  lon double precision,
  address_structured jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_client_profiles_user ON public.client_profiles(user_id);

-- ============================================================================
-- TABLA: delivery_agent_profiles
-- Perfil extendido para repartidores
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.delivery_agent_profiles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status text DEFAULT 'offline' CHECK (status IN ('offline', 'online', 'busy')),
  account_state text DEFAULT 'pending' CHECK (account_state IN ('pending', 'approved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_profiles_user ON public.delivery_agent_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_delivery_profiles_status ON public.delivery_agent_profiles(status);
CREATE INDEX IF NOT EXISTS idx_delivery_profiles_account_state ON public.delivery_agent_profiles(account_state);

-- ============================================================================
-- TABLA: restaurants
-- Información de restaurantes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.restaurants (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  logo_url text,
  cover_image_url text,
  menu_image_url text,
  facade_image_url text,
  business_permit_url text,
  health_permit_url text,
  
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  online boolean DEFAULT false,
  
  -- Dirección y ubicación
  address text,
  location_lat double precision,
  location_lon double precision,
  location_place_id text,
  address_structured jsonb,
  phone text,
  
  -- Configuración de negocio
  cuisine_type text,
  business_hours jsonb,
  delivery_radius_km double precision DEFAULT 5.0,
  min_order_amount double precision DEFAULT 0.0,
  estimated_delivery_time_minutes integer DEFAULT 30,
  
  -- Onboarding
  onboarding_completed boolean DEFAULT false,
  onboarding_step integer DEFAULT 0,
  profile_completion_percentage integer DEFAULT 0,
  
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_restaurants_user ON public.restaurants(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_status ON public.restaurants(status);
CREATE INDEX IF NOT EXISTS idx_restaurants_online ON public.restaurants(online);

-- ============================================================================
-- TABLA: products
-- Productos disponibles en restaurantes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.products (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  price double precision NOT NULL CHECK (price >= 0),
  image_url text,
  is_available boolean DEFAULT true,
  type text DEFAULT 'principal' CHECK (type IN ('principal', 'bebida', 'postre', 'entrada', 'combo')),
  contains jsonb, -- Para combos: array de {product_id, quantity}
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_products_restaurant ON public.products(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_products_available ON public.products(is_available);
CREATE INDEX IF NOT EXISTS idx_products_type ON public.products(type);

-- ============================================================================
-- TABLA: product_combos
-- Definición de combos (alternativa a usar jsonb en products.contains)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.product_combos (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id uuid UNIQUE NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_combos_product ON public.product_combos(product_id);
CREATE INDEX IF NOT EXISTS idx_product_combos_restaurant ON public.product_combos(restaurant_id);

-- ============================================================================
-- TABLA: product_combo_items
-- Items individuales dentro de un combo
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.product_combo_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  combo_id uuid NOT NULL REFERENCES public.product_combos(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_combo_items_combo ON public.product_combo_items(combo_id);
CREATE INDEX IF NOT EXISTS idx_combo_items_product ON public.product_combo_items(product_id);

-- ============================================================================
-- TABLA: orders
-- Órdenes de compra
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.orders (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id uuid REFERENCES public.restaurants(id) ON DELETE SET NULL,
  delivery_agent_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  
  status text NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 
    'assigned', 'on_the_way', 'delivered', 'canceled'
  )),
  
  total_amount double precision NOT NULL CHECK (total_amount >= 0),
  delivery_fee double precision DEFAULT 0.0,
  payment_method text CHECK (payment_method IN ('card', 'cash')),
  
  -- Dirección de entrega
  delivery_address text,
  delivery_latlng text,
  delivery_lat double precision,
  delivery_lon double precision,
  
  -- Códigos de confirmación
  confirm_code text, -- 3 dígitos para confirmar entrega
  pickup_code text,  -- 4 dígitos para recoger en restaurante
  
  -- Notas y tiempos
  order_notes text,
  assigned_at timestamptz,
  pickup_time timestamptz,
  delivery_time timestamptz,
  
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orders_user ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant ON public.orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_delivery_agent ON public.orders(delivery_agent_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);

-- ============================================================================
-- TABLA: order_items
-- Items individuales dentro de una orden
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_items (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  quantity integer NOT NULL CHECK (quantity > 0),
  price_at_time_of_order double precision NOT NULL CHECK (price_at_time_of_order >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order ON public.order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product ON public.order_items(product_id);

-- ============================================================================
-- TABLA: order_status_updates
-- Historial de cambios de estado de órdenes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.order_status_updates (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status text NOT NULL,
  updated_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_status_updates_order ON public.order_status_updates(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_updates_created_at ON public.order_status_updates(created_at DESC);

-- ============================================================================
-- TABLA: payments
-- Registro de pagos
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  stripe_payment_id text,
  amount double precision NOT NULL CHECK (amount >= 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'succeeded', 'failed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payments_order ON public.payments(order_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments(status);

-- ============================================================================
-- TABLA: accounts
-- Cuentas financieras para restaurantes y repartidores
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.accounts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  account_type text NOT NULL CHECK (account_type IN ('client', 'restaurant', 'delivery_agent', 'admin')),
  balance numeric(10,2) NOT NULL DEFAULT 0.00,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_accounts_user ON public.accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_accounts_type ON public.accounts(account_type);

-- ============================================================================
-- TABLA: account_transactions
-- Transacciones financieras
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.account_transactions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN (
    'ORDER_REVENUE', 'PLATFORM_COMMISSION', 'DELIVERY_EARNING', 
    'CASH_COLLECTED', 'SETTLEMENT_PAYMENT', 'SETTLEMENT_RECEPTION'
  )),
  amount numeric(10,2) NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  settlement_id uuid,
  description text,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_account_transactions_account ON public.account_transactions(account_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_order ON public.account_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_account_transactions_type ON public.account_transactions(type);
CREATE INDEX IF NOT EXISTS idx_account_transactions_created_at ON public.account_transactions(created_at DESC);

-- ============================================================================
-- TABLA: settlements
-- Liquidaciones de efectivo entre repartidores y restaurantes
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.settlements (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  payer_account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  receiver_account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  amount numeric(10,2) NOT NULL CHECK (amount > 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'cancelled')),
  confirmation_code text NOT NULL,
  initiated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  completed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  notes text
);

CREATE INDEX IF NOT EXISTS idx_settlements_payer ON public.settlements(payer_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_receiver ON public.settlements(receiver_account_id);
CREATE INDEX IF NOT EXISTS idx_settlements_status ON public.settlements(status);
CREATE INDEX IF NOT EXISTS idx_settlements_confirmation_code ON public.settlements(confirmation_code);

-- ============================================================================
-- TABLA: courier_locations_latest
-- Ubicación actual de repartidores
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.courier_locations_latest (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision,
  speed double precision,
  heading double precision,
  source text,
  last_seen_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_courier_latest_order ON public.courier_locations_latest(order_id);

-- ============================================================================
-- TABLA: courier_locations_history
-- Historial de ubicaciones de repartidores
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.courier_locations_history (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision,
  speed double precision,
  heading double precision,
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_courier_hist_user_time ON public.courier_locations_history(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_courier_hist_order_time ON public.courier_locations_history(order_id, recorded_at DESC);

-- ============================================================================
-- TABLA: reviews
-- Reseñas de restaurantes y repartidores
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  reviewer_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reviewee_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating integer NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment text,
  review_type text NOT NULL CHECK (review_type IN ('restaurant', 'delivery')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reviews_order ON public.reviews(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewer ON public.reviews(reviewer_id);
CREATE INDEX IF NOT EXISTS idx_reviews_reviewee ON public.reviews(reviewee_id);
CREATE INDEX IF NOT EXISTS idx_reviews_type ON public.reviews(review_type);

-- ============================================================================
-- TABLA: app_logs
-- Logs de aplicación para debugging
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.app_logs (
  id bigserial PRIMARY KEY,
  at timestamptz NOT NULL DEFAULT now(),
  scope text NOT NULL,
  message text NOT NULL,
  data jsonb,
  created_by text DEFAULT current_user
);

CREATE INDEX IF NOT EXISTS idx_app_logs_scope ON public.app_logs(scope);
CREATE INDEX IF NOT EXISTS idx_app_logs_at ON public.app_logs(at DESC);

-- ============================================================================
-- TRIGGERS: updated_at automático
-- ============================================================================

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar trigger a todas las tablas con updated_at
DO $$
DECLARE
  t text;
BEGIN
  FOR t IN 
    SELECT table_name 
    FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND column_name = 'updated_at'
  LOOP
    EXECUTE format('
      DROP TRIGGER IF EXISTS update_%s_updated_at ON public.%I;
      CREATE TRIGGER update_%s_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW
        EXECUTE FUNCTION public.update_updated_at_column();
    ', t, t, t, t);
  END LOOP;
END;
$$ LANGUAGE plpgsql;
