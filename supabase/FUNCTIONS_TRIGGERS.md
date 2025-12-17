-- 1. LISTAR FUNCIONES (RPCs y Helpers)
-- Buscamos funciones en el esquema 'public' que no sean nativas de PostGIS.
[
  {
    "function_name": "_coalesce_text",
    "arguments": "anyelement, text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "_fmt_pct",
    "arguments": "p_rate numeric",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "_format_percentage",
    "arguments": "p_rate numeric",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "_is_active_delivery_status",
    "arguments": "p_status text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "_normalize_role",
    "arguments": "p_role text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "accept_order",
    "arguments": "p_order_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Assigns available order to current delivery agent and marks it as assigned."
  },
  {
    "function_name": "admin_approve_delivery_agent",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Approves a delivery agent by setting account_state=approved and status=offline. Used by admin panel."
  },
  {
    "function_name": "admin_approve_restaurant",
    "arguments": "p_restaurant_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_approve_user",
    "arguments": "p_user_id uuid, p_status text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Approves or rejects a user by updating users.status. Used by admin panel. Requires caller to be admin."
  },
  {
    "function_name": "admin_get_dashboard_metrics",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_get_order_status_counts",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Retorna conteo de pedidos agrupados por estado. Requiere rol admin."
  },
  {
    "function_name": "admin_get_orders_by_day",
    "arguments": "p_days integer DEFAULT 7",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Retorna conteo de pedidos por día para los últimos N días. Requiere rol admin."
  },
  {
    "function_name": "admin_get_restaurant_overview",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_get_revenue_by_day",
    "arguments": "p_days integer DEFAULT 7",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Retorna suma de ingresos por día para los últimos N días. Requiere rol admin."
  },
  {
    "function_name": "admin_list_clients",
    "arguments": "p_status text DEFAULT 'all'::text, p_query text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Lista clientes (client_profiles + users) con filtros por estado y búsqueda. SECURITY DEFINER para superar RLS."
  },
  {
    "function_name": "admin_list_pending_restaurants",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_set_commission_bps",
    "arguments": "p_restaurant_id uuid, p_commission_bps integer",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_toggle_restaurant_online",
    "arguments": "p_restaurant_id uuid, p_online boolean",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_update_delivery_agent_status",
    "arguments": "p_user_id uuid, p_status text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "admin_update_delivery_agent_status",
    "arguments": "p_user_id uuid, p_status delivery_agent_status",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "assign_pickup_code",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": "Asigna automáticamente un pickup_code cuando se crea una nueva orden"
  },
  {
    "function_name": "audit_and_block_delivery_agent_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "audit_delivery_agent_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "auto_generate_order_codes",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "calculate_distance_between_users",
    "arguments": "user_id_1 uuid, user_id_2 uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "calculate_order_transactions",
    "arguments": "order_id_param uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "calculate_restaurant_completion",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": "Calcula el porcentaje de completado del perfil de un restaurante (0-100%)"
  },
  {
    "function_name": "check_client_suspension",
    "arguments": "p_client_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "check_email_availability",
    "arguments": "p_email text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Verifica si un email está disponible (no registrado). Retorna TRUE si está disponible."
  },
  {
    "function_name": "check_phone_availability",
    "arguments": "p_phone text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Verifica si un teléfono está disponible (no registrado). Retorna TRUE si está disponible."
  },
  {
    "function_name": "check_restaurant_name_availability",
    "arguments": "p_name text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "TRUE si el nombre no existe en restaurants."
  },
  {
    "function_name": "check_restaurant_name_available",
    "arguments": "p_name text, p_exclude_id uuid DEFAULT NULL::uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "check_restaurant_name_available_for_update",
    "arguments": "p_name text, p_exclude_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "TRUE si el nombre no existe en restaurants, excluyendo el id dado."
  },
  {
    "function_name": "check_restaurant_phone_availability",
    "arguments": "p_phone text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "TRUE si el teléfono no existe en restaurants (usa formato canónico)."
  },
  {
    "function_name": "check_restaurant_phone_available",
    "arguments": "p_phone text, p_exclude_id uuid DEFAULT NULL::uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "check_restaurant_phone_available_for_update",
    "arguments": "p_phone text, p_exclude_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "TRUE si el teléfono no existe en restaurants, excluyendo el id dado."
  },
  {
    "function_name": "confirm_mercadopago_payment",
    "arguments": "p_payment_id uuid, p_mp_payment_id text, p_mp_preference_id text, p_payment_details jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "create_account_on_approval",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "create_account_on_user_approval",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "create_account_public",
    "arguments": "p_user_id uuid, p_account_type text, p_balance numeric DEFAULT 0.00",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "create_order_safe",
    "arguments": "p_client_id uuid, p_restaurant_id uuid, p_delivery_address text, p_order_notes text DEFAULT NULL::text, p_delivery_fee numeric DEFAULT 0, p_service_fee numeric DEFAULT 0, p_total_amount numeric DEFAULT 0",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "create_order_safe",
    "arguments": "p_user_id uuid, p_restaurant_id uuid, p_delivery_address text, p_total_amount numeric, p_delivery_fee numeric, p_delivery_latitude numeric DEFAULT NULL::numeric, p_delivery_longitude numeric DEFAULT NULL::numeric, p_order_notes text DEFAULT NULL::text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "create_order_safe",
    "arguments": "p_user_id uuid, p_restaurant_id uuid, p_total_amount numeric, p_delivery_address text, p_delivery_fee numeric DEFAULT 35, p_order_notes text DEFAULT ''::text, p_payment_method text DEFAULT 'cash'::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "create_payment_preference",
    "arguments": "p_order_id uuid, p_client_id uuid, p_total_amount numeric, p_client_debt numeric DEFAULT 0",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "create_user_profile_public",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_is_temp_password boolean DEFAULT false",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "delivery_agent_profiles_guard",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "dispute_debt",
    "arguments": "p_debt_id uuid, p_client_id uuid, p_dispute_reason text, p_dispute_photo_url text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "ensure_account",
    "arguments": "p_user_id uuid, p_account_type text, p_status text DEFAULT 'active'::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "ensure_client_profile_and_account",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "ensure_delivery_agent_account",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Crea automáticamente una account tipo delivery_agent para el user_id dado si no existe. Retorna account_id."
  },
  {
    "function_name": "ensure_delivery_agent_role_and_profile",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Crea perfil mínimo de delivery agent cuando se crea una cuenta financiera.\r\nActualiza role en users, crea registro en delivery_agent_profiles y user_preferences.\r\nSafe to call multiple times (idempotent)."
  },
  {
    "function_name": "ensure_financial_account",
    "arguments": "p_user_id uuid, p_account_type text DEFAULT 'delivery_agent'::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "ensure_restaurant_account",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Crea automáticamente una account tipo restaurant para el user_id dado si no existe. Retorna account_id."
  },
  {
    "function_name": "ensure_user_preferences",
    "arguments": "_user_id uuid, _restaurant_id uuid DEFAULT NULL::uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_accounts_recompute_balance",
    "arguments": "p_account_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Recomputes accounts.balance from the sum of account_transactions.amount for the given account_id"
  },
  {
    "function_name": "fn_combo_items_sync_products_contains",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_get_restaurant_account_id",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_get_restaurant_owner_account_id",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_get_restaurant_owner_user_id",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_notify_admin_on_new_client",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_notify_admin_on_new_delivery_agent",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_notify_admin_on_new_restaurant",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_on_account_transactions_change",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_orders_after_delivered",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_orders_set_owner_on_write",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_platform_account_id",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_product_combos_touch_updated_at",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_products_sync_combo_meta",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "fn_products_validate_type_contains",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": "Valida products.contains para combos. Respeta flag combo.bypass_validate=on para permitir validación diferida en transacciones atómicas."
  },
  {
    "function_name": "fn_required_min_payment",
    "arguments": "p_account_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "fn_sync_combo_contains",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "[DESHABILITADA] Sincronización automática desactivada para evitar recursión infinita. La RPC upsert_combo_atomic maneja contains directamente."
  },
  {
    "function_name": "fn_validate_combo_deferred",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": "Valida restricciones de combos al final de la transacción: unidades 2-9, sin recursión, contains sincronizado."
  },
  {
    "function_name": "fn_validate_combo_items_and_bounds",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": "[OBSOLETO] Validación síncrona. Reemplazada por fn_validate_combo_deferred (CONSTRAINT TRIGGER DEFERRED)."
  },
  {
    "function_name": "fn_validate_product_combos_type",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "forgive_debt",
    "arguments": "p_debt_id uuid, p_admin_id uuid, p_notes text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "generate_pickup_code",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "generate_random_code",
    "arguments": "code_length integer",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "generate_settlement_confirmation_code",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "get_all_orders_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_all_restaurants_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_all_users_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_client_active_orders",
    "arguments": "client_id_param uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_client_debts",
    "arguments": "p_client_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_client_total_debt",
    "arguments": "p_client_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Retorna el adeudo total pendiente de un cliente (suma de client_debts con status = pending)"
  },
  {
    "function_name": "get_driver_location_for_order",
    "arguments": "p_order_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_order_full_details",
    "arguments": "order_id_param uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_order_with_details",
    "arguments": "order_id_param uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_platform_account_id",
    "arguments": "kind text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "get_restaurant_stats_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_user_formatted_address",
    "arguments": "user_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "get_user_lat",
    "arguments": "user_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "get_user_lon",
    "arguments": "user_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "get_user_profile",
    "arguments": "user_uuid uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "get_user_stats_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "guard_delivery_profile_role",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "handle_delivery_agent_account_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Trigger function que asegura la creación del perfil de delivery agent\r\ncuando se inserta o actualiza una cuenta con account_type = delivery_agent."
  },
  {
    "function_name": "handle_email_confirmation_final",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "handle_new_user_delivery_profile",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "handle_new_user_signup_v2",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "handle_user_signup",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "has_active_couriers",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Returns true if there is at least one delivery agent with status=online and account_state=approved. SECURITY DEFINER to bypass RLS."
  },
  {
    "function_name": "insert_order_items",
    "arguments": "p_order_id uuid, p_items json",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "insert_order_items_v2",
    "arguments": "p_order_id uuid, p_items json",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Versioned RPC to insert order items. Accepts JSON array with product_id/productId, quantity/qty, and price fields (price_at_time_of_order/unit_price/price). Returns JSON."
  },
  {
    "function_name": "insert_user_to_auth",
    "arguments": "email text, password text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "is_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "is_current_user_admin",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "is_delivery_profile_complete",
    "arguments": "user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Valida si el perfil de un repartidor está completo con todos los datos obligatorios"
  },
  {
    "function_name": "is_email_verified",
    "arguments": "p_email text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "is_restaurant_owner",
    "arguments": "p_restaurant_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "is_restaurant_profile_complete",
    "arguments": "restaurant_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Valida si el perfil de un restaurante está completo con todos los datos obligatorios"
  },
  {
    "function_name": "is_user_admin",
    "arguments": "user_uuid uuid DEFAULT auth.uid()",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "log_auth_user_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "log_dap_after_upsert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "lower",
    "arguments": "product_type_enum",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "mark_onboarding_seen",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "mark_order_not_delivered",
    "arguments": "p_order_id uuid, p_delivery_agent_id uuid, p_reason text DEFAULT 'client_no_show'::text, p_delivery_notes text DEFAULT NULL::text, p_photo_url text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "mark_restaurant_welcome_seen",
    "arguments": "_user_id uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "mark_user_login",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "master_handle_signup",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Master signup trigger that creates user profile based on user_role: client, delivery_agent, restaurant, or admin"
  },
  {
    "function_name": "normalize_account_type",
    "arguments": "p_type text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "normalize_user_role",
    "arguments": "p_role text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "pre_signup_check_repartidor",
    "arguments": "p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "pre_signup_validation",
    "arguments": "p_email text, p_phone text DEFAULT NULL::text, p_restaurant_name text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "process_order_completion",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "process_order_delivery_v3",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "process_order_delivery_v4",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "process_order_financial_completion",
    "arguments": "order_uuid uuid",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "process_order_financial_transactions",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "process_order_payment_on_delivery",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "process_settlement_completion",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "products_validate_contains_references",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "record_client_debt",
    "arguments": "p_user_id uuid, p_amount numeric, p_reason text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "register_delivery_agent_atomic",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_phone text, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_vehicle_type text DEFAULT 'motocicleta'::text, p_vehicle_plate text DEFAULT NULL::text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Atomically registers a delivery agent. V3: Strictly adheres to DATABASE_SCHEMA.sql (removes address columns from users table insert)."
  },
  {
    "function_name": "register_delivery_agent_v2",
    "arguments": "p_email text, p_password text, p_phone text, p_full_name text, p_vehicle_type text DEFAULT NULL::text, p_license_plate text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Registers a new delivery agent with role delivery_agent"
  },
  {
    "function_name": "register_restaurant_atomic",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_restaurant_name text, p_phone text, p_address text, p_location_lat double precision, p_location_lon double precision, p_location_place_id text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "register_restaurant_atomic",
    "arguments": "p_user_id uuid, p_restaurant_name text, p_phone text, p_address text, p_location_lat double precision, p_location_lon double precision, p_location_place_id text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "register_restaurant_v2",
    "arguments": "p_email text, p_password text, p_phone text, p_restaurant_name text, p_restaurant_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Registers a new restaurant with role restaurant"
  },
  {
    "function_name": "repair_user_registration_misclassification",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "resend_email_confirmation",
    "arguments": "p_user_email text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Valida si un usuario puede recibir reenvío de email de confirmación. El reenvío real debe hacerse desde cliente con supabase.auth.resend()"
  },
  {
    "function_name": "resolve_dispute",
    "arguments": "p_debt_id uuid, p_admin_id uuid, p_resolution text, p_resolution_notes text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "reverse_order_transactions",
    "arguments": "order_uuid uuid, reason text DEFAULT 'Order cancellation'::text",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "rpc_admin_create_settlement",
    "arguments": "p_payer_account_id uuid, p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text, p_auto_complete boolean DEFAULT true",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_admin_list_accounts",
    "arguments": "p_account_type text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_confirm_settlement",
    "arguments": "p_settlement_id uuid, p_code text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_create_settlement",
    "arguments": "p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_find_nearby_restaurants",
    "arguments": "p_lat double precision, p_lon double precision, p_radius_meters integer DEFAULT 5000, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_search_text text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Power-Search: Encuentra restaurantes en un radio (metros) usando PostGIS. Retorna distancia calculada y ordena por relevancia."
  },
  {
    "function_name": "rpc_get_driver_location_for_order",
    "arguments": "p_order_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_get_my_account_id",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_get_platform_account_id",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_get_restaurant_account_id",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_get_settlement_code",
    "arguments": "p_settlement_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_get_user_location",
    "arguments": "p_user_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_initiate_restaurant_settlement",
    "arguments": "p_amount double precision, p_notes text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_list_restaurants_with_debt_for_delivery",
    "arguments": "p_delivery_account_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_post_client_default",
    "arguments": "p_order_id uuid, p_reason text DEFAULT 'Falla de Cliente'::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_preview_order_financials",
    "arguments": "p_order_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_recompute_account_balance",
    "arguments": "p_account_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_refresh_account_balance",
    "arguments": "p_account_id uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_set_order_delivery_location",
    "arguments": "p_order_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_set_restaurant_location",
    "arguments": "p_restaurant_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "rpc_update_my_location",
    "arguments": "lat double precision, lon double precision, heading double precision DEFAULT NULL::double precision",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "set_delivery_welcome_seen",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "set_updated_at",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "set_user_phone_if_missing",
    "arguments": "p_user_id uuid, p_phone text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "set_user_phone_if_missing_safe",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "set_user_phone_if_missing_v2",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "submit_review",
    "arguments": "p_order_id uuid, p_rating smallint, p_subject_user_id uuid DEFAULT NULL::uuid, p_subject_restaurant_id uuid DEFAULT NULL::uuid, p_comment text DEFAULT ''::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "trg_accounts_normalize_type",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "trg_debug_log_delivery_agent_profiles",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "trg_debug_log_public_users_after_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "trg_handle_delivery_agent_account_creation",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Trigger function que se ejecuta después de INSERT en delivery_agent_profiles para crear account automáticamente"
  },
  {
    "function_name": "trg_handle_restaurant_account_creation",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Trigger function que se ejecuta después de INSERT en restaurants para crear account automáticamente"
  },
  {
    "function_name": "trg_log_public_users_after_insert",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "trg_order_items_compute_totals",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "trg_orders_sync_coords_from_latlng",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "trg_orders_sync_latlng_from_coords",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "trg_set_user_phone_from_metadata",
    "arguments": "",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "trg_users_normalize_role",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "update_client_debts_updated_at",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "update_client_default_address",
    "arguments": "p_user_id uuid, p_address text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Updates client_profiles for the given user with default delivery address and coordinates. Returns {success, user_id} or {success: false, error}"
  },
  {
    "function_name": "update_my_delivery_profile",
    "arguments": "p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_my_delivery_profile",
    "arguments": "p jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_my_delivery_profile",
    "arguments": "p_profile_image_url text, p_vehicle_type text, p_vehicle_plate text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_my_location",
    "arguments": "p_lat double precision, p_lng double precision",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_my_phone_if_unique",
    "arguments": "p_phone text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_order_with_tracking",
    "arguments": "order_uuid uuid, new_status text, updated_by_uuid uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_restaurant_completion_on_product_change",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "update_restaurant_completion_trigger",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "update_updated_at_column",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "update_user_location",
    "arguments": "p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "update_user_preferences_updated_at",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "upsert_combo_atomic",
    "arguments": "product jsonb, items jsonb, product_id uuid DEFAULT NULL::uuid",
    "security_type": "Security Definer (Bypass RLS)",
    "description": "Upserta combos de forma atómica. Calcula contains desde items, valida 2-9, evita combos anidados. Inserta product_combo_items sin updated_at."
  },
  {
    "function_name": "upsert_delivery_agent_profile",
    "arguments": "p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "validate_email",
    "arguments": "p_email text, p_user_type text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "validate_name",
    "arguments": "p_name text, p_user_type text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "validate_payment_amount",
    "arguments": "",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  },
  {
    "function_name": "validate_phone",
    "arguments": "p_phone text, p_user_type text",
    "security_type": "Security Definer (Bypass RLS)",
    "description": null
  },
  {
    "function_name": "validate_products_contains_shape",
    "arguments": "_contains jsonb",
    "security_type": "Invoker (Respeta RLS)",
    "description": null
  }
]


