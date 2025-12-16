-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public._backup_obsolete_functions (
  id bigint NOT NULL DEFAULT nextval('_backup_obsolete_functions_id_seq'::regclass),
  function_schema text NOT NULL,
  function_name text NOT NULL,
  function_args text,
  function_source text NOT NULL,
  function_type text,
  reason_obsolete text,
  backed_up_at timestamp with time zone DEFAULT now(),
  CONSTRAINT _backup_obsolete_functions_pkey PRIMARY KEY (id)
);
CREATE TABLE public._debug_events (
  id bigint NOT NULL DEFAULT nextval('_debug_events_id_seq'::regclass),
  ts timestamp with time zone DEFAULT now(),
  source text NOT NULL,
  event text NOT NULL,
  data jsonb,
  CONSTRAINT _debug_events_pkey PRIMARY KEY (id)
);
CREATE TABLE public.account_transactions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  account_id uuid,
  type text NOT NULL CHECK (type = ANY (ARRAY['ORDER_REVENUE'::text, 'PLATFORM_COMMISSION'::text, 'DELIVERY_EARNING'::text, 'CASH_COLLECTED'::text, 'SETTLEMENT_PAYMENT'::text, 'SETTLEMENT_RECEPTION'::text, 'RESTAURANT_PAYABLE'::text, 'DELIVERY_PAYABLE'::text, 'PLATFORM_DELIVERY_MARGIN'::text, 'PLATFORM_NOT_DELIVERED_REFUND'::text, 'CLIENT_DEBT'::text])),
  amount numeric NOT NULL,
  order_id uuid,
  settlement_id uuid,
  description text,
  metadata jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT account_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT account_transactions_account_id_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id),
  CONSTRAINT account_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT fk_settlement_id FOREIGN KEY (settlement_id) REFERENCES public.settlements(id)
);
CREATE TABLE public.accounts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE,
  account_type text NOT NULL CHECK (account_type = ANY (ARRAY['client'::text, 'restaurant'::text, 'delivery_agent'::text, 'platform'::text, 'platform_revenue'::text, 'platform_payables'::text])),
  balance numeric NOT NULL DEFAULT 0.00,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT accounts_pkey PRIMARY KEY (id),
  CONSTRAINT accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.admin_notifications (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  target_role text NOT NULL DEFAULT 'admin'::text,
  category text NOT NULL CHECK (category = ANY (ARRAY['registration'::text, 'order'::text, 'system'::text])),
  entity_type text NOT NULL CHECK (entity_type = ANY (ARRAY['restaurant'::text, 'delivery_agent'::text, 'user'::text])),
  entity_id uuid,
  title text NOT NULL,
  message text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_read boolean NOT NULL DEFAULT false,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT admin_notifications_pkey PRIMARY KEY (id)
);
CREATE TABLE public.client_account_suspensions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0,
  is_suspended boolean DEFAULT false,
  suspended_at timestamp with time zone,
  suspension_expires_at timestamp with time zone,
  last_failed_order_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT client_account_suspensions_pkey PRIMARY KEY (id),
  CONSTRAINT client_account_suspensions_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id),
  CONSTRAINT client_account_suspensions_last_failed_order_id_fkey FOREIGN KEY (last_failed_order_id) REFERENCES public.orders(id)
);
CREATE TABLE public.client_debts (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  client_id uuid NOT NULL,
  order_id uuid NOT NULL,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  reason text NOT NULL DEFAULT 'not_delivered'::text CHECK (reason = ANY (ARRAY['not_delivered'::text, 'client_no_show'::text, 'fake_address'::text, 'other'::text])),
  status text NOT NULL DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'paid'::text, 'forgiven'::text, 'disputed'::text])),
  photo_url text,
  delivery_notes text,
  dispute_reason text,
  dispute_photo_url text,
  dispute_created_at timestamp with time zone,
  dispute_resolved_at timestamp with time zone,
  dispute_resolved_by uuid,
  dispute_resolution_notes text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  paid_at timestamp with time zone,
  forgiven_at timestamp with time zone,
  forgiven_by uuid,
  metadata jsonb DEFAULT '{}'::jsonb,
  CONSTRAINT client_debts_pkey PRIMARY KEY (id),
  CONSTRAINT client_debts_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id),
  CONSTRAINT client_debts_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT client_debts_dispute_resolved_by_fkey FOREIGN KEY (dispute_resolved_by) REFERENCES public.users(id),
  CONSTRAINT client_debts_forgiven_by_fkey FOREIGN KEY (forgiven_by) REFERENCES public.users(id)
);
CREATE TABLE public.client_debts_transactions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  debt_id uuid NOT NULL,
  client_id uuid NOT NULL,
  amount numeric NOT NULL,
  transaction_type text NOT NULL CHECK (transaction_type = ANY (ARRAY['debt_created'::text, 'payment'::text, 'forgiven'::text, 'dispute_created'::text, 'dispute_resolved'::text])),
  description text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT client_debts_transactions_pkey PRIMARY KEY (id),
  CONSTRAINT client_debts_transactions_debt_id_fkey FOREIGN KEY (debt_id) REFERENCES public.client_debts(id),
  CONSTRAINT client_debts_transactions_client_id_fkey FOREIGN KEY (client_id) REFERENCES public.users(id)
);
CREATE TABLE public.client_profiles (
  user_id uuid NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  address text,
  lat double precision,
  lon double precision,
  address_structured jsonb,
  average_rating numeric DEFAULT 0.00,
  total_reviews integer DEFAULT 0,
  profile_image_url text,
  status text NOT NULL DEFAULT 'active'::text CHECK (status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text])),
  CONSTRAINT client_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT client_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.courier_locations_history (
  id bigint NOT NULL DEFAULT nextval('courier_locations_history_id_seq'::regclass),
  user_id uuid NOT NULL,
  order_id uuid,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision,
  speed double precision,
  heading double precision,
  recorded_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT courier_locations_history_pkey PRIMARY KEY (id),
  CONSTRAINT courier_locations_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT courier_locations_history_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id)
);
CREATE TABLE public.courier_locations_latest (
  user_id uuid NOT NULL,
  order_id uuid,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision,
  speed double precision,
  heading double precision,
  source text,
  last_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT courier_locations_latest_pkey PRIMARY KEY (user_id),
  CONSTRAINT courier_locations_latest_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT courier_locations_latest_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id)
);
CREATE TABLE public.debug_logs (
  id bigint NOT NULL DEFAULT nextval('debug_logs_id_seq'::regclass),
  ts timestamp with time zone DEFAULT now(),
  scope text NOT NULL,
  message text NOT NULL,
  meta jsonb,
  CONSTRAINT debug_logs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.debug_user_signup_log (
  id bigint NOT NULL DEFAULT nextval('debug_user_signup_log_id_seq'::regclass),
  source text,
  event text,
  role text,
  user_id uuid,
  email text,
  details jsonb,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT debug_user_signup_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.delivery_agent_audit_log (
  id bigint NOT NULL DEFAULT nextval('delivery_agent_audit_log_id_seq'::regclass),
  attempt_time timestamp with time zone DEFAULT now(),
  user_id uuid,
  user_role text,
  user_email text,
  db_user text,
  call_stack text,
  is_blocked boolean,
  block_reason text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT delivery_agent_audit_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.delivery_agent_profiles (
  user_id uuid NOT NULL UNIQUE,
  profile_image_url text,
  id_document_front_url text,
  id_document_back_url text,
  vehicle_type text CHECK (vehicle_type = ANY (ARRAY['bicicleta'::text, 'motocicleta'::text, 'auto'::text, 'pie'::text, 'otro'::text])),
  vehicle_plate text,
  vehicle_model text,
  vehicle_color text,
  vehicle_registration_url text,
  vehicle_insurance_url text,
  vehicle_photo_url text,
  emergency_contact_name text,
  emergency_contact_phone text,
  onboarding_completed boolean DEFAULT false,
  onboarding_completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  status USER-DEFINED NOT NULL DEFAULT 'pending'::delivery_agent_status,
  account_state USER-DEFINED DEFAULT 'pending'::delivery_agent_account_state,
  CONSTRAINT delivery_agent_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT delivery_agent_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.delivery_agent_profiles_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  user_role text,
  attempted_at timestamp with time zone DEFAULT now(),
  call_stack text,
  db_user text,
  auth_uid uuid,
  ip_address text,
  CONSTRAINT delivery_agent_profiles_audit_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.function_logs (
  id bigint NOT NULL DEFAULT nextval('function_logs_id_seq'::regclass),
  function_name text NOT NULL,
  message text NOT NULL,
  metadata jsonb,
  level text DEFAULT 'INFO'::text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT function_logs_pkey PRIMARY KEY (id)
);
CREATE TABLE public.order_items (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  order_id uuid,
  product_id uuid,
  quantity integer NOT NULL DEFAULT 1,
  price_at_time_of_order numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  unit_price numeric NOT NULL DEFAULT 0.00,
  CONSTRAINT order_items_pkey PRIMARY KEY (id),
  CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
CREATE TABLE public.order_status_updates (
  id bigint NOT NULL DEFAULT nextval('order_status_updates_id_seq'::regclass),
  order_id uuid NOT NULL,
  status text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  actor_role text,
  actor_id uuid,
  notes text,
  updated_by_user_id uuid,
  CONSTRAINT order_status_updates_pkey PRIMARY KEY (id),
  CONSTRAINT order_status_updates_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT order_status_updates_updated_by_user_id_fkey FOREIGN KEY (updated_by_user_id) REFERENCES public.users(id)
);
CREATE TABLE public.orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  restaurant_id uuid NOT NULL,
  delivery_agent_id uuid,
  status text DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'preparing'::text, 'in_preparation'::text, 'ready_for_pickup'::text, 'assigned'::text, 'picked_up'::text, 'on_the_way'::text, 'in_transit'::text, 'delivered'::text, 'cancelled'::text, 'canceled'::text, 'not_delivered'::text])),
  total_amount numeric NOT NULL,
  payment_method text CHECK (payment_method = ANY (ARRAY['card'::text, 'cash'::text])),
  delivery_address text NOT NULL,
  delivery_latlng text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  delivery_time timestamp with time zone,
  pickup_time timestamp with time zone,
  delivery_fee numeric DEFAULT 3.0,
  assigned_at timestamp with time zone,
  cancellation_reason text,
  confirm_code character varying,
  order_notes text,
  pickup_code character varying,
  subtotal numeric DEFAULT GREATEST((COALESCE(total_amount, (0)::numeric) - COALESCE(delivery_fee, (0)::numeric)), (0)::numeric),
  restaurant_account_id uuid,
  delivery_lat double precision CHECK (delivery_lat IS NULL OR delivery_lat >= '-90'::integer::double precision AND delivery_lat <= 90::double precision),
  delivery_lon double precision CHECK (delivery_lon IS NULL OR delivery_lon >= '-180'::integer::double precision AND delivery_lon <= 180::double precision),
  delivery_place_id text,
  delivery_address_structured jsonb,
  payment_status text DEFAULT 'pending'::text CHECK (payment_status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text, 'refunded'::text])),
  CONSTRAINT orders_pkey PRIMARY KEY (id),
  CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT orders_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id),
  CONSTRAINT orders_delivery_agent_id_fkey FOREIGN KEY (delivery_agent_id) REFERENCES public.users(id),
  CONSTRAINT orders_restaurant_account_id_fkey FOREIGN KEY (restaurant_account_id) REFERENCES public.users(id)
);
CREATE TABLE public.payments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  order_id uuid,
  payment_provider_id text,
  amount numeric NOT NULL,
  status text CHECK (status = ANY (ARRAY['pending'::text, 'succeeded'::text, 'failed'::text, 'completed'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  provider text DEFAULT 'mercadopago'::text CHECK (provider = ANY (ARRAY['stripe'::text, 'mercadopago'::text])),
  mp_payment_id text,
  mp_preference_id text,
  client_debt_amount numeric DEFAULT 0.00,
  payment_details jsonb,
  paid_at timestamp with time zone,
  updated_at timestamp with time zone DEFAULT now(),
  mp_init_point text,
  payment_method text DEFAULT 'cash'::text CHECK (payment_method = ANY (ARRAY['cash'::text, 'card'::text])),
  order_data jsonb,
  CONSTRAINT payments_pkey PRIMARY KEY (id),
  CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id)
);
CREATE TABLE public.product_combo_items (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  combo_id uuid NOT NULL,
  product_id uuid NOT NULL,
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity >= 1),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_combo_items_pkey PRIMARY KEY (id),
  CONSTRAINT product_combo_items_combo_id_fkey FOREIGN KEY (combo_id) REFERENCES public.product_combos(id),
  CONSTRAINT product_combo_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id)
);
CREATE TABLE public.product_combos (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  product_id uuid NOT NULL,
  restaurant_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT product_combos_pkey PRIMARY KEY (id),
  CONSTRAINT product_combos_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT product_combos_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE TABLE public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL,
  name text NOT NULL,
  description text,
  price numeric NOT NULL,
  image_url text,
  is_available boolean DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  type USER-DEFINED NOT NULL DEFAULT 'principal'::product_type_enum,
  contains jsonb,
  CONSTRAINT products_pkey PRIMARY KEY (id),
  CONSTRAINT products_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE TABLE public.restaurants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE,
  name text NOT NULL UNIQUE,
  description text,
  logo_url text,
  status text DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  address text,
  phone text,
  online boolean DEFAULT false,
  average_rating numeric DEFAULT 0.00,
  total_reviews integer DEFAULT 0,
  location_lat double precision CHECK (location_lat IS NULL OR location_lat >= '-90'::integer::double precision AND location_lat <= 90::double precision),
  location_lon double precision CHECK (location_lon IS NULL OR location_lon >= '-180'::integer::double precision AND location_lon <= 180::double precision),
  location_place_id text,
  address_structured jsonb,
  cover_image_url text,
  menu_image_url text,
  business_permit_url text,
  health_permit_url text,
  cuisine_type text,
  business_hours jsonb,
  delivery_radius_km numeric DEFAULT 5.0,
  min_order_amount numeric DEFAULT 0.0,
  estimated_delivery_time_minutes integer DEFAULT 30,
  onboarding_completed boolean DEFAULT false,
  onboarding_step integer DEFAULT 0,
  profile_completion_percentage integer DEFAULT 0,
  commission_bps integer NOT NULL DEFAULT 1500 CHECK (commission_bps >= 0 AND commission_bps <= 3000),
  facade_image_url text,
  CONSTRAINT restaurants_pkey PRIMARY KEY (id),
  CONSTRAINT restaurants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id)
);
CREATE TABLE public.reviews (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  order_id uuid NOT NULL,
  author_id uuid NOT NULL,
  author_role text NOT NULL CHECK (author_role = ANY (ARRAY['cliente'::text, 'restaurante'::text, 'repartidor'::text])),
  subject_user_id uuid,
  subject_restaurant_id uuid,
  rating smallint NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT reviews_pkey PRIMARY KEY (id),
  CONSTRAINT reviews_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id),
  CONSTRAINT reviews_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id),
  CONSTRAINT reviews_subject_user_id_fkey FOREIGN KEY (subject_user_id) REFERENCES public.users(id),
  CONSTRAINT reviews_subject_restaurant_id_fkey FOREIGN KEY (subject_restaurant_id) REFERENCES public.restaurants(id)
);
CREATE TABLE public.settlements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  payer_account_id uuid,
  receiver_account_id uuid,
  amount numeric NOT NULL CHECK (amount > 0::numeric),
  status text DEFAULT 'pending'::text CHECK (status = ANY (ARRAY['pending'::text, 'completed'::text, 'cancelled'::text])),
  confirmation_code text NOT NULL,
  initiated_at timestamp with time zone DEFAULT now(),
  completed_at timestamp with time zone,
  completed_by uuid,
  notes text,
  code_hash text,
  initiated_by uuid,
  CONSTRAINT settlements_pkey PRIMARY KEY (id),
  CONSTRAINT settlements_payer_account_id_fkey FOREIGN KEY (payer_account_id) REFERENCES public.accounts(id),
  CONSTRAINT settlements_receiver_account_id_fkey FOREIGN KEY (receiver_account_id) REFERENCES public.accounts(id),
  CONSTRAINT settlements_completed_by_fkey FOREIGN KEY (completed_by) REFERENCES public.users(id)
);
CREATE TABLE public.system_debug_log (
  id bigint NOT NULL DEFAULT nextval('system_debug_log_id_seq'::regclass),
  ts timestamp with time zone DEFAULT now(),
  tag text,
  data jsonb,
  CONSTRAINT system_debug_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.trigger_debug_log (
  id bigint NOT NULL DEFAULT nextval('trigger_debug_log_id_seq'::regclass),
  ts timestamp with time zone DEFAULT now(),
  function_name text NOT NULL,
  user_id uuid,
  event text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb,
  error_message text,
  stack_trace text,
  CONSTRAINT trigger_debug_log_pkey PRIMARY KEY (id)
);
CREATE TABLE public.user_preferences (
  user_id uuid NOT NULL UNIQUE,
  has_seen_onboarding boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  has_seen_restaurant_welcome boolean NOT NULL DEFAULT false,
  restaurant_welcome_seen_at timestamp with time zone,
  email_verified_congrats_shown boolean NOT NULL DEFAULT false,
  first_login_at timestamp with time zone,
  last_login_at timestamp with time zone,
  login_count integer NOT NULL DEFAULT 0,
  restaurant_id uuid,
  has_seen_delivery_welcome boolean NOT NULL DEFAULT false,
  delivery_welcome_seen_at timestamp with time zone,
  CONSTRAINT user_preferences_pkey PRIMARY KEY (user_id),
  CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id),
  CONSTRAINT user_prefs_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id)
);
CREATE TABLE public.users (
  id uuid NOT NULL,
  email text NOT NULL UNIQUE,
  name text,
  phone text,
  role text DEFAULT 'cliente'::text CHECK (role = ANY (ARRAY['client'::text, 'restaurant'::text, 'delivery_agent'::text, 'admin'::text])),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  email_confirm boolean DEFAULT false,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);