-- 2. LISTAR TRIGGERS ACTIVOS
-- Muestra qué disparadores se ejecutan y en qué tablas.
[
  {
    "table_name": "account_transactions",
    "trigger_name": "trg_account_transactions_balance_maintain",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_on_account_transactions_change()"
  },
  {
    "table_name": "account_transactions",
    "trigger_name": "trg_account_transactions_balance_maintain",
    "event": "DELETE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_on_account_transactions_change()"
  },
  {
    "table_name": "account_transactions",
    "trigger_name": "trg_account_transactions_balance_maintain",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_on_account_transactions_change()"
  },
  {
    "table_name": "accounts",
    "trigger_name": "trg_accounts_normalize_type",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_accounts_normalize_type()"
  },
  {
    "table_name": "accounts",
    "trigger_name": "trg_accounts_normalize_type",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_accounts_normalize_type()"
  },
  {
    "table_name": "accounts",
    "trigger_name": "trg_handle_delivery_agent_account_insert",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION handle_delivery_agent_account_insert()"
  },
  {
    "table_name": "accounts",
    "trigger_name": "trg_handle_delivery_agent_account_update",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION handle_delivery_agent_account_insert()"
  },
  {
    "table_name": "client_account_suspensions",
    "trigger_name": "trigger_suspensions_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_client_debts_updated_at()"
  },
  {
    "table_name": "client_debts",
    "trigger_name": "trigger_client_debts_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_client_debts_updated_at()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "ai_debug_log_delivery_agent_profiles",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION trg_debug_log_delivery_agent_profiles()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "delivery_agent_profiles_guard_bi",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION delivery_agent_profiles_guard()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_after_upsert_set_phone",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION trg_set_user_phone_from_metadata()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_after_upsert_set_phone",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION trg_set_user_phone_from_metadata()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_audit_delivery_agent_insert",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION audit_delivery_agent_insert()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_create_delivery_agent_account",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION trg_handle_delivery_agent_account_creation()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_guard_delivery_profile_role",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION guard_delivery_profile_role()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_guard_delivery_profile_role",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION guard_delivery_profile_role()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_log_dap_after_upsert",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION log_dap_after_upsert()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_log_dap_after_upsert",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION log_dap_after_upsert()"
  },
  {
    "table_name": "delivery_agent_profiles",
    "trigger_name": "trg_notify_admin_new_delivery_agent",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_notify_admin_on_new_delivery_agent()"
  },
  {
    "table_name": "order_items",
    "trigger_name": "trg_order_items_compute_totals",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_order_items_compute_totals()"
  },
  {
    "table_name": "order_items",
    "trigger_name": "trg_order_items_compute_totals",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_order_items_compute_totals()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_on_order_delivered_process_v4",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION process_order_delivery_v4()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_set_owner_on_write",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_orders_set_owner_on_write()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_set_owner_on_write",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_orders_set_owner_on_write()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_sync_coords_from_latlng",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_orders_sync_coords_from_latlng()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_sync_coords_from_latlng",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_orders_sync_coords_from_latlng()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_sync_latlng_from_coords",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_orders_sync_latlng_from_coords()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trg_orders_sync_latlng_from_coords",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION trg_orders_sync_latlng_from_coords()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trigger_auto_generate_order_codes",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION auto_generate_order_codes()"
  },
  {
    "table_name": "orders",
    "trigger_name": "trigger_process_order_financial_transactions",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION process_order_financial_transactions()"
  },
  {
    "table_name": "payments",
    "trigger_name": "validate_payment_amount_trigger",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION validate_payment_amount()"
  },
  {
    "table_name": "payments",
    "trigger_name": "validate_payment_amount_trigger",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION validate_payment_amount()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_combo_items_sync_products_d",
    "event": "DELETE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_combo_items_sync_products_contains()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_combo_items_sync_products_i",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_combo_items_sync_products_contains()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_combo_items_sync_products_u",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_combo_items_sync_products_contains()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_validate_combo_deferred",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_validate_combo_deferred()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_validate_combo_deferred",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_validate_combo_deferred()"
  },
  {
    "table_name": "product_combo_items",
    "trigger_name": "trg_validate_combo_deferred",
    "event": "DELETE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_validate_combo_deferred()"
  },
  {
    "table_name": "product_combos",
    "trigger_name": "trg_product_combos_touch",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_product_combos_touch_updated_at()"
  },
  {
    "table_name": "product_combos",
    "trigger_name": "trg_validate_product_combos_type",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_validate_product_combos_type()"
  },
  {
    "table_name": "product_combos",
    "trigger_name": "trg_validate_product_combos_type",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_validate_product_combos_type()"
  },
  {
    "table_name": "products",
    "trigger_name": "products_updated_at_trigger",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_updated_at_column()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_sync_combo_meta",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_products_sync_combo_meta()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_sync_combo_meta",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_products_sync_combo_meta()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_validate_contains",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION products_validate_contains_references()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_validate_contains",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION products_validate_contains_references()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_validate_type_contains",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_products_validate_type_contains()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_products_validate_type_contains",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION fn_products_validate_type_contains()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_update_restaurant_on_product",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION update_restaurant_completion_on_product_change()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_update_restaurant_on_product",
    "event": "DELETE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION update_restaurant_completion_on_product_change()"
  },
  {
    "table_name": "products",
    "trigger_name": "trg_update_restaurant_on_product",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION update_restaurant_completion_on_product_change()"
  },
  {
    "table_name": "products",
    "trigger_name": "update_products_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_updated_at_column()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "restaurants_updated_at_trigger",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_updated_at_column()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "trg_create_restaurant_account",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION trg_handle_restaurant_account_creation()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "trg_notify_admin_new_restaurant",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION fn_notify_admin_on_new_restaurant()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "trg_update_restaurant_completion",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_restaurant_completion_trigger()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "trg_update_restaurant_completion",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_restaurant_completion_trigger()"
  },
  {
    "table_name": "restaurants",
    "trigger_name": "update_restaurants_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_updated_at_column()"
  },
  {
    "table_name": "settlements",
    "trigger_name": "trigger_generate_settlement_confirmation_code",
    "event": "INSERT",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION generate_settlement_confirmation_code()"
  },
  {
    "table_name": "settlements",
    "trigger_name": "trigger_process_settlement_completion",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION process_settlement_completion()"
  },
  {
    "table_name": "user_preferences",
    "trigger_name": "trg_user_prefs_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION set_updated_at()"
  },
  {
    "table_name": "user_preferences",
    "trigger_name": "trigger_update_user_preferences_updated_at",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_user_preferences_updated_at()"
  },
  {
    "table_name": "users",
    "trigger_name": "users_updated_at_trigger",
    "event": "UPDATE",
    "timing": "BEFORE",
    "function_call": "EXECUTE FUNCTION update_updated_at_column()"
  }
]


-- 3. LISTAR POLÍTICAS RLS (Row Level Security)
-- Fundamental para saber quién puede ver qué.
[
  {
    "tablename": "account_transactions",
    "policyname": "Admins can view all transactions",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "account_transactions",
    "policyname": "System can create transactions",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "true"
  },
  {
    "tablename": "account_transactions",
    "policyname": "System can insert transactions",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['admin'::text, 'platform'::text])))))"
  },
  {
    "tablename": "account_transactions",
    "policyname": "Users can view own account transactions",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM accounts\n  WHERE ((accounts.id = account_transactions.account_id) AND (accounts.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "account_transactions",
    "policyname": "Users can view own transactions",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM accounts\n  WHERE ((accounts.id = account_transactions.account_id) AND (accounts.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "account_transactions",
    "policyname": "p_transactions_select_own",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM accounts a\n  WHERE ((a.id = account_transactions.account_id) AND (a.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "accounts",
    "policyname": "accounts_insert_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "accounts",
    "policyname": "accounts_select_admin",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "is_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "accounts",
    "policyname": "accounts_select_own",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "accounts",
    "policyname": "accounts_update_admin",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "is_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "accounts",
    "policyname": "accounts_update_own",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "admin_notifications",
    "policyname": "Admins can read notifications",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "is_current_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "admin_notifications",
    "policyname": "Admins can update is_read",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "is_current_user_admin()",
    "definition_check": "is_current_user_admin()"
  },
  {
    "tablename": "client_account_suspensions",
    "policyname": "suspensions_admin_all",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "client_account_suspensions",
    "policyname": "suspensions_select_own",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((client_id = auth.uid()) OR (EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text)))))",
    "definition_check": null
  },
  {
    "tablename": "client_debts",
    "policyname": "client_debts_admin_all",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "client_debts",
    "policyname": "client_debts_select_own",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((client_id = auth.uid()) OR (EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text)))))",
    "definition_check": null
  },
  {
    "tablename": "client_debts_transactions",
    "policyname": "debt_transactions_select",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((client_id = auth.uid()) OR (EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text)))))",
    "definition_check": null
  },
  {
    "tablename": "client_profiles",
    "policyname": "client_profiles_insert_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "client_profiles",
    "policyname": "client_profiles_select_admin",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "is_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "client_profiles",
    "policyname": "client_profiles_select_own",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "client_profiles",
    "policyname": "client_profiles_update_own",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Admins can read all history",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Admins can view all driver location history",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Authorized users can read driver history",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders o\n  WHERE ((o.delivery_agent_id = courier_locations_history.user_id) AND ((o.user_id = auth.uid()) OR (o.restaurant_id IN ( SELECT r.id\n           FROM restaurants r\n          WHERE (r.user_id = auth.uid())))))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Clients can view driver location history for their orders",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders o\n  WHERE ((o.delivery_agent_id = courier_locations_history.user_id) AND (o.user_id = auth.uid()) AND (o.id = courier_locations_history.order_id))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Drivers can insert their own history",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Drivers can insert their own location history",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "Restaurants can view driver location history for their orders",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM (orders o\n     JOIN restaurants r ON ((o.restaurant_id = r.id)))\n  WHERE ((o.delivery_agent_id = courier_locations_history.user_id) AND (r.user_id = auth.uid()) AND (o.id = courier_locations_history.order_id))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_history",
    "policyname": "courier_hist_insert_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Admins can read all locations",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Admins can view all driver locations",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND (u.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Authorized users can read driver location",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders o\n  WHERE ((o.delivery_agent_id = courier_locations_latest.user_id) AND (o.status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'preparing'::text, 'in_preparation'::text, 'ready_for_pickup'::text, 'assigned'::text, 'picked_up'::text, 'on_the_way'::text, 'in_transit'::text])) AND ((o.user_id = auth.uid()) OR (o.restaurant_id IN ( SELECT r.id\n           FROM restaurants r\n          WHERE (r.user_id = auth.uid())))))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Clients can view driver location for their orders",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders o\n  WHERE ((o.delivery_agent_id = courier_locations_latest.user_id) AND (o.user_id = auth.uid()) AND (o.status = ANY (ARRAY['assigned'::text, 'ready_for_pickup'::text, 'picked_up'::text, 'in_transit'::text, 'on_the_way'::text])))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Drivers can update their own location",
    "roles": "{authenticated}",
    "action": "ALL",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Drivers can upsert their own location",
    "roles": "{authenticated}",
    "action": "ALL",
    "definition_using": "(auth.uid() = user_id)",
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "Restaurants can view driver location for their orders",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM (orders o\n     JOIN restaurants r ON ((o.restaurant_id = r.id)))\n  WHERE ((o.delivery_agent_id = courier_locations_latest.user_id) AND (r.user_id = auth.uid()) AND (o.status = ANY (ARRAY['assigned'::text, 'ready_for_pickup'::text, 'picked_up'::text, 'in_transit'::text, 'on_the_way'::text])))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_select_admin",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND (lower(COALESCE(u.role, 'client'::text)) = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_select_client",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders o\n  WHERE ((o.delivery_agent_id = courier_locations_latest.user_id) AND (o.user_id = auth.uid()) AND _is_active_delivery_status(o.status))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_select_restaurant",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM (orders o\n     JOIN restaurants r ON ((r.id = o.restaurant_id)))\n  WHERE ((o.delivery_agent_id = courier_locations_latest.user_id) AND (r.user_id = auth.uid()) AND _is_active_delivery_status(o.status))))",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_select_self",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(auth.uid() = user_id)",
    "definition_check": null
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_update_self",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "(auth.uid() = user_id)",
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "courier_locations_latest",
    "policyname": "courier_latest_write_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "delivery_agent_profiles",
    "policyname": "delivery_agent_profiles_insert_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "delivery_agent_profiles",
    "policyname": "delivery_agent_profiles_select_admin",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "is_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "delivery_agent_profiles",
    "policyname": "delivery_agent_profiles_select_own",
    "roles": "{authenticated}",
    "action": "SELECT",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "delivery_agent_profiles",
    "policyname": "delivery_agent_profiles_update_admin",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "is_user_admin()",
    "definition_check": null
  },
  {
    "tablename": "delivery_agent_profiles",
    "policyname": "delivery_agent_profiles_update_own",
    "roles": "{authenticated}",
    "action": "UPDATE",
    "definition_using": "(user_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "function_logs",
    "policyname": "function_logs_admin_view",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "function_logs",
    "policyname": "function_logs_all",
    "roles": "{authenticated}",
    "action": "ALL",
    "definition_using": "true",
    "definition_check": "true"
  },
  {
    "tablename": "order_items",
    "policyname": "Order items can be created with orders",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(order_id IN ( SELECT orders.id\n   FROM orders\n  WHERE (orders.user_id = auth.uid())))"
  },
  {
    "tablename": "order_items",
    "policyname": "Order items follow order permissions",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(order_id IN ( SELECT orders.id\n   FROM orders\n  WHERE ((orders.user_id = auth.uid()) OR (orders.restaurant_id IN ( SELECT restaurants.id\n           FROM restaurants\n          WHERE (restaurants.user_id = auth.uid()))) OR (( SELECT users.role\n           FROM users\n          WHERE (users.id = auth.uid())) = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "order_items",
    "policyname": "Users can insert order items",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND (orders.user_id = auth.uid()))))"
  },
  {
    "tablename": "order_items",
    "policyname": "Users can view own order items",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND ((orders.user_id = auth.uid()) OR (orders.delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n           FROM restaurants\n          WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid()))))))))",
    "definition_check": null
  },
  {
    "tablename": "order_items",
    "policyname": "order_items_delete",
    "roles": "{public}",
    "action": "DELETE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND (orders.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "order_items",
    "policyname": "order_items_insert",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND (orders.user_id = auth.uid()))))"
  },
  {
    "tablename": "order_items",
    "policyname": "order_items_read",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND ((orders.user_id = auth.uid()) OR (orders.delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n           FROM restaurants\n          WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid()))))))))",
    "definition_check": null
  },
  {
    "tablename": "order_items",
    "policyname": "order_items_update",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_items.order_id) AND (orders.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "order_status_updates",
    "policyname": "Authorized users can insert status updates",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "((updated_by_user_id = auth.uid()) AND (EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_status_updates.order_id) AND ((orders.user_id = auth.uid()) OR (orders.delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n           FROM restaurants\n          WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid())))))))))"
  },
  {
    "tablename": "order_status_updates",
    "policyname": "Users can view order status updates",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = order_status_updates.order_id) AND ((orders.user_id = auth.uid()) OR (orders.delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n           FROM restaurants\n          WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid()))))))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Admins can update all orders",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Admins can view all orders",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'admin'::text))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Delivery agents can update assigned orders",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(auth.uid() = delivery_agent_id)",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Orders can be created by authenticated users",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  },
  {
    "tablename": "orders",
    "policyname": "Orders can be updated by restaurant or admin",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "((restaurant_id IN ( SELECT restaurants.id\n   FROM restaurants\n  WHERE (restaurants.user_id = auth.uid()))) OR (( SELECT users.role\n   FROM users\n  WHERE (users.id = auth.uid())) = 'admin'::text))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Orders viewable by customer, restaurant or admin",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((user_id = auth.uid()) OR (restaurant_id IN ( SELECT restaurants.id\n   FROM restaurants\n  WHERE (restaurants.user_id = auth.uid()))) OR (( SELECT users.role\n   FROM users\n  WHERE (users.id = auth.uid())) = 'admin'::text))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Restaurant owners can update restaurant orders",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Users can insert orders",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "orders",
    "policyname": "Users can update own orders",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(auth.uid() = user_id)",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "Users can view own orders",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((auth.uid() = user_id) OR (auth.uid() = delivery_agent_id) OR (EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid())))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "orders_insert",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "((auth.uid() = user_id) AND (EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = 'cliente'::text)))))"
  },
  {
    "tablename": "orders",
    "policyname": "orders_read",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((user_id = auth.uid()) OR (delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid())))))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "orders_select_assigned_to_delivery",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(delivery_agent_id = auth.uid())",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "orders_select_available_for_delivery",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((EXISTS ( SELECT 1\n   FROM users u\n  WHERE ((u.id = auth.uid()) AND ((u.role = 'delivery_agent'::text) OR (u.role = 'repartidor'::text))))) AND (EXISTS ( SELECT 1\n   FROM delivery_agent_profiles dap\n  WHERE ((dap.user_id = auth.uid()) AND (dap.account_state = 'approved'::delivery_agent_account_state)))) AND (delivery_agent_id IS NULL) AND (status = ANY (ARRAY['confirmed'::text, 'in_preparation'::text, 'ready_for_pickup'::text])))",
    "definition_check": null
  },
  {
    "tablename": "orders",
    "policyname": "orders_update",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "((user_id = auth.uid()) OR (delivery_agent_id = auth.uid()) OR (EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid())))))",
    "definition_check": null
  },
  {
    "tablename": "payments",
    "policyname": "System can manage payments",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM users\n  WHERE ((users.id = auth.uid()) AND (users.role = ANY (ARRAY['admin'::text, 'platform'::text])))))",
    "definition_check": null
  },
  {
    "tablename": "payments",
    "policyname": "Users can view own payments",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = payments.order_id) AND (orders.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "payments",
    "policyname": "payments_insert",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = payments.order_id) AND (orders.user_id = auth.uid()))))"
  },
  {
    "tablename": "payments",
    "policyname": "payments_read",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = payments.order_id) AND (orders.user_id = auth.uid())))) OR (EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = payments.order_id) AND (EXISTS ( SELECT 1\n           FROM restaurants\n          WHERE ((restaurants.id = orders.restaurant_id) AND (restaurants.user_id = auth.uid()))))))))",
    "definition_check": null
  },
  {
    "tablename": "payments",
    "policyname": "payments_update",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM orders\n  WHERE ((orders.id = payments.order_id) AND (orders.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "product_combo_items",
    "policyname": "product_combo_items_manage_own_restaurant",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM ((product_combos c\n     JOIN products p ON ((p.id = c.product_id)))\n     JOIN restaurants r ON ((r.id = p.restaurant_id)))\n  WHERE ((c.id = product_combo_items.combo_id) AND (r.user_id = auth.uid()))))",
    "definition_check": "(EXISTS ( SELECT 1\n   FROM ((product_combos c\n     JOIN products p ON ((p.id = c.product_id)))\n     JOIN restaurants r ON ((r.id = p.restaurant_id)))\n  WHERE ((c.id = product_combo_items.combo_id) AND (r.user_id = auth.uid()))))"
  },
  {
    "tablename": "product_combo_items",
    "policyname": "product_combo_items_select_all",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "true",
    "definition_check": null
  },
  {
    "tablename": "product_combos",
    "policyname": "product_combos_manage_own_restaurant",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM (products p\n     JOIN restaurants r ON ((r.id = p.restaurant_id)))\n  WHERE ((p.id = product_combos.product_id) AND (r.user_id = auth.uid()))))",
    "definition_check": "(EXISTS ( SELECT 1\n   FROM (products p\n     JOIN restaurants r ON ((r.id = p.restaurant_id)))\n  WHERE ((p.id = product_combos.product_id) AND (r.user_id = auth.uid()))))"
  },
  {
    "tablename": "product_combos",
    "policyname": "product_combos_select_all",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "true",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Anyone can view available products",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((is_available = true) OR (EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid())))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Products are publicly readable",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "true",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Products can be managed by restaurant owners",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(restaurant_id IN ( SELECT restaurants.id\n   FROM restaurants\n  WHERE (restaurants.user_id = auth.uid())))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Public products view",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "true",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Restaurant owners can delete products",
    "roles": "{public}",
    "action": "DELETE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Restaurant owners can insert products",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))"
  },
  {
    "tablename": "products",
    "policyname": "Restaurant owners can update products",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "Restaurant owners manage products",
    "roles": "{public}",
    "action": "ALL",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "products_delete",
    "roles": "{public}",
    "action": "DELETE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "products_insert",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))"
  },
  {
    "tablename": "products",
    "policyname": "products_read",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "((EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.status = 'approved'::text)))) OR (EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid())))))",
    "definition_check": null
  },
  {
    "tablename": "products",
    "policyname": "products_update",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(EXISTS ( SELECT 1\n   FROM restaurants\n  WHERE ((restaurants.id = products.restaurant_id) AND (restaurants.user_id = auth.uid()))))",
    "definition_check": null
  },
  {
    "tablename": "restaurants",
    "policyname": "Public restaurants are viewable by everyone",
    "roles": "{public}",
    "action": "SELECT",
    "definition_using": "true",
    "definition_check": null
  },
  {
    "tablename": "restaurants",
    "policyname": "Users can insert own restaurant",
    "roles": "{public}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(auth.uid() = user_id)"
  },
  {
    "tablename": "restaurants",
    "policyname": "Users can update own restaurant",
    "roles": "{public}",
    "action": "UPDATE",
    "definition_using": "(auth.uid() = user_id)",
    "definition_check": null
  },
  {
    "tablename": "restaurants",
    "policyname": "restaurants_insert_self",
    "roles": "{authenticated}",
    "action": "INSERT",
    "definition_using": null,
    "definition_check": "(user_id = auth.uid())"
  }
]