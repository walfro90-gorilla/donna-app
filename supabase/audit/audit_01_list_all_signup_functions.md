[
  {
    "schema_name": "public",
    "function_name": "_is_active_delivery_status",
    "function_source": "CREATE OR REPLACE FUNCTION public._is_active_delivery_status(p_status text)\n RETURNS boolean\n LANGUAGE sql\nAS $function$\r\n  SELECT lower(p_status) IN ('assigned','ready_for_pickup','on_the_way','en_camino');\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_status text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "_should_autocreate_client",
    "function_source": "CREATE OR REPLACE FUNCTION public._should_autocreate_client(p_user_id uuid)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_role_users text;\r\n  v_role_meta  text;\r\n  v_role_final text;\r\nBEGIN\r\n  -- existing role in public.users (if any)\r\n  SELECT _normalize_role(role) INTO v_role_users\r\n  FROM public.users WHERE id = p_user_id;\r\n\r\n  -- role from auth metadata (if accessible)\r\n  BEGIN\r\n    SELECT _normalize_role((raw_user_meta_data->>'role')) INTO v_role_meta\r\n    FROM auth.users WHERE id = p_user_id;\r\n  EXCEPTION WHEN others THEN\r\n    v_role_meta := NULL; -- never fail\r\n  END;\r\n\r\n  v_role_final := coalesce(nullif(v_role_users,''), nullif(v_role_meta,''), 'client');\r\n  RETURN v_role_final = 'client';\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "_trg_call_ensure_client_profile_and_account",
    "function_source": "CREATE OR REPLACE FUNCTION public._trg_call_ensure_client_profile_and_account()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  PERFORM public.ensure_client_profile_and_account(NEW.id);\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "_trg_handle_client_account_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public._trg_handle_client_account_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  PERFORM public.ensure_client_profile_and_account(NEW.user_id);\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "admin_approve_delivery_agent",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_approve_delivery_agent(p_user_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_result jsonb;\r\nBEGIN\r\n  -- Update delivery_agent_profiles\r\n  UPDATE delivery_agent_profiles\r\n  SET \r\n    account_state = 'approved',\r\n    status = 'offline',\r\n    updated_at = NOW()\r\n  WHERE user_id = p_user_id;\r\n\r\n  -- Check if update was successful\r\n  IF NOT FOUND THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'message', 'Delivery agent profile not found'\r\n    );\r\n  END IF;\r\n\r\n  -- Return success with updated data\r\n  SELECT jsonb_build_object(\r\n    'success', true,\r\n    'message', 'Delivery agent approved successfully',\r\n    'account_state', account_state,\r\n    'status', status,\r\n    'updated_at', updated_at\r\n  )\r\n  INTO v_result\r\n  FROM delivery_agent_profiles\r\n  WHERE user_id = p_user_id;\r\n\r\n  RETURN v_result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_approve_restaurant",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_approve_restaurant(p_restaurant_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists boolean;\r\nBEGIN\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only'\r\n      USING ERRCODE = '42501';\r\n  END IF;\r\n\r\n  SELECT TRUE INTO v_exists FROM public.restaurants WHERE id = p_restaurant_id;\r\n  IF NOT FOUND THEN\r\n    RETURN jsonb_build_object('success', false, 'error', 'NOT_FOUND');\r\n  END IF;\r\n\r\n  UPDATE public.restaurants\r\n  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,\r\n      online = CASE WHEN p_approve THEN online ELSE FALSE END,\r\n      updated_at = now()\r\n  WHERE id = p_restaurant_id;\r\n\r\n  RETURN jsonb_build_object('success', true);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_approve_user",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_approve_user(p_user_id uuid, p_status text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_result jsonb;\r\nBEGIN\r\n  -- Validate that the caller is an admin\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' \r\n      USING ERRCODE = '42501';\r\n  END IF;\r\n\r\n  -- Validate status parameter\r\n  IF p_status NOT IN ('approved', 'rejected', 'pending') THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'message', 'Invalid status. Must be approved, rejected, or pending'\r\n    );\r\n  END IF;\r\n\r\n  -- Update users table\r\n  UPDATE users\r\n  SET \r\n    status = p_status,\r\n    updated_at = NOW()\r\n  WHERE id = p_user_id;\r\n\r\n  -- Check if update was successful\r\n  IF NOT FOUND THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'message', 'User not found'\r\n    );\r\n  END IF;\r\n\r\n  -- Return success with updated data\r\n  SELECT jsonb_build_object(\r\n    'success', true,\r\n    'message', 'User status updated successfully',\r\n    'status', status,\r\n    'updated_at', updated_at\r\n  )\r\n  INTO v_result\r\n  FROM users\r\n  WHERE id = p_user_id;\r\n\r\n  RETURN v_result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_status text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_get_dashboard_metrics",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_get_dashboard_metrics()\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_total_users bigint;\r\n  v_total_restaurants bigint;\r\n  v_total_delivery_agents bigint;\r\n  v_pending_restaurants bigint;\r\n  v_total_orders bigint;\r\n  v_orders_today bigint;\r\n  v_platform_revenue numeric;\r\n  v_delivery_earnings numeric;\r\nBEGIN\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' USING ERRCODE = '42501';\r\n  END IF;\r\n\r\n  SELECT COUNT(*) INTO v_total_users FROM public.users;\r\n  SELECT COUNT(*) INTO v_total_restaurants FROM public.restaurants;\r\n  SELECT COUNT(*) INTO v_total_delivery_agents FROM public.users WHERE role = 'delivery_agent';\r\n  SELECT COUNT(*) INTO v_pending_restaurants FROM public.restaurants WHERE status = 'pending';\r\n  SELECT COUNT(*) INTO v_total_orders FROM public.orders;\r\n  SELECT COUNT(*) INTO v_orders_today FROM public.orders WHERE created_at::date = now()::date;\r\n\r\n  SELECT COALESCE(SUM(CASE WHEN type IN ('PLATFORM_COMMISSION','PLATFORM_DELIVERY_MARGIN') THEN amount ELSE 0 END),0)\r\n    INTO v_platform_revenue\r\n  FROM public.account_transactions;\r\n\r\n  SELECT COALESCE(SUM(CASE WHEN type = 'DELIVERY_EARNING' THEN amount ELSE 0 END),0)\r\n    INTO v_delivery_earnings\r\n  FROM public.account_transactions;\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'data', jsonb_build_object(\r\n      'total_users', v_total_users,\r\n      'total_restaurants', v_total_restaurants,\r\n      'total_delivery_agents', v_total_delivery_agents,\r\n      'pending_restaurants', v_pending_restaurants,\r\n      'total_orders', v_total_orders,\r\n      'orders_today', v_orders_today,\r\n      'platform_revenue', v_platform_revenue,\r\n      'delivery_earnings', v_delivery_earnings\r\n    )\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_get_restaurant_overview",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_get_restaurant_overview(p_restaurant_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_orders_count bigint;\r\n  v_revenue numeric;\r\n  v_delivery_fees numeric;\r\n  v_avg_rating numeric;\r\n  v_total_reviews int;\r\n  v_rest jsonb;\r\nBEGIN\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' USING ERRCODE = '42501';\r\n  END IF;\r\n\r\n  SELECT COUNT(*), COALESCE(SUM(o.total_amount),0), COALESCE(SUM(COALESCE(o.delivery_fee,0)),0)\r\n  INTO v_orders_count, v_revenue, v_delivery_fees\r\n  FROM public.orders o\r\n  WHERE o.restaurant_id = p_restaurant_id;\r\n\r\n  SELECT COALESCE(AVG(r.rating)::numeric, 0), COALESCE(COUNT(*), 0)\r\n  INTO v_avg_rating, v_total_reviews\r\n  FROM public.reviews r\r\n  WHERE r.subject_restaurant_id = p_restaurant_id;\r\n\r\n  SELECT to_jsonb(rr) INTO v_rest FROM (\r\n    SELECT id, user_id, name, phone, status, online, commission_bps, created_at, updated_at\r\n    FROM public.restaurants WHERE id = p_restaurant_id\r\n  ) rr;\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'data', jsonb_build_object(\r\n      'restaurant', v_rest,\r\n      'orders_count', v_orders_count,\r\n      'revenue', v_revenue,\r\n      'delivery_fees', v_delivery_fees,\r\n      'avg_rating', v_avg_rating,\r\n      'total_reviews', v_total_reviews\r\n    )\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_list_clients",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_list_clients(p_status text DEFAULT 'all'::text, p_query text DEFAULT NULL::text)\n RETURNS TABLE(id uuid, user_id uuid, email text, name text, phone text, role text, avatar_url text, address text, created_at timestamp with time zone, updated_at timestamp with time zone, email_confirm boolean, lat double precision, lon double precision, address_structured jsonb, status text)\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  RETURN QUERY\r\n    SELECT \r\n      u.id,\r\n      cp.user_id,\r\n      u.email,\r\n      u.name,\r\n      u.phone,\r\n      u.role,\r\n      u.avatar_url,\r\n      u.address,\r\n      COALESCE(u.created_at, cp.created_at) AS created_at,\r\n      GREATEST(COALESCE(u.updated_at, cp.updated_at), COALESCE(cp.updated_at, u.updated_at)) AS updated_at,\r\n      u.email_confirm,\r\n      u.lat,\r\n      u.lon,\r\n      u.address_structured,\r\n      COALESCE(cp.status, u.status)::text AS status\r\n    FROM public.client_profiles cp\r\n    JOIN public.users u ON u.id = cp.user_id\r\n    WHERE \r\n      (\r\n        p_status IS NULL OR p_status = 'all' OR \r\n        LOWER(COALESCE(cp.status, u.status)::text) = LOWER(p_status)\r\n      )\r\n      AND (\r\n        p_query IS NULL OR p_query = '' OR\r\n        LOWER(COALESCE(u.name, '')) LIKE '%' || LOWER(p_query) || '%' OR\r\n        LOWER(COALESCE(u.email, '')) LIKE '%' || LOWER(p_query) || '%' OR\r\n        LOWER(COALESCE(u.phone, '')) LIKE '%' || LOWER(p_query) || '%'\r\n      )\r\n    ORDER BY GREATEST(COALESCE(u.updated_at, cp.updated_at), COALESCE(cp.updated_at, u.updated_at)) DESC;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_status text DEFAULT 'all'::text, p_query text DEFAULT NULL::text",
    "return_type": "TABLE(id uuid, user_id uuid, email text, name text, phone text, role text, avatar_url text, address text, created_at timestamp with time zone, updated_at timestamp with time zone, email_confirm boolean, lat double precision, lon double precision, address_structured jsonb, status text)"
  },
  {
    "schema_name": "public",
    "function_name": "admin_list_pending_restaurants",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_list_pending_restaurants()\n RETURNS SETOF restaurants\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\n  SELECT * FROM public.restaurants r WHERE r.status = 'pending';\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "",
    "return_type": "SETOF restaurants"
  },
  {
    "schema_name": "public",
    "function_name": "admin_set_commission_bps",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_set_commission_bps(p_restaurant_id uuid, p_commission_bps integer)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' USING ERRCODE = '42501';\r\n  END IF;\r\n  IF p_commission_bps < 0 OR p_commission_bps > 3000 THEN\r\n    RETURN jsonb_build_object('success', false, 'error', 'INVALID_RANGE');\r\n  END IF;\r\n  UPDATE public.restaurants\r\n  SET commission_bps = p_commission_bps,\r\n      updated_at = now()\r\n  WHERE id = p_restaurant_id;\r\n  RETURN jsonb_build_object('success', true);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid, p_commission_bps integer",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_toggle_restaurant_online",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_toggle_restaurant_online(p_restaurant_id uuid, p_online boolean)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' USING ERRCODE = '42501';\r\n  END IF;\r\n  UPDATE public.restaurants\r\n  SET online = p_online,\r\n      updated_at = now()\r\n  WHERE id = p_restaurant_id;\r\n  RETURN jsonb_build_object('success', true);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid, p_online boolean",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "admin_update_delivery_agent_status",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_update_delivery_agent_status(p_user_id uuid, p_status text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n  IF p_status = 'approved' THEN\r\n    UPDATE public.delivery_agent_profiles\r\n    SET \r\n      status = 'offline',\r\n      account_state = 'approved',\r\n      updated_at = now()\r\n    WHERE user_id = p_user_id;\r\n  ELSIF p_status IN ('pending', 'rejected', 'suspended') THEN\r\n    UPDATE public.delivery_agent_profiles\r\n    SET \r\n      account_state = 'pending',\r\n      updated_at = now()\r\n    WHERE user_id = p_user_id;\r\n  END IF;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_status text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "admin_update_delivery_agent_status",
    "function_source": "CREATE OR REPLACE FUNCTION public.admin_update_delivery_agent_status(p_user_id uuid, p_status delivery_agent_status)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN IF NOT ( (current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'role') = 'admin' OR (current_setting('request.jwt.claims', true)::jsonb->'app_metadata'->>'is_admin') = 'true' ) THEN RAISE EXCEPTION 'forbidden'; END IF;UPDATE public.delivery_agent_profiles SET status = p_status WHERE user_id = p_user_id;IF NOT FOUND THEN RETURN false; END IF;RETURN true; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_status delivery_agent_status",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "audit_and_block_delivery_agent_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.audit_and_block_delivery_agent_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_user_role TEXT;\r\n  v_user_email TEXT;\r\n  v_should_block BOOLEAN := false;\r\n  v_block_reason TEXT := NULL;\r\nBEGIN\r\n  -- Obtener información del usuario desde public.users\r\n  SELECT role, email INTO v_user_role, v_user_email\r\n  FROM public.users\r\n  WHERE id = NEW.user_id;\r\n\r\n  -- Si no encontramos el usuario, permitir el INSERT (puede ser creación simultánea)\r\n  IF v_user_role IS NULL THEN\r\n    v_user_role := 'USUARIO NO ENCONTRADO';\r\n    v_should_block := false; -- NO bloquear si el usuario aún no existe en public.users\r\n  ELSIF v_user_role != 'repartidor' THEN\r\n    -- Si el rol NO es 'repartidor', bloquear\r\n    v_should_block := true;\r\n    v_block_reason := 'Usuario con rol \"' || v_user_role || '\" no puede tener perfil de repartidor';\r\n  END IF;\r\n\r\n  -- Registrar el intento en la tabla de auditoría\r\n  INSERT INTO public.delivery_agent_audit_log (\r\n    user_id,\r\n    user_role,\r\n    user_email,\r\n    db_user,\r\n    call_stack,\r\n    is_blocked,\r\n    block_reason\r\n  ) VALUES (\r\n    NEW.user_id,\r\n    v_user_role,\r\n    v_user_email,\r\n    current_user::TEXT,\r\n    pg_catalog.current_query()::TEXT,\r\n    v_should_block,\r\n    v_block_reason\r\n  );\r\n\r\n  -- Si debemos bloquear, lanzar excepción\r\n  IF v_should_block THEN\r\n    RAISE EXCEPTION '🚨 AUDIT BLOCK: %', v_block_reason;\r\n  END IF;\r\n\r\n  -- Si no bloqueamos, permitir el INSERT\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "audit_delivery_agent_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.audit_delivery_agent_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_user_role TEXT;\r\n  v_call_stack TEXT;\r\nBEGIN\r\n  -- Obtener el rol del usuario que se intenta insertar\r\n  SELECT role INTO v_user_role\r\n  FROM public.users\r\n  WHERE id = NEW.user_id;\r\n  \r\n  -- Obtener el call stack\r\n  GET DIAGNOSTICS v_call_stack = PG_CONTEXT;\r\n  \r\n  -- Registrar en el log de auditoría\r\n  INSERT INTO delivery_agent_profiles_audit_log (\r\n    user_id,\r\n    user_role,\r\n    call_stack,\r\n    db_user,\r\n    auth_uid,\r\n    ip_address\r\n  ) VALUES (\r\n    NEW.user_id,\r\n    COALESCE(v_user_role, 'ROLE_NOT_FOUND'),\r\n    v_call_stack,\r\n    current_user::TEXT,\r\n    auth.uid(),\r\n    inet_client_addr()::TEXT\r\n  );\r\n  \r\n  -- Si el usuario NO es repartidor, BLOQUEAR la inserción\r\n  IF v_user_role IS NULL OR v_user_role NOT IN ('repartidor', 'delivery_agent') THEN\r\n    RAISE EXCEPTION 'BLOCKED: Cannot create delivery_agent_profile for user with role: %. User ID: %', \r\n      COALESCE(v_user_role, 'NULL'), NEW.user_id;\r\n  END IF;\r\n  \r\n  -- Si es repartidor, permitir la inserción\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "calculate_distance_between_users",
    "function_source": "CREATE OR REPLACE FUNCTION public.calculate_distance_between_users(user_id_1 uuid, user_id_2 uuid)\n RETURNS double precision\n LANGUAGE plpgsql\n STABLE\nAS $function$\r\nDECLARE\r\n  lat1 DOUBLE PRECISION;\r\n  lon1 DOUBLE PRECISION;\r\n  lat2 DOUBLE PRECISION;\r\n  lon2 DOUBLE PRECISION;\r\n  R CONSTANT DOUBLE PRECISION := 6371; -- Earth radius in kilometers\r\n  dLat DOUBLE PRECISION;\r\n  dLon DOUBLE PRECISION;\r\n  a DOUBLE PRECISION;\r\n  c DOUBLE PRECISION;\r\nBEGIN\r\n  -- Get coordinates for user 1\r\n  SELECT (address_structured->>'lat')::double precision, \r\n         (address_structured->>'lon')::double precision\r\n  INTO lat1, lon1\r\n  FROM public.users WHERE id = user_id_1;\r\n\r\n  -- Get coordinates for user 2\r\n  SELECT (address_structured->>'lat')::double precision, \r\n         (address_structured->>'lon')::double precision\r\n  INTO lat2, lon2\r\n  FROM public.users WHERE id = user_id_2;\r\n\r\n  -- Return NULL if any coordinate is missing\r\n  IF lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN\r\n    RETURN NULL;\r\n  END IF;\r\n\r\n  -- Haversine formula\r\n  dLat := radians(lat2 - lat1);\r\n  dLon := radians(lon2 - lon1);\r\n  \r\n  a := sin(dLat/2) * sin(dLat/2) +\r\n       cos(radians(lat1)) * cos(radians(lat2)) *\r\n       sin(dLon/2) * sin(dLon/2);\r\n  \r\n  c := 2 * atan2(sqrt(a), sqrt(1-a));\r\n  \r\n  RETURN R * c; -- Distance in kilometers\r\nEND;\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "user_id_1 uuid, user_id_2 uuid",
    "return_type": "double precision"
  },
  {
    "schema_name": "public",
    "function_name": "calculate_restaurant_completion",
    "function_source": "CREATE OR REPLACE FUNCTION public.calculate_restaurant_completion(p_restaurant_id uuid)\n RETURNS integer\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    completion_score INTEGER := 0;\r\n    total_fields INTEGER := 10;\r\n    restaurant_record RECORD;\r\n    product_count INTEGER;\r\nBEGIN\r\n    -- Obtener datos del restaurante\r\n    SELECT * INTO restaurant_record\r\n    FROM restaurants\r\n    WHERE id = p_restaurant_id;\r\n    \r\n    IF NOT FOUND THEN\r\n        RETURN 0;\r\n    END IF;\r\n    \r\n    -- Campo obligatorio: nombre (10%)\r\n    IF restaurant_record.name IS NOT NULL AND LENGTH(restaurant_record.name) > 0 THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo obligatorio: descripción (10%)\r\n    IF restaurant_record.description IS NOT NULL AND LENGTH(restaurant_record.description) > 0 THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo obligatorio: logo (15%)\r\n    IF restaurant_record.logo_url IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: imagen de portada (10%)\r\n    IF restaurant_record.cover_image_url IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: imagen del menú (10%)\r\n    IF restaurant_record.menu_image_url IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: tipo de cocina (5%)\r\n    IF restaurant_record.cuisine_type IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: horarios (10%)\r\n    IF restaurant_record.business_hours IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: radio de entrega (5%)\r\n    IF restaurant_record.delivery_radius_km IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo recomendado: tiempo estimado (5%)\r\n    IF restaurant_record.estimated_delivery_time_minutes IS NOT NULL THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Campo crítico: al menos 1 producto (20%)\r\n    -- ✅ CORRECCIÓN: Usar p_restaurant_id en lugar de restaurant_id para evitar ambigüedad\r\n    SELECT COUNT(*) INTO product_count\r\n    FROM products\r\n    WHERE restaurant_id = p_restaurant_id AND is_available = true;\r\n    \r\n    IF product_count > 0 THEN\r\n        completion_score := completion_score + 1;\r\n    END IF;\r\n    \r\n    -- Calcular porcentaje\r\n    RETURN (completion_score * 100) / total_fields;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "integer"
  },
  {
    "schema_name": "public",
    "function_name": "check_email_availability",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_email_availability(p_email text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\nBEGIN\r\n  -- Verificar si el email ya existe (case-insensitive)\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.users \r\n    WHERE LOWER(email) = LOWER(TRIM(p_email))\r\n  ) INTO v_exists;\r\n\r\n  -- Retornar TRUE si está disponible (no existe)\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_phone_availability",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_phone_availability(p_phone text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\n  v_clean_phone TEXT;\r\nBEGIN\r\n  -- Limpiar el teléfono (solo números y +)\r\n  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\\d+]', '', 'g');\r\n\r\n  -- Verificar si el teléfono ya existe\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.users \r\n    WHERE phone = v_clean_phone\r\n  ) INTO v_exists;\r\n\r\n  -- Retornar TRUE si está disponible (no existe)\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_phone text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_name_availability",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_name_availability(p_name text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\nBEGIN\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE LOWER(r.name) = LOWER(TRIM(p_name))\r\n  ) INTO v_exists;\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_name text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_name_available",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_name_available(p_name text, p_exclude_id uuid DEFAULT NULL::uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\n  SELECT NOT EXISTS (\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE lower(r.name) = lower(trim(p_name))\r\n      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)\r\n  );\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "p_name text, p_exclude_id uuid DEFAULT NULL::uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_name_available_for_update",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_name_available_for_update(p_name text, p_exclude_id uuid)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\nBEGIN\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE LOWER(r.name) = LOWER(TRIM(p_name))\r\n      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)\r\n  ) INTO v_exists;\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_name text, p_exclude_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_phone_availability",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_phone_availability(p_phone text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\n  v_clean_phone TEXT;\r\nBEGIN\r\n  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\\d+]', '', 'g');\r\n  IF v_clean_phone IS NULL OR v_clean_phone = '' THEN\r\n    RETURN TRUE; -- teléfono opcional, considerar disponible\r\n  END IF;\r\n\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE r.phone = v_clean_phone\r\n  ) INTO v_exists;\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_phone text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_phone_available",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_phone_available(p_phone text, p_exclude_id uuid DEFAULT NULL::uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\n  SELECT NOT EXISTS (\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE r.phone IS NOT NULL\r\n      AND trim(r.phone) = trim(p_phone)\r\n      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)\r\n  );\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "p_phone text, p_exclude_id uuid DEFAULT NULL::uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "check_restaurant_phone_available_for_update",
    "function_source": "CREATE OR REPLACE FUNCTION public.check_restaurant_phone_available_for_update(p_phone text, p_exclude_id uuid)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists BOOLEAN;\r\n  v_clean_phone TEXT;\r\nBEGIN\r\n  v_clean_phone := REGEXP_REPLACE(TRIM(p_phone), '[^\\d+]', '', 'g');\r\n  IF v_clean_phone IS NULL OR v_clean_phone = '' THEN\r\n    RETURN TRUE; -- teléfono opcional\r\n  END IF;\r\n\r\n  SELECT EXISTS(\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE r.phone = v_clean_phone\r\n      AND (p_exclude_id IS NULL OR r.id <> p_exclude_id)\r\n  ) INTO v_exists;\r\n  RETURN NOT v_exists;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_phone text, p_exclude_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "create_account_on_approval",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_account_on_approval()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nBEGIN\r\n  -- Check if user role is restaurant or delivery agent and status changed to approved\r\n  IF NEW.role IN ('restaurante', 'repartidor') AND NEW.status = 'approved' AND \r\n     (OLD.status IS NULL OR OLD.status != 'approved') THEN\r\n    \r\n    -- Create account for this user\r\n    INSERT INTO accounts (user_id, account_type, balance)\r\n    VALUES (\r\n      NEW.id, \r\n      CASE \r\n        WHEN NEW.role = 'restaurante' THEN 'restaurant'\r\n        WHEN NEW.role = 'repartidor' THEN 'delivery_agent'\r\n      END,\r\n      0.00\r\n    )\r\n    ON CONFLICT (user_id) DO NOTHING; -- Avoid duplicate if account already exists\r\n  END IF;\r\n  \r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "create_account_on_user_approval",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_account_on_user_approval()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    mapped_account_type TEXT;\r\nBEGIN\r\n    -- Solo procesar cuando se actualiza status a 'approved'\r\n    IF TG_OP = 'UPDATE' AND \r\n       OLD.status != 'approved' AND \r\n       NEW.status = 'approved' THEN\r\n        \r\n        -- Mapear rol del usuario a tipo de cuenta\r\n        CASE NEW.role\r\n            WHEN 'restaurante' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'restaurant' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'delivery_agent' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            WHEN 'repartidor' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            ELSE\r\n                -- No crear cuenta para admin o cliente\r\n                RETURN NEW;\r\n        END CASE;\r\n        \r\n        -- Verificar si ya existe una cuenta para este usuario\r\n        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = NEW.id) THEN\r\n            -- Crear cuenta con balance inicial 0\r\n            INSERT INTO public.accounts (\r\n                id,\r\n                user_id,\r\n                account_type,\r\n                balance,\r\n                created_at,\r\n                updated_at\r\n            ) VALUES (\r\n                gen_random_uuid(),\r\n                NEW.id,\r\n                mapped_account_type,\r\n                0.0,\r\n                NOW(),\r\n                NOW()\r\n            );\r\n            \r\n            RAISE NOTICE 'Cuenta creada para usuario % con tipo %', NEW.id, mapped_account_type;\r\n        ELSE\r\n            RAISE NOTICE 'Cuenta ya existe para usuario %', NEW.id;\r\n        END IF;\r\n    END IF;\r\n    \r\n    RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "create_account_public",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_account_public(p_user_id uuid, p_account_type text, p_balance numeric DEFAULT 0.00)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_account_id uuid;\r\nBEGIN\r\n  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User ID does not exist in auth.users';\r\n  END IF;\r\n\r\n  -- Upsert by (user_id, account_type)\r\n  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (p_user_id, p_account_type, COALESCE(p_balance,0.0), now(), now())\r\n  ON CONFLICT (user_id, account_type) DO UPDATE\r\n    SET updated_at = EXCLUDED.updated_at\r\n  RETURNING id INTO v_account_id;\r\n\r\n  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('account_id', v_account_id), 'error', NULL);\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_account_type text, p_balance numeric DEFAULT 0.00",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "create_auth_user_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_auth_user_profile()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.users (id, email, role, created_at, updated_at) VALUES (NEW.id, COALESCE(NEW.email, NEW.raw_user_meta_data->>'email'), 'client', now(), now()) ON CONFLICT (id) DO NOTHING;INSERT INTO public.user_preferences (user_id) VALUES (NEW.id) ON CONFLICT (user_id) DO NOTHING;RETURN NEW; EXCEPTION WHEN OTHERS THEN RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "create_delivery_agent",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_delivery_agent(auth_user_id uuid, p_email text, p_name text, p_phone text)\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  v_account_id uuid;\r\nbegin\r\n  -- 1. Crear cuenta\r\n  insert into public.accounts (\r\n    created_at,\r\n    account_type,\r\n    status\r\n  ) values (\r\n    now(),\r\n    'DELIVERY_AGENT',\r\n    'PENDING'\r\n  )\r\n  returning id into v_account_id;\r\n\r\n  -- 2. Crear usuario\r\n  insert into public.users (\r\n    id,\r\n    email,\r\n    phone,\r\n    name,\r\n    account_id,\r\n    role,\r\n    status\r\n  ) values (\r\n    auth_user_id,\r\n    p_email,\r\n    p_phone,\r\n    p_name,\r\n    v_account_id,\r\n    'DELIVERY_AGENT',\r\n    'PENDING'\r\n  );\r\n\r\n  -- 3. Crear perfil de repartidor\r\n  insert into public.delivery_agent_profiles (\r\n    user_id,\r\n    account_id,\r\n    status,\r\n    created_at\r\n  ) values (\r\n    auth_user_id,\r\n    v_account_id,\r\n    'PENDING',\r\n    now()\r\n  );\r\n\r\n  -- 4. Crear preferencias\r\n  insert into public.user_preferences (\r\n    user_id,\r\n    created_at\r\n  ) values (\r\n    auth_user_id,\r\n    now()\r\n  );\r\n\r\n  return json_build_object(\r\n    'success', true,\r\n    'user_id', auth_user_id,\r\n    'account_id', v_account_id\r\n  );\r\n\r\nexception when others then\r\n  return json_build_object(\r\n    'success', false,\r\n    'error', SQLERRM,\r\n    'detail', SQLSTATE\r\n  );\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "auth_user_id uuid, p_email text, p_name text, p_phone text",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "create_order_safe",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_order_safe(p_client_id uuid, p_restaurant_id uuid, p_delivery_address text, p_order_notes text DEFAULT NULL::text, p_delivery_fee numeric DEFAULT 0, p_service_fee numeric DEFAULT 0, p_total_amount numeric DEFAULT 0)\n RETURNS json\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    v_order_id UUID;\r\n    v_confirm_code TEXT;\r\n    v_pickup_code TEXT;\r\n    result JSON;\r\nBEGIN\r\n    -- Generar códigos únicos\r\n    LOOP\r\n        v_confirm_code := generate_random_code(3);\r\n        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE confirm_code = v_confirm_code);\r\n    END LOOP;\r\n    \r\n    LOOP\r\n        v_pickup_code := generate_random_code(4);\r\n        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE pickup_code = v_pickup_code);\r\n    END LOOP;\r\n\r\n    -- Generar ID único para la orden\r\n    v_order_id := gen_random_uuid();\r\n\r\n    -- Insertar la orden con códigos\r\n    INSERT INTO orders (\r\n        id,\r\n        client_id,\r\n        restaurant_id,\r\n        delivery_address,\r\n        order_notes,\r\n        delivery_fee,\r\n        service_fee,\r\n        total_amount,\r\n        status,\r\n        confirm_code,\r\n        pickup_code,\r\n        created_at,\r\n        updated_at\r\n    ) VALUES (\r\n        v_order_id,\r\n        p_client_id,\r\n        p_restaurant_id,\r\n        p_delivery_address,\r\n        p_order_notes,\r\n        p_delivery_fee,\r\n        p_service_fee,\r\n        p_total_amount,\r\n        'pending',\r\n        v_confirm_code,\r\n        v_pickup_code,\r\n        NOW(),\r\n        NOW()\r\n    );\r\n\r\n    -- Construir respuesta JSON\r\n    result := json_build_object(\r\n        'success', true,\r\n        'id', v_order_id,\r\n        'confirm_code', v_confirm_code,\r\n        'pickup_code', v_pickup_code,\r\n        'status', 'pending',\r\n        'message', 'Orden creada exitosamente con códigos generados'\r\n    );\r\n\r\n    RAISE NOTICE 'Orden creada: ID=%, ConfirmCode=%, PickupCode=%', v_order_id, v_confirm_code, v_pickup_code;\r\n\r\n    RETURN result;\r\n    \r\nEXCEPTION\r\n    WHEN OTHERS THEN\r\n        RAISE NOTICE 'Error en create_order_safe: %', SQLERRM;\r\n        RETURN json_build_object(\r\n            'success', false,\r\n            'error', SQLERRM,\r\n            'message', 'Error al crear la orden'\r\n        );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_client_id uuid, p_restaurant_id uuid, p_delivery_address text, p_order_notes text DEFAULT NULL::text, p_delivery_fee numeric DEFAULT 0, p_service_fee numeric DEFAULT 0, p_total_amount numeric DEFAULT 0",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "create_order_safe",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_order_safe(p_user_id uuid, p_restaurant_id uuid, p_total_amount numeric, p_delivery_address text, p_delivery_fee numeric DEFAULT 35, p_order_notes text DEFAULT ''::text, p_payment_method text DEFAULT 'cash'::text)\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n    new_order_id UUID;\r\n    result JSON;\r\nBEGIN\r\n    -- Generar UUID único para la orden\r\n    new_order_id := gen_random_uuid();\r\n    \r\n    -- Insertar orden directamente sin activar triggers\r\n    INSERT INTO orders (\r\n        id,\r\n        user_id,\r\n        restaurant_id,\r\n        status,\r\n        total_amount,\r\n        delivery_fee,\r\n        delivery_address,\r\n        order_notes,\r\n        payment_method,\r\n        created_at\r\n    ) VALUES (\r\n        new_order_id,\r\n        p_user_id,\r\n        p_restaurant_id,\r\n        'pending',\r\n        p_total_amount,\r\n        p_delivery_fee,\r\n        p_delivery_address,\r\n        p_order_notes,\r\n        p_payment_method,\r\n        NOW()\r\n    );\r\n    \r\n    -- Retornar el ID de la orden creada\r\n    result := json_build_object('id', new_order_id::text);\r\n    \r\n    RETURN result;\r\nEXCEPTION\r\n    WHEN OTHERS THEN\r\n        -- Log del error para debugging\r\n        RAISE NOTICE 'Error in create_order_safe: %', SQLERRM;\r\n        RETURN json_build_object('error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_restaurant_id uuid, p_total_amount numeric, p_delivery_address text, p_delivery_fee numeric DEFAULT 35, p_order_notes text DEFAULT ''::text, p_payment_method text DEFAULT 'cash'::text",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "create_order_safe",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_order_safe(p_user_id uuid, p_restaurant_id uuid, p_delivery_address text, p_total_amount numeric, p_delivery_fee numeric, p_delivery_latitude numeric DEFAULT NULL::numeric, p_delivery_longitude numeric DEFAULT NULL::numeric, p_order_notes text DEFAULT NULL::text)\n RETURNS json\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    new_order_id UUID;\r\n    confirm_code_generated VARCHAR(3);\r\n    pickup_code_generated VARCHAR(4);\r\n    result JSON;\r\nBEGIN\r\n    -- Generar códigos aleatorios únicos\r\n    LOOP\r\n        confirm_code_generated := LPAD(FLOOR(RANDOM() * 1000)::INTEGER::TEXT, 3, '0');\r\n        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE confirm_code = confirm_code_generated);\r\n    END LOOP;\r\n    \r\n    LOOP\r\n        pickup_code_generated := LPAD(FLOOR(RANDOM() * 10000)::INTEGER::TEXT, 4, '0');\r\n        EXIT WHEN NOT EXISTS (SELECT 1 FROM orders WHERE pickup_code = pickup_code_generated);\r\n    END LOOP;\r\n    \r\n    -- Log para debugging\r\n    RAISE NOTICE 'Generando códigos - confirm_code: %, pickup_code: %', confirm_code_generated, pickup_code_generated;\r\n    \r\n    -- Insertar la nueva orden con códigos\r\n    INSERT INTO orders (\r\n        user_id,\r\n        restaurant_id,\r\n        delivery_address,\r\n        delivery_latitude,\r\n        delivery_longitude,\r\n        total_amount,\r\n        delivery_fee,\r\n        order_notes,\r\n        status,\r\n        confirm_code,\r\n        pickup_code,\r\n        created_at,\r\n        updated_at\r\n    ) VALUES (\r\n        p_user_id,\r\n        p_restaurant_id,\r\n        p_delivery_address,\r\n        p_delivery_latitude,\r\n        p_delivery_longitude,\r\n        p_total_amount,\r\n        p_delivery_fee,\r\n        p_order_notes,\r\n        'pending',\r\n        confirm_code_generated,\r\n        pickup_code_generated,\r\n        NOW(),\r\n        NOW()\r\n    ) RETURNING id INTO new_order_id;\r\n    \r\n    -- Log para verificar inserción\r\n    RAISE NOTICE 'Orden creada con ID: %, confirm_code: %, pickup_code: %', new_order_id, confirm_code_generated, pickup_code_generated;\r\n    \r\n    -- Devolver resultado con códigos incluidos\r\n    result := json_build_object(\r\n        'success', true,\r\n        'id', new_order_id,\r\n        'confirm_code', confirm_code_generated,\r\n        'pickup_code', pickup_code_generated,\r\n        'status', 'pending',\r\n        'message', 'Orden creada exitosamente'\r\n    );\r\n    \r\n    RETURN result;\r\n    \r\nEXCEPTION WHEN OTHERS THEN\r\n    RAISE NOTICE 'Error al crear orden: %', SQLERRM;\r\n    RETURN json_build_object(\r\n        'success', false,\r\n        'error', SQLERRM,\r\n        'message', 'Error al crear la orden'\r\n    );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_restaurant_id uuid, p_delivery_address text, p_total_amount numeric, p_delivery_fee numeric, p_delivery_latitude numeric DEFAULT NULL::numeric, p_delivery_longitude numeric DEFAULT NULL::numeric, p_order_notes text DEFAULT NULL::text",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "create_restaurant_public",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_restaurant_public(p_user_id uuid, p_name text, p_status text DEFAULT 'pending'::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_location_place_id text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb, p_phone text DEFAULT NULL::text, p_online boolean DEFAULT false)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_restaurant_id uuid;\r\nBEGIN\r\n  -- validate auth user\r\n  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User ID does not exist in auth.users';\r\n  END IF;\r\n\r\n  -- ensure user profile exists\r\n  PERFORM public.ensure_user_profile_public(p_user_id, COALESCE(p_name,'')||'@placeholder.local', p_name, 'restaurant');\r\n\r\n  -- if already exists, return it\r\n  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id LIMIT 1;\r\n  IF v_restaurant_id IS NOT NULL THEN\r\n    RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('restaurant_id', v_restaurant_id), 'error', NULL);\r\n  END IF;\r\n\r\n  INSERT INTO public.restaurants (\r\n    user_id, name, status, location_lat, location_lon, location_place_id, address, address_structured, phone, online, created_at, updated_at\r\n  ) VALUES (\r\n    p_user_id, p_name, p_status, p_location_lat, p_location_lon, p_location_place_id, p_address, p_address_structured, p_phone, COALESCE(p_online,false), now(), now()\r\n  ) RETURNING id INTO v_restaurant_id;\r\n\r\n  -- Optionally normalize user role to restaurant if previously client/empty\r\n  UPDATE public.users SET role = 'restaurant', updated_at = now()\r\n  WHERE id = p_user_id AND COALESCE(role,'') IN ('', 'client', 'cliente');\r\n\r\n  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('restaurant_id', v_restaurant_id), 'error', NULL);\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_name text, p_status text DEFAULT 'pending'::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_location_place_id text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb, p_phone text DEFAULT NULL::text, p_online boolean DEFAULT false",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "create_user_profile_public",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_user_profile_public(p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_result JSONB;\r\nBEGIN\r\n  -- Validar que el user_id existe en auth.users\r\n  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User ID does not exist in auth.users';\r\n  END IF;\r\n\r\n  -- Validar que no existe ya el perfil\r\n  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User profile already exists';\r\n  END IF;\r\n\r\n  -- Insertar perfil de usuario (sin metadata)\r\n  INSERT INTO public.users (\r\n    id,\r\n    email,\r\n    name,\r\n    phone,\r\n    address,\r\n    role,\r\n    email_confirm,\r\n    lat,\r\n    lon,\r\n    address_structured,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id,\r\n    p_email,\r\n    p_name,\r\n    p_phone,\r\n    p_address,\r\n    p_role,\r\n    false, -- Email no confirmado aún\r\n    p_lat,\r\n    p_lon,\r\n    p_address_structured,\r\n    NOW(),\r\n    NOW()\r\n  );\r\n\r\n  -- Retornar resultado exitoso\r\n  v_result := jsonb_build_object(\r\n    'success', true,\r\n    'user_id', p_user_id,\r\n    'message', 'User profile created successfully'\r\n  );\r\n\r\n  RETURN v_result;\r\n\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    -- Retornar error\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'error', SQLERRM\r\n    );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "create_user_profile_public",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_user_profile_public(p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_is_temp_password boolean DEFAULT false)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_res jsonb;\r\nBEGIN\r\n  -- Route to ensure function to avoid schema mismatches like missing 'metadata' column\r\n  v_res := public.ensure_user_profile_public(\r\n    p_user_id => p_user_id,\r\n    p_email => p_email,\r\n    p_name => p_name,\r\n    p_role => p_role,\r\n    p_phone => p_phone,\r\n    p_address => p_address,\r\n    p_lat => p_lat,\r\n    p_lon => p_lon,\r\n    p_address_structured => p_address_structured\r\n  );\r\n  RETURN v_res;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_phone text, p_address text, p_role text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_is_temp_password boolean DEFAULT false",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "delivery_agent_profiles_guard",
    "function_source": "CREATE OR REPLACE FUNCTION public.delivery_agent_profiles_guard()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN IF NOT EXISTS ( SELECT 1 FROM public.users u WHERE u.id = NEW.user_id AND COALESCE(u.role,'') IN ('repartidor','delivery_agent') ) THEN INSERT INTO public._debug_events(source, event, data) VALUES ('delivery_agent_profiles_guard', 'skip_insert_non_delivery', jsonb_build_object('user_id', NEW.user_id)); RETURN NULL; END IF; RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_account",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_account(p_user_id uuid, p_account_type text, p_status text DEFAULT 'active'::text)\n RETURNS uuid\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ declare v_account_id uuid; begin select id into v_account_id from accounts where user_id = p_user_id and account_type = p_account_type and status = coalesce(p_status, status) order by created_at asc limit 1;if v_account_id is null then insert into accounts (user_id, account_type, balance, status, created_at) values (p_user_id, p_account_type, 0, coalesce(p_status, 'active'), now()) returning id into v_account_id; end if;return v_account_id; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_account_type text, p_status text DEFAULT 'active'::text",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_client_profile_and_account",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_client_profile_and_account(p_user_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  -- ✅ Incluir 'status' con valor 'active' por defecto\r\n  INSERT INTO public.client_profiles AS cp (user_id, status, created_at, updated_at)\r\n  VALUES (p_user_id, 'active', now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE \r\n  SET updated_at = excluded.updated_at;\r\n\r\n  -- Asegurar registro en accounts con tipo 'client'\r\n  INSERT INTO public.accounts AS a (user_id, account_type, balance)\r\n  VALUES (p_user_id, 'client', 0.00)\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  RETURN jsonb_build_object('success', true);\r\nEXCEPTION WHEN OTHERS THEN\r\n  -- Log detallado del error\r\n  RAISE WARNING 'ensure_client_profile_and_account failed for user %: % (DETAIL: %)', \r\n    p_user_id, SQLERRM, SQLSTATE;\r\n  RAISE;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_delivery_agent_role_and_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_delivery_agent_role_and_profile(p_user_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_now timestamptz := now();\r\nBEGIN\r\n  -- Update role only if different\r\n  UPDATE public.users u\r\n  SET role = 'delivery_agent'\r\n  WHERE u.id = p_user_id AND COALESCE(u.role, '') <> 'delivery_agent';\r\n\r\n  -- Ensure delivery profile exists (minimal stub)\r\n  INSERT INTO public.delivery_agent_profiles (\r\n    user_id,\r\n    status,\r\n    account_state,\r\n    created_at,\r\n    updated_at\r\n  )\r\n  VALUES (\r\n    p_user_id,\r\n    'pending',\r\n    'pending',\r\n    v_now,\r\n    v_now\r\n  )\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  RETURN jsonb_build_object('success', true);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_financial_account",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_financial_account(p_user_id uuid, p_account_type text DEFAULT 'delivery_agent'::text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.accounts (user_id, account_type, balance) VALUES (p_user_id, p_account_type, 0.00) ON CONFLICT (user_id) DO NOTHING; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_account_type text DEFAULT 'delivery_agent'::text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_my_delivery_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_my_delivery_profile()\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ begin insert into public.delivery_agent_profiles (user_id) values (auth.uid()) on conflict (user_id) do nothing;insert into public.user_preferences (user_id) values (auth.uid()) on conflict (user_id) do nothing; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_user_preferences",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_user_preferences(_user_id uuid, _restaurant_id uuid DEFAULT NULL::uuid)\n RETURNS void\n LANGUAGE plpgsql\nAS $function$ begin insert into public.user_preferences (user_id, restaurant_id, first_login_at, last_login_at, login_count) values (_user_id, _restaurant_id, now(), now(), 1) on conflict (user_id) do update set last_login_at = now(), login_count = public.user_preferences.login_count + 1, restaurant_id = coalesce(excluded.restaurant_id, public.user_preferences.restaurant_id), updated_at = now(); end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "_user_id uuid, _restaurant_id uuid DEFAULT NULL::uuid",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_user_profile_public",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_user_profile_public(p_user_id uuid, p_email text, p_name text DEFAULT ''::text, p_role text DEFAULT 'client'::text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_exists boolean;\r\n  v_is_email_confirmed boolean := false;\r\n  v_now timestamptz := now();\r\n  v_role text;\r\nBEGIN\r\n  IF p_user_id IS NULL THEN\r\n    RAISE EXCEPTION 'p_user_id is required';\r\n  END IF;\r\n\r\n  -- verify exists in auth.users\r\n  PERFORM 1 FROM auth.users WHERE id = p_user_id;\r\n  IF NOT FOUND THEN\r\n    RAISE EXCEPTION 'User ID % does not exist in auth.users', p_user_id;\r\n  END IF;\r\n\r\n  -- email confirmation flag from auth\r\n  SELECT (email_confirmed_at IS NOT NULL) INTO v_is_email_confirmed\r\n  FROM auth.users WHERE id = p_user_id;\r\n\r\n  -- normalize role gently\r\n  v_role := CASE LOWER(COALESCE(p_role, ''))\r\n    WHEN 'usuario' THEN 'client'\r\n    WHEN 'cliente' THEN 'client'\r\n    WHEN 'restaurante' THEN 'restaurant'\r\n    WHEN 'repartidor' THEN 'delivery_agent'\r\n    ELSE COALESCE(NULLIF(TRIM(p_role), ''), 'client')\r\n  END;\r\n\r\n  -- upsert profile\r\n  SELECT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) INTO v_exists;\r\n  IF NOT v_exists THEN\r\n    INSERT INTO public.users (\r\n      id, email, name, phone, address, role, email_confirm,\r\n      lat, lon, address_structured, created_at, updated_at\r\n    ) VALUES (\r\n      p_user_id,\r\n      COALESCE(p_email, ''),\r\n      COALESCE(p_name, ''),\r\n      NULLIF(TRIM(p_phone), ''),           -- IMPORTANT: store NULL, not ''\r\n      COALESCE(p_address, ''),\r\n      COALESCE(v_role, 'client'),\r\n      COALESCE(v_is_email_confirmed, false),\r\n      p_lat,\r\n      p_lon,\r\n      p_address_structured,\r\n      v_now,\r\n      v_now\r\n    );\r\n  ELSE\r\n    UPDATE public.users u SET\r\n      email = COALESCE(NULLIF(p_email, ''), u.email),\r\n      name = COALESCE(NULLIF(p_name, ''), u.name),\r\n      phone = COALESCE(NULLIF(TRIM(p_phone), ''), u.phone),  -- ignore blank -> keep existing\r\n      address = COALESCE(NULLIF(p_address, ''), u.address),\r\n      role = CASE WHEN COALESCE(u.role, '') IN ('', 'client', 'cliente') THEN COALESCE(v_role, 'client') ELSE u.role END,\r\n      email_confirm = COALESCE(u.email_confirm, v_is_email_confirmed),\r\n      lat = COALESCE(p_lat, u.lat),\r\n      lon = COALESCE(p_lon, u.lon),\r\n      address_structured = COALESCE(p_address_structured, u.address_structured),\r\n      updated_at = v_now\r\n    WHERE u.id = p_user_id;\r\n  END IF;\r\n\r\n  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('user_id', p_user_id), 'error', NULL);\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_name text DEFAULT ''::text, p_role text DEFAULT 'client'::text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "ensure_user_profile_v2",
    "function_source": "CREATE OR REPLACE FUNCTION public.ensure_user_profile_v2(p_user_id uuid, p_email text, p_role text DEFAULT 'client'::text, p_name text DEFAULT ''::text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  RETURN public.ensure_user_profile_public(\r\n    p_user_id => p_user_id,\r\n    p_email => p_email,\r\n    p_name => p_name,\r\n    p_role => p_role,\r\n    p_phone => p_phone,\r\n    p_address => p_address,\r\n    p_lat => p_lat,\r\n    p_lon => p_lon,\r\n    p_address_structured => p_address_structured\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_role text DEFAULT 'client'::text, p_name text DEFAULT ''::text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "fn_get_restaurant_account_id",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_get_restaurant_account_id(p_restaurant_id uuid)\n RETURNS uuid\n LANGUAGE sql\n STABLE\nAS $function$ select a.id from public.restaurants r join public.accounts a on a.user_id = r.user_id where r.id = p_restaurant_id limit 1 $function$\n",
    "volatility": "STABLE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "fn_get_restaurant_owner_account_id",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_get_restaurant_owner_account_id(p_restaurant_id uuid)\n RETURNS uuid\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ select a.id from public.restaurants r join public.accounts a on a.user_id = r.user_id where r.id = p_restaurant_id -- Si usas columna \"type\" y clasificas cuentas, descomenta y ajusta: --   and a.type in ('restaurant', 'business') order by a.created_at nulls last, a.id limit 1 $function$\n",
    "volatility": "STABLE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "fn_get_restaurant_owner_user_id",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_get_restaurant_owner_user_id(p_restaurant_id uuid)\n RETURNS uuid\n LANGUAGE sql\n STABLE\nAS $function$ select r.user_id from public.restaurants r where r.id = p_restaurant_id limit 1 $function$\n",
    "volatility": "STABLE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_client",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_client()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  uname text;\r\nbegin\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_client disparado para user_id=%', new.user_id;\r\n  \r\n  select coalesce(u.name, u.email, 'Cliente') into uname\r\n  from public.users u where u.id = new.user_id;\r\n\r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'user', new.user_id, 'Nuevo cliente registrado',\r\n          coalesce(uname, 'Cliente') || ' creó una cuenta',\r\n          jsonb_build_object('user_id', new.user_id));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para cliente: %', uname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para cliente %: %', new.user_id, sqlerrm;\r\n    return new;\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_delivery_agent",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_delivery_agent()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  uname text;\r\nbegin\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_delivery_agent disparado para user_id=%', new.user_id;\r\n  \r\n  select coalesce(u.name, u.email, 'Repartidor') into uname\r\n  from public.users u where u.id = new.user_id;\r\n\r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'delivery_agent', new.user_id, 'Nuevo repartidor registrado',\r\n          coalesce(uname, 'Repartidor') || ' se registró y espera revisión',\r\n          jsonb_build_object('user_id', new.user_id, 'account_state', new.account_state));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para repartidor: %', uname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para repartidor %: %', new.user_id, sqlerrm;\r\n    return new;\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_restaurant",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_restaurant()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  rname text;\r\nbegin\r\n  -- Log para debugging\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_restaurant disparado para restaurant_id=%', new.id;\r\n  \r\n  rname := coalesce(new.name, 'Restaurante sin nombre');\r\n  \r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'restaurant', new.id, 'Nuevo restaurante registrado',\r\n          rname || ' se registró y está en revisión',\r\n          jsonb_build_object('restaurant_id', new.id, 'status', new.status, 'user_id', new.user_id));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para restaurante: %', rname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para restaurante %: %', new.id, sqlerrm;\r\n    return new; -- No fallar el insert del restaurante si falla la notificación\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "fn_orders_after_delivered",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_orders_after_delivered()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\ndeclare\r\n  v_restaurant_account_id uuid;\r\n  v_client_account_id uuid;\r\n  v_delivery_account_id uuid;\r\n  v_platform_revenue_account_id uuid;\r\n  v_platform_payables_account_id uuid;\r\n\r\n  -- Ajusta tipos/nombres si difieren en tu esquema\r\n  v_subtotal numeric := NEW.subtotal;\r\n  v_delivery_fee numeric := NEW.delivery_fee;\r\n  v_platform_commission numeric := NEW.platform_commission;\r\nbegin\r\n  -- Ejecutar solo cuando el status pasa a 'delivered'\r\n  if not (TG_OP = 'UPDATE' and NEW.status = 'delivered' and OLD.status is distinct from NEW.status) then\r\n    return NEW;\r\n  end if;\r\n\r\n  -- Lookup correcto por dueño del restaurante\r\n  v_restaurant_account_id := public.fn_get_restaurant_account_id(NEW.restaurant_id);\r\n\r\n  if v_restaurant_account_id is null then\r\n    raise notice 'Restaurant account missing (restaurants.user_id → accounts.user_id) for restaurant_id=%; skipping restaurant accounting lines.', NEW.restaurant_id;\r\n    -- Si quieres omitir solo la parte del restaurante y seguir con el resto, no retornes aquí.\r\n    -- Si prefieres abortar por completo la contabilidad (pero dejar el cambio de status), descomenta:\r\n    -- return NEW;\r\n  end if;\r\n\r\n  -- ================== BLOQUE DE CONTABILIDAD EXISTENTE ==================\r\n  -- Deja aquí intactos tus INSERT/UPDATE sobre accounts y account_transactions,\r\n  -- usando v_restaurant_account_id en lugar del lookup anterior por restaurant_id.\r\n  -- ======================================================================\r\n\r\n  return NEW;\r\nend\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "fn_orders_set_owner_on_write",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_orders_set_owner_on_write()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ begin if new.restaurant_id is not null then select r.user_id into new.restaurant_account_id from public.restaurants r where r.id = new.restaurant_id limit 1; end if; return new; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "get_all_restaurants_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_all_restaurants_admin()\n RETURNS TABLE(id uuid, user_id uuid, name text, description text, logo_url text, status text, created_at timestamp with time zone, updated_at timestamp with time zone)\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Return all restaurants (bypasses RLS)\r\n  RETURN QUERY \r\n  SELECT \r\n    r.id,\r\n    r.user_id,\r\n    r.name,\r\n    r.description,\r\n    r.logo_url,\r\n    r.status,\r\n    r.created_at,\r\n    r.updated_at\r\n  FROM restaurants r\r\n  ORDER BY r.created_at DESC;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "TABLE(id uuid, user_id uuid, name text, description text, logo_url text, status text, created_at timestamp with time zone, updated_at timestamp with time zone)"
  },
  {
    "schema_name": "public",
    "function_name": "get_all_users_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_all_users_admin()\n RETURNS TABLE(id uuid, email text, name text, phone text, address text, role text, email_confirm boolean, avatar_url text, created_at timestamp with time zone, updated_at timestamp with time zone)\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Return all users (bypasses RLS)\r\n  RETURN QUERY \r\n  SELECT \r\n    u.id,\r\n    u.email,\r\n    u.name,\r\n    u.phone,\r\n    u.address,\r\n    u.role,\r\n    u.email_confirm,\r\n    u.avatar_url,\r\n    u.created_at,\r\n    u.updated_at\r\n  FROM users u\r\n  ORDER BY u.created_at DESC;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "TABLE(id uuid, email text, name text, phone text, address text, role text, email_confirm boolean, avatar_url text, created_at timestamp with time zone, updated_at timestamp with time zone)"
  },
  {
    "schema_name": "public",
    "function_name": "get_driver_location_for_order",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_driver_location_for_order(p_order_id uuid)\n RETURNS TABLE(lat double precision, lon double precision, last_seen_at timestamp with time zone, speed double precision, heading double precision, accuracy double precision)\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_delivery_agent_id UUID;\r\n  v_requester_id UUID;\r\n  v_is_authorized BOOLEAN := FALSE;\r\nBEGIN\r\n  v_requester_id := auth.uid();\r\n  \r\n  IF v_requester_id IS NULL THEN\r\n    RAISE EXCEPTION 'Authentication required';\r\n  END IF;\r\n\r\n  -- Get the delivery agent ID for this order\r\n  SELECT delivery_agent_id INTO v_delivery_agent_id\r\n  FROM public.orders\r\n  WHERE id = p_order_id;\r\n\r\n  IF v_delivery_agent_id IS NULL THEN\r\n    -- No driver assigned yet\r\n    RETURN;\r\n  END IF;\r\n\r\n  -- Check authorization: requester must be the client, the restaurant owner, or an admin\r\n  SELECT EXISTS (\r\n    -- Case 1: requester is the client who placed the order\r\n    SELECT 1 FROM public.orders o\r\n    WHERE o.id = p_order_id AND o.user_id = v_requester_id\r\n    \r\n    UNION\r\n    \r\n    -- Case 2: requester is the restaurant owner\r\n    SELECT 1 FROM public.orders o\r\n    JOIN public.restaurants r ON o.restaurant_id = r.id\r\n    WHERE o.id = p_order_id AND r.user_id = v_requester_id\r\n    \r\n    UNION\r\n    \r\n    -- Case 3: requester is an admin\r\n    SELECT 1 FROM public.users u\r\n    WHERE u.id = v_requester_id AND u.role = 'admin'\r\n  ) INTO v_is_authorized;\r\n\r\n  IF NOT v_is_authorized THEN\r\n    RAISE EXCEPTION 'Unauthorized to view this driver location';\r\n  END IF;\r\n\r\n  -- Return the driver's current location from courier_locations_latest\r\n  RETURN QUERY\r\n  SELECT \r\n    cll.lat,\r\n    cll.lon,\r\n    cll.last_seen_at,\r\n    cll.speed,\r\n    cll.heading,\r\n    cll.accuracy\r\n  FROM public.courier_locations_latest cll\r\n  WHERE cll.user_id = v_delivery_agent_id;\r\nEND $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_order_id uuid",
    "return_type": "TABLE(lat double precision, lon double precision, last_seen_at timestamp with time zone, speed double precision, heading double precision, accuracy double precision)"
  },
  {
    "schema_name": "public",
    "function_name": "get_platform_account_id",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_platform_account_id(kind text)\n RETURNS uuid\n LANGUAGE sql\n STABLE\nAS $function$ select a.id from public.accounts a join public.users u on u.id = a.user_id where a.account_type = 'platform' and lower(u.email) = case when kind = 'revenue' then 'platform+revenue@doarepartos.com' when kind = 'payables' then 'platform+payables@doarepartos.com' end limit 1 $function$\n",
    "volatility": "STABLE",
    "arguments": "kind text",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "get_restaurant_stats_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_restaurant_stats_admin()\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  result JSON;\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Get restaurant statistics\r\n  SELECT json_build_object(\r\n    'total_restaurants', (SELECT COUNT(*) FROM restaurants),\r\n    'pending_restaurants', (SELECT COUNT(*) FROM restaurants WHERE status = 'pending' OR status IS NULL),\r\n    'approved_restaurants', (SELECT COUNT(*) FROM restaurants WHERE status = 'approved'),\r\n    'rejected_restaurants', (SELECT COUNT(*) FROM restaurants WHERE status = 'rejected'),\r\n    'suspended_restaurants', (SELECT COUNT(*) FROM restaurants WHERE status = 'suspended')\r\n  ) INTO result;\r\n  \r\n  RETURN result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "get_user_formatted_address",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_user_formatted_address(user_id uuid)\n RETURNS text\n LANGUAGE sql\n STABLE\nAS $function$\r\n  SELECT address_structured->>'formatted_address'\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "user_id uuid",
    "return_type": "text"
  },
  {
    "schema_name": "public",
    "function_name": "get_user_lat",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_user_lat(user_id uuid)\n RETURNS double precision\n LANGUAGE sql\n STABLE\nAS $function$\r\n  SELECT (address_structured->>'lat')::double precision\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "user_id uuid",
    "return_type": "double precision"
  },
  {
    "schema_name": "public",
    "function_name": "get_user_lon",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_user_lon(user_id uuid)\n RETURNS double precision\n LANGUAGE sql\n STABLE\nAS $function$\r\n  SELECT (address_structured->>'lon')::double precision\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "user_id uuid",
    "return_type": "double precision"
  },
  {
    "schema_name": "public",
    "function_name": "get_user_stats_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.get_user_stats_admin()\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  result JSON;\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Get user statistics\r\n  SELECT json_build_object(\r\n    'total_users', (SELECT COUNT(*) FROM users),\r\n    'clients', (SELECT COUNT(*) FROM users WHERE role = 'cliente'),\r\n    'restaurants', (SELECT COUNT(*) FROM users WHERE role = 'restaurante'), \r\n    'delivery_agents', (SELECT COUNT(*) FROM users WHERE role = 'repartidor'),\r\n    'admins', (SELECT COUNT(*) FROM users WHERE role = 'admin'),\r\n    'confirmed_emails', (SELECT COUNT(*) FROM users WHERE email_confirm = true),\r\n    'unconfirmed_emails', (SELECT COUNT(*) FROM users WHERE email_confirm = false OR email_confirm IS NULL)\r\n  ) INTO result;\r\n  \r\n  RETURN result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "guard_delivery_profile_role",
    "function_source": "CREATE OR REPLACE FUNCTION public.guard_delivery_profile_role()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ DECLARE u record; BEGIN SELECT id, email, role INTO u FROM public.users WHERE id = NEW.user_id; IF u.id IS NULL THEN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) VALUES ('delivery_agent_profiles','before_insert_denied', NEW.user_id, NULL, NULL, jsonb_build_object('reason','user_not_found')); RAISE EXCEPTION 'user_not_found'; END IF; IF lower(coalesce(u.role,'')) NOT IN ('repartidor','delivery_agent') THEN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) VALUES ('delivery_agent_profiles','before_insert_denied', u.id, u.email, u.role, jsonb_build_object('reason','invalid_role','payload', row_to_json(NEW)::jsonb)); RAISE EXCEPTION 'invalid_role_for_delivery_profile'; END IF; RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "handle_delivery_agent_account_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_delivery_agent_account_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  IF NEW.account_type = 'delivery_agent' THEN\r\n    PERFORM public.ensure_delivery_agent_role_and_profile(NEW.user_id);\r\n  END IF;\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "handle_new_user",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_new_user()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_email TEXT;\r\n  v_role TEXT := 'cliente'; -- Por defecto todos son clientes\r\nBEGIN\r\n  -- Obtener email del nuevo usuario en auth.users\r\n  v_email := NEW.email;\r\n  \r\n  -- Log de inicio (para debugging)\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_new_user', 'START', v_role, NEW.id, v_email, jsonb_build_object('raw_user_meta_data', NEW.raw_user_meta_data));\r\n\r\n  -- 📝 PASO 1: Insertar en public.users\r\n  INSERT INTO public.users (id, email, role, name, created_at, updated_at, email_confirm)\r\n  VALUES (\r\n    NEW.id,\r\n    v_email,\r\n    v_role,\r\n    COALESCE(NEW.raw_user_meta_data->>'name', v_email), -- Usar nombre del meta_data o email\r\n    now(),\r\n    now(),\r\n    false\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = EXCLUDED.email,\r\n    updated_at = now();\r\n\r\n  -- Log de public.users creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'USER_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 2: Crear client_profile (status='active' es el default)\r\n  INSERT INTO public.client_profiles (user_id, created_at, updated_at)\r\n  VALUES (NEW.id, now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET updated_at = now();\r\n\r\n  -- Log de client_profile creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 3: Crear cuenta (account) para el cliente\r\n  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())\r\n  ON CONFLICT DO NOTHING;\r\n\r\n  -- Log de account creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'ACCOUNT_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 4: Crear user_preferences\r\n  INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n  VALUES (NEW.id, now(), now())\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  -- Log de SUCCESS\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'SUCCESS', v_role, NEW.id, v_email);\r\n\r\n  RETURN NEW;\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    -- Log de ERROR con detalles\r\n    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n    VALUES ('handle_new_user', 'ERROR', v_role, NEW.id, v_email, \r\n            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));\r\n    \r\n    -- Re-lanzar el error para que Supabase Auth devuelva 500\r\n    RAISE;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "handle_new_user_delivery_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_new_user_delivery_profile()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ begin insert into public.delivery_agent_profiles (user_id) values (new.id) on conflict (user_id) do nothing;insert into public.user_preferences (user_id) values (new.id) on conflict (user_id) do nothing;return new; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "handle_user_email_confirmation",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n  -- Solo actualizar si email_confirmed_at cambió de null a no-null\r\n  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN\r\n    UPDATE public.users \r\n    SET \r\n      email_confirm = true,\r\n      updated_at = NOW()\r\n    WHERE id = NEW.id;\r\n  END IF;\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "has_active_couriers",
    "function_source": "CREATE OR REPLACE FUNCTION public.has_active_couriers()\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  _exists BOOLEAN;\r\nBEGIN\r\n  -- Importante: usar EXISTS para que sea rápido y sólo lea 1 fila.\r\n  SELECT EXISTS (\r\n    SELECT 1\r\n    FROM public.delivery_agent_profiles p\r\n    WHERE p.status = 'online'\r\n      AND p.account_state = 'approved'\r\n  ) INTO _exists;\r\n\r\n  RETURN COALESCE(_exists, FALSE);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "insert_user_to_auth",
    "function_source": "CREATE OR REPLACE FUNCTION public.insert_user_to_auth(email text, password text)\n RETURNS uuid\n LANGUAGE plpgsql\nAS $function$\nDECLARE\n  user_id uuid;\n  encrypted_pw text;\nBEGIN\n  user_id := gen_random_uuid();\n  encrypted_pw := crypt(password, gen_salt('bf'));\n  \n  INSERT INTO auth.users\n    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)\n  VALUES\n    (gen_random_uuid(), user_id, 'authenticated', 'authenticated', email, encrypted_pw, '2023-05-03 19:41:43.585805+00', '2023-04-22 13:10:03.275387+00', '2023-04-22 13:10:31.458239+00', '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}', '2023-05-03 19:41:43.580424+00', '2023-05-03 19:41:43.585948+00', '', '', '', '');\n  \n  INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)\n  VALUES\n    (gen_random_uuid(), user_id, format('{\"sub\":\"%s\",\"email\":\"%s\"}', user_id::text, email)::jsonb, 'email', '2023-05-03 19:41:43.582456+00', '2023-05-03 19:41:43.582497+00', '2023-05-03 19:41:43.582497+00');\n  \n  RETURN user_id;\nEND;\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "email text, password text",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "is_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_admin()\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\n  SELECT EXISTS (\r\n    SELECT 1 FROM public.users u\r\n    WHERE u.id = auth.uid() AND u.role = 'admin'\r\n  );\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "is_current_user_admin",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_current_user_admin()\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\nAS $function$\r\n  SELECT EXISTS (\r\n    SELECT 1 \r\n    FROM public.users \r\n    WHERE id = auth.uid() \r\n      AND role = 'admin'\r\n  );\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "is_delivery_profile_complete",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_delivery_profile_complete(user_id uuid)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  profile_complete BOOLEAN;\r\nBEGIN\r\n  SELECT \r\n    name IS NOT NULL AND\r\n    phone IS NOT NULL AND\r\n    address IS NOT NULL AND\r\n    lat IS NOT NULL AND\r\n    lon IS NOT NULL AND\r\n    profile_image_url IS NOT NULL AND\r\n    id_document_front_url IS NOT NULL AND\r\n    id_document_back_url IS NOT NULL AND\r\n    vehicle_type IS NOT NULL AND\r\n    vehicle_plate IS NOT NULL\r\n  INTO profile_complete\r\n  FROM public.users\r\n  WHERE id = user_id AND role = 'repartidor';\r\n  \r\n  RETURN COALESCE(profile_complete, FALSE);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "user_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "is_email_verified",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_email_verified(p_email text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_confirmed_at TIMESTAMPTZ;\r\nBEGIN\r\n  -- Buscar en auth.users el email_confirmed_at\r\n  SELECT email_confirmed_at\r\n  INTO v_confirmed_at\r\n  FROM auth.users\r\n  WHERE email = p_email\r\n  LIMIT 1;\r\n  \r\n  -- Si encontró el usuario y tiene email_confirmed_at, está verificado\r\n  RETURN (v_confirmed_at IS NOT NULL);\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    -- En caso de error, asumir no verificado\r\n    RETURN FALSE;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "is_restaurant_owner",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_restaurant_owner(p_restaurant_id uuid)\n RETURNS boolean\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\n  SELECT EXISTS (\r\n    SELECT 1 FROM public.restaurants r\r\n    WHERE r.id = p_restaurant_id AND r.user_id = auth.uid()\r\n  );\r\n$function$\n",
    "volatility": "STABLE",
    "arguments": "p_restaurant_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "is_restaurant_profile_complete",
    "function_source": "CREATE OR REPLACE FUNCTION public.is_restaurant_profile_complete(restaurant_id uuid)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  profile_complete BOOLEAN;\r\nBEGIN\r\n  SELECT \r\n    r.name IS NOT NULL AND\r\n    r.logo_url IS NOT NULL AND\r\n    r.cover_image_url IS NOT NULL AND\r\n    r.cuisine_type IS NOT NULL AND\r\n    r.address_structured IS NOT NULL AND\r\n    u.phone IS NOT NULL\r\n  INTO profile_complete\r\n  FROM public.restaurants r\r\n  JOIN public.users u ON r.user_id = u.id\r\n  WHERE r.id = restaurant_id;\r\n  \r\n  RETURN COALESCE(profile_complete, FALSE);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "restaurant_id uuid",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "log_auth_user_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.log_auth_user_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.system_debug_log(tag, data) VALUES ( 'auth_user_insert', jsonb_build_object( 'new_id', NEW.id, 'email', NEW.email, 'meta', NEW.raw_user_meta_data ) ); RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "log_dap_after_upsert",
    "function_source": "CREATE OR REPLACE FUNCTION public.log_dap_after_upsert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) SELECT 'delivery_agent_profiles','after_upsert', u.id, u.email, u.role, jsonb_build_object('profile', row_to_json(NEW)::jsonb) FROM public.users u WHERE u.id = NEW.user_id; RETURN NEW; END $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "mark_restaurant_welcome_seen",
    "function_source": "CREATE OR REPLACE FUNCTION public.mark_restaurant_welcome_seen(_user_id uuid)\n RETURNS void\n LANGUAGE sql\nAS $function$ update public.user_preferences set has_seen_restaurant_welcome = true, restaurant_welcome_seen_at = now(), updated_at = now() where user_id = _user_id; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "_user_id uuid",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "mark_user_login",
    "function_source": "CREATE OR REPLACE FUNCTION public.mark_user_login()\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ begin insert into public.user_preferences (user_id, first_login_at, last_login_at, login_count) values (auth.uid(), now(), now(), 1) on conflict (user_id) do update set last_login_at = now(), first_login_at = coalesce(public.user_preferences.first_login_at, excluded.first_login_at), login_count = public.user_preferences.login_count + 1; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "normalize_user_role",
    "function_source": "CREATE OR REPLACE FUNCTION public.normalize_user_role(p_role text)\n RETURNS text\n LANGUAGE sql\n IMMUTABLE\nAS $function$ SELECT CASE lower(trim($1)) WHEN 'cliente' THEN 'client' WHEN 'client' THEN 'client' WHEN 'restaurante' THEN 'restaurant' WHEN 'restaurant' THEN 'restaurant' WHEN 'repartidor' THEN 'delivery_agent' WHEN 'delivery_agent' THEN 'delivery_agent' WHEN 'admin' THEN 'admin' WHEN 'platform' THEN 'platform' ELSE 'client' END $function$\n",
    "volatility": "IMMUTABLE",
    "arguments": "p_role text",
    "return_type": "text"
  },
  {
    "schema_name": "public",
    "function_name": "pre_signup_check_repartidor",
    "function_source": "CREATE OR REPLACE FUNCTION public.pre_signup_check_repartidor(p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text)\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  v_email_exists boolean := false;\r\n  v_phone_exists boolean := false;\r\nbegin\r\n  -- Check email if provided\r\n  if p_email is not null then\r\n    select exists(\r\n      select 1 \r\n      from public.users \r\n      where email = p_email\r\n    ) into v_email_exists;\r\n  end if;\r\n\r\n  -- Check phone if provided\r\n  if p_phone is not null then\r\n    select exists(\r\n      select 1 \r\n      from public.users \r\n      where phone = p_phone\r\n    ) into v_phone_exists;\r\n  end if;\r\n\r\n  -- Return results\r\n  return json_build_object(\r\n    'email_taken', v_email_exists,\r\n    'phone_taken', v_phone_exists\r\n  );\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "pre_signup_validation",
    "function_source": "CREATE OR REPLACE FUNCTION public.pre_signup_validation(p_email text, p_phone text DEFAULT NULL::text, p_restaurant_name text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n    v_email_exists BOOLEAN;\r\n    v_phone_exists BOOLEAN;\r\n    v_name_exists BOOLEAN;\r\nBEGIN\r\n    -- 1. Verificar Email: Siempre se hace contra 'public.users'\r\n    SELECT EXISTS (\r\n        SELECT 1 FROM public.users WHERE lower(email) = lower(p_email)\r\n    ) INTO v_email_exists;\r\n\r\n    -- 2. Verificar Teléfono: Siempre se hace contra 'public.users', si se proporciona\r\n    IF p_phone IS NOT NULL AND p_phone <> '' THEN\r\n        SELECT EXISTS (\r\n            SELECT 1 FROM public.users WHERE phone = p_phone\r\n        ) INTO v_phone_exists;\r\n    ELSE\r\n        v_phone_exists := FALSE;\r\n    END IF;\r\n    \r\n    -- 3. Verificar Nombre de Restaurante: Solo se hace si se proporciona un nombre\r\n    IF p_restaurant_name IS NOT NULL AND p_restaurant_name <> '' THEN\r\n         SELECT EXISTS (\r\n            SELECT 1 FROM public.restaurants WHERE lower(name) = lower(p_restaurant_name)\r\n        ) INTO v_name_exists;\r\n    ELSE\r\n        v_name_exists := FALSE;\r\n    END IF;\r\n\r\n    -- Devolver un solo objeto JSON con todos los resultados\r\n    RETURN jsonb_build_object(\r\n        'email_taken', v_email_exists,\r\n        'phone_taken', v_phone_exists,\r\n        'name_taken', v_name_exists\r\n    );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text, p_phone text DEFAULT NULL::text, p_restaurant_name text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "process_order_delivery_v3",
    "function_source": "CREATE OR REPLACE FUNCTION public.process_order_delivery_v3()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_commission_bps integer;\r\n  v_commission_rate numeric(10,4);\r\n  v_platform_commission numeric(10,2);\r\n  v_restaurant_net numeric(10,2);\r\n  v_delivery_earning numeric(10,2);\r\n  v_platform_delivery_margin numeric(10,2);\r\n\r\n  v_restaurant_account_id uuid;\r\n  v_delivery_account_id uuid;\r\n  v_platform_revenue_account_id uuid;\r\n  v_platform_payables_account_id uuid;\r\n\r\n  v_payment_method text;\r\n  v_restaurant_user_id uuid;\r\n  v_short_order text := '';\r\nBEGIN\r\n  IF NEW.status = 'delivered' AND (OLD.status IS DISTINCT FROM 'delivered') THEN\r\n    v_short_order := LEFT(NEW.id::text, 8);\r\n\r\n    -- Restaurant config\r\n    SELECT COALESCE(r.commission_bps, 1500), r.user_id\r\n    INTO v_commission_bps, v_restaurant_user_id\r\n    FROM public.restaurants r\r\n    WHERE r.id = NEW.restaurant_id;\r\n\r\n    IF v_restaurant_user_id IS NULL THEN\r\n      RAISE WARNING '[delivery_v3] Restaurant not found for order %', NEW.id;\r\n      RETURN NEW;\r\n    END IF;\r\n\r\n    -- Clamp and compute amounts\r\n    v_commission_bps := GREATEST(0, LEAST(3000, v_commission_bps));\r\n    v_commission_rate := v_commission_bps / 10000.0;\r\n    v_platform_commission := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) * v_commission_rate, 2);\r\n    v_restaurant_net := ROUND(COALESCE(NEW.subtotal, NEW.total_amount - COALESCE(NEW.delivery_fee, 0)) - v_platform_commission, 2);\r\n    v_delivery_earning := ROUND(COALESCE(NEW.delivery_fee, 0) * 0.85, 2);\r\n    v_platform_delivery_margin := ROUND(COALESCE(NEW.delivery_fee, 0) - v_delivery_earning, 2);\r\n\r\n    v_payment_method := COALESCE(NEW.payment_method, 'cash');\r\n\r\n    -- Resolve accounts\r\n    SELECT a.id INTO v_restaurant_account_id\r\n    FROM public.accounts a\r\n    WHERE a.user_id = v_restaurant_user_id AND a.account_type = 'restaurant'\r\n    ORDER BY a.created_at DESC\r\n    LIMIT 1;\r\n\r\n    IF NEW.delivery_agent_id IS NOT NULL THEN\r\n      SELECT a.id INTO v_delivery_account_id\r\n      FROM public.accounts a\r\n      WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent'\r\n      ORDER BY a.created_at DESC\r\n      LIMIT 1;\r\n    END IF;\r\n\r\n    SELECT a.id INTO v_platform_revenue_account_id\r\n    FROM public.accounts a\r\n    WHERE a.account_type = 'platform_revenue'\r\n    ORDER BY a.created_at DESC\r\n    LIMIT 1;\r\n\r\n    SELECT a.id INTO v_platform_payables_account_id\r\n    FROM public.accounts a\r\n    WHERE a.account_type = 'platform_payables'\r\n    ORDER BY a.created_at DESC\r\n    LIMIT 1;\r\n\r\n    IF v_restaurant_account_id IS NULL OR v_platform_revenue_account_id IS NULL OR v_platform_payables_account_id IS NULL THEN\r\n      RAISE WARNING '[delivery_v3] Missing core accounts for order %', NEW.id;\r\n      RETURN NEW;\r\n    END IF;\r\n\r\n    -- Distribution lines (positives)\r\n    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n    VALUES (\r\n      v_platform_revenue_account_id,\r\n      'PLATFORM_COMMISSION',\r\n      v_platform_commission,\r\n      NEW.id,\r\n      'Comisión plataforma ' || v_commission_bps || 'bps orden #' || v_short_order,\r\n      jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', v_payment_method)\r\n    )\r\n    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n\r\n    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n    VALUES (\r\n      v_restaurant_account_id,\r\n      'RESTAURANT_PAYABLE',\r\n      v_restaurant_net,\r\n      NEW.id,\r\n      'Pago neto restaurante orden #' || v_short_order,\r\n      jsonb_build_object('commission_bps', v_commission_bps, 'rate', v_commission_rate, 'payment_method', v_payment_method)\r\n    )\r\n    ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n\r\n    IF v_delivery_account_id IS NOT NULL AND COALESCE(NEW.delivery_fee, 0) > 0 THEN\r\n      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n      VALUES (\r\n        v_delivery_account_id,\r\n        'DELIVERY_EARNING',\r\n        v_delivery_earning,\r\n        NEW.id,\r\n        'Ganancia delivery 85% orden #' || v_short_order,\r\n        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.85, 'payment_method', v_payment_method)\r\n      )\r\n      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n\r\n      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n      VALUES (\r\n        v_platform_revenue_account_id,\r\n        'PLATFORM_DELIVERY_MARGIN',\r\n        v_platform_delivery_margin,\r\n        NEW.id,\r\n        'Margen plataforma delivery 15% orden #' || v_short_order,\r\n        jsonb_build_object('delivery_fee', COALESCE(NEW.delivery_fee, 0), 'pct', 0.15, 'payment_method', v_payment_method)\r\n      )\r\n      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n    END IF;\r\n\r\n    -- Balancing line (negative) to make per-order sum = 0\r\n    IF v_payment_method = 'cash' AND v_delivery_account_id IS NOT NULL THEN\r\n      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n      VALUES (\r\n        v_delivery_account_id,\r\n        'CASH_COLLECTED',\r\n        -NEW.total_amount,\r\n        NEW.id,\r\n        'Efectivo recolectado orden #' || v_short_order,\r\n        jsonb_build_object('total', NEW.total_amount, 'payment_method', 'cash', 'collected_by_delivery', true)\r\n      )\r\n      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n    ELSE\r\n      -- card: platform captured funds; post balancing negative in platform_payables\r\n      INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata)\r\n      VALUES (\r\n        v_platform_payables_account_id,\r\n        'CASH_COLLECTED',\r\n        -NEW.total_amount,\r\n        NEW.id,\r\n        'Cobro por tarjeta orden #' || v_short_order,\r\n        jsonb_build_object('total', NEW.total_amount, 'payment_method', 'card')\r\n      )\r\n      ON CONFLICT ON CONSTRAINT uq_account_txn_order_account_type DO NOTHING;\r\n    END IF;\r\n\r\n    -- NOTE: No creation of pending settlements here. Settlements must be initiated explicitly via RPC/UI.\r\n\r\n    RAISE NOTICE '✅ [delivery_v3] order % processed (method %, net_rest %, deliv %) [no auto-settlement]', NEW.id, v_payment_method, v_restaurant_net, v_delivery_earning;\r\n  END IF;\r\n\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "process_order_financial_completion",
    "function_source": "CREATE OR REPLACE FUNCTION public.process_order_financial_completion(order_uuid uuid)\n RETURNS json\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    v_order RECORD;\r\n    v_restaurant_account_id UUID;\r\n    v_delivery_account_id UUID;\r\n    v_platform_revenue_account_id UUID;\r\n    v_subtotal DECIMAL(10,2);\r\n    v_commission DECIMAL(10,2);\r\n    v_restaurant_earning DECIMAL(10,2);\r\n    v_delivery_earning DECIMAL(10,2);\r\n    v_result JSON;\r\n    v_commission_bps integer;\r\n    v_commission_rate numeric;\r\nBEGIN\r\n    SELECT o.*, r.name as restaurant_name, u.name as delivery_agent_name, COALESCE(r.commission_bps, 1500) as c_bps\r\n    INTO v_order\r\n    FROM public.orders o\r\n    LEFT JOIN public.restaurants r ON o.restaurant_id = r.id\r\n    LEFT JOIN public.users u ON o.delivery_agent_id = u.id\r\n    WHERE o.id = order_uuid;\r\n\r\n    IF NOT FOUND THEN\r\n        RETURN json_build_object('success', false, 'error', 'Order not found');\r\n    END IF;\r\n    IF v_order.status != 'delivered' THEN\r\n        RETURN json_build_object('success', false, 'error', 'Order is not delivered yet');\r\n    END IF;\r\n    IF EXISTS (SELECT 1 FROM public.account_transactions WHERE order_id = order_uuid) THEN\r\n        RETURN json_build_object('success', false, 'error', 'Transactions already processed for this order');\r\n    END IF;\r\n\r\n    SELECT id INTO v_restaurant_account_id\r\n    FROM public.accounts \r\n    WHERE user_id = (SELECT user_id FROM public.restaurants WHERE id = v_order.restaurant_id)\r\n      AND account_type ILIKE 'restaur%'\r\n    LIMIT 1;\r\n\r\n    SELECT id INTO v_delivery_account_id\r\n    FROM public.accounts \r\n    WHERE user_id = v_order.delivery_agent_id\r\n      AND account_type ILIKE 'delivery%'\r\n    LIMIT 1;\r\n\r\n    SELECT id INTO v_platform_revenue_account_id\r\n    FROM public.accounts \r\n    WHERE user_id = (SELECT id FROM public.users WHERE email ILIKE 'platform+revenue%@%')\r\n      OR account_type = 'platform_revenue'\r\n    LIMIT 1;\r\n\r\n    IF v_restaurant_account_id IS NULL OR v_delivery_account_id IS NULL OR v_platform_revenue_account_id IS NULL THEN\r\n        RETURN json_build_object('success', false, 'error', 'Required accounts not found');\r\n    END IF;\r\n\r\n    v_subtotal := v_order.total_amount - COALESCE(v_order.delivery_fee, 0);\r\n    v_commission_bps := COALESCE(v_order.c_bps, 1500);\r\n    v_commission_rate := v_commission_bps::numeric / 10000.0;\r\n    v_commission := ROUND(v_subtotal * v_commission_rate, 2);\r\n    v_restaurant_earning := v_subtotal - v_commission;\r\n    v_delivery_earning := COALESCE(v_order.delivery_fee, 0);\r\n\r\n    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)\r\n    VALUES (\r\n        v_restaurant_account_id,\r\n        'ORDER_REVENUE',\r\n        v_restaurant_earning,\r\n        order_uuid,\r\n        format('Ingreso por orden #%s - %s', LEFT(order_uuid::text, 8), v_order.restaurant_name),\r\n        json_build_object('order_id', order_uuid, 'subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps)\r\n    );\r\n\r\n    IF v_delivery_earning > 0 THEN\r\n        INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)\r\n        VALUES (\r\n            v_delivery_account_id,\r\n            'DELIVERY_EARNING',\r\n            v_delivery_earning,\r\n            order_uuid,\r\n            format('Delivery fee - Orden #%s', LEFT(order_uuid::text, 8)),\r\n            json_build_object('order_id', order_uuid, 'delivery_fee', v_delivery_earning)\r\n        );\r\n    END IF;\r\n\r\n    INSERT INTO public.account_transactions (account_id, type, amount, order_id, description, metadata)\r\n    VALUES (\r\n        v_platform_revenue_account_id,\r\n        'PLATFORM_COMMISSION',\r\n        v_commission,\r\n        order_uuid,\r\n        format('Comisión %s - Orden #%s', public._fmt_pct(v_commission_rate), LEFT(order_uuid::text, 8)),\r\n        json_build_object('order_id', order_uuid, 'subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps, 'restaurant_name', v_order.restaurant_name)\r\n    );\r\n\r\n    UPDATE public.accounts \r\n    SET balance = balance + v_restaurant_earning, updated_at = NOW()\r\n    WHERE id = v_restaurant_account_id;\r\n\r\n    IF v_delivery_earning > 0 THEN\r\n        UPDATE public.accounts \r\n        SET balance = balance + v_delivery_earning, updated_at = NOW()\r\n        WHERE id = v_delivery_account_id;\r\n    END IF;\r\n\r\n    UPDATE public.accounts \r\n    SET balance = balance + v_commission, updated_at = NOW()\r\n    WHERE id = v_platform_revenue_account_id;\r\n\r\n    v_result := json_build_object(\r\n        'success', true,\r\n        'order_id', order_uuid,\r\n        'calculations', json_build_object(\r\n            'total_amount', v_order.total_amount,\r\n            'subtotal', v_subtotal,\r\n            'delivery_fee', v_delivery_earning,\r\n            'commission', v_commission,\r\n            'commission_rate', v_commission_rate,\r\n            'restaurant_earning', v_restaurant_earning,\r\n            'delivery_earning', v_delivery_earning\r\n        )\r\n    );\r\n\r\n    RETURN v_result;\r\nEXCEPTION WHEN OTHERS THEN\r\n    RETURN json_build_object('success', false, 'error', SQLERRM, 'error_code', SQLSTATE);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "order_uuid uuid",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "process_order_financial_transactions",
    "function_source": "CREATE OR REPLACE FUNCTION public.process_order_financial_transactions()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n  restaurant_account_id UUID;\r\n  delivery_account_id UUID;\r\n  product_total DECIMAL(10,2);\r\n  platform_commission DECIMAL(10,2);\r\n  delivery_earning DECIMAL(10,2);\r\nBEGIN\r\n  -- Only process when status changes to 'delivered'\r\n  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN\r\n    \r\n    -- Get restaurant account\r\n    SELECT a.id INTO restaurant_account_id\r\n    FROM accounts a\r\n    JOIN restaurants r ON r.user_id = a.user_id\r\n    WHERE r.id = NEW.restaurant_id AND a.account_type = 'restaurant';\r\n    \r\n    -- Get delivery agent account\r\n    SELECT a.id INTO delivery_account_id\r\n    FROM accounts a\r\n    WHERE a.user_id = NEW.delivery_agent_id AND a.account_type = 'delivery_agent';\r\n    \r\n    -- Calculate amounts\r\n    product_total := NEW.total_amount - COALESCE(NEW.delivery_fee, 35.00);\r\n    platform_commission := product_total * 0.20;\r\n    delivery_earning := COALESCE(NEW.delivery_fee, 35.00) * 0.85;\r\n    \r\n    -- Create transactions based on payment method\r\n    IF NEW.payment_method = 'cash' THEN\r\n      -- Cash payment: 4 transactions\r\n      \r\n      -- 1. Restaurant revenue (credit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, \r\n              'Revenue from order ' || NEW.id);\r\n      \r\n      -- 2. Platform commission (debit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, \r\n              'Platform commission for order ' || NEW.id);\r\n      \r\n      -- 3. Delivery earning (credit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, \r\n              'Delivery earning for order ' || NEW.id);\r\n      \r\n      -- 4. Cash collected (debit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (delivery_account_id, 'CASH_COLLECTED', -NEW.total_amount, NEW.id, \r\n              'Cash collected for order ' || NEW.id);\r\n      \r\n    ELSE\r\n      -- Card payment: 3 transactions (no cash collection)\r\n      \r\n      -- 1. Restaurant revenue (credit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (restaurant_account_id, 'ORDER_REVENUE', product_total, NEW.id, \r\n              'Revenue from order ' || NEW.id);\r\n      \r\n      -- 2. Platform commission (debit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (restaurant_account_id, 'PLATFORM_COMMISSION', -platform_commission, NEW.id, \r\n              'Platform commission for order ' || NEW.id);\r\n      \r\n      -- 3. Delivery earning (credit)\r\n      INSERT INTO account_transactions (account_id, type, amount, order_id, description)\r\n      VALUES (delivery_account_id, 'DELIVERY_EARNING', delivery_earning, NEW.id, \r\n              'Delivery earning for order ' || NEW.id);\r\n    END IF;\r\n    \r\n    -- Update account balances\r\n    UPDATE accounts \r\n    SET balance = (\r\n      SELECT COALESCE(SUM(amount), 0) \r\n      FROM account_transactions \r\n      WHERE account_id = accounts.id\r\n    ),\r\n    updated_at = now()\r\n    WHERE id IN (restaurant_account_id, delivery_account_id);\r\n    \r\n  END IF;\r\n  \r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "process_order_payment_on_delivery",
    "function_source": "CREATE OR REPLACE FUNCTION public.process_order_payment_on_delivery()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n    v_restaurant_account_id uuid;\r\n    v_delivery_account_id uuid;\r\n    v_platform_revenue_account_id uuid;\r\n    v_platform_payables_account_id uuid;\r\n    \r\n    v_commission_bps integer;\r\n    v_commission_rate numeric(10,4);\r\n    v_platform_commission numeric(10,2);\r\n    v_restaurant_net numeric(10,2);\r\n    v_delivery_earning numeric(10,2);\r\n    v_platform_delivery_margin numeric(10,2);\r\n    \r\n    v_payment_method text;\r\nBEGIN\r\n    -- Solo procesar cuando cambia de cualquier estado a 'delivered'\r\n    IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN\r\n        \r\n        -- ==========================================\r\n        -- OBTENER CUENTAS NECESARIAS\r\n        -- ==========================================\r\n        \r\n        -- Cuenta del restaurante\r\n        SELECT a.id INTO v_restaurant_account_id\r\n        FROM public.accounts a\r\n        INNER JOIN public.restaurants r ON r.user_id = a.user_id\r\n        WHERE r.id = NEW.restaurant_id\r\n        AND a.account_type = 'restaurant'\r\n        ORDER BY a.created_at DESC LIMIT 1;\r\n        \r\n        -- Cuenta del delivery agent\r\n        SELECT id INTO v_delivery_account_id\r\n        FROM public.accounts\r\n        WHERE user_id = NEW.delivery_agent_id\r\n        AND account_type = 'delivery_agent'\r\n        ORDER BY created_at DESC LIMIT 1;\r\n        \r\n        -- ✅ BUSCAR platform_revenue DIRECTAMENTE por account_type\r\n        SELECT id INTO v_platform_revenue_account_id\r\n        FROM public.accounts\r\n        WHERE account_type = 'platform_revenue'\r\n        ORDER BY created_at DESC LIMIT 1;\r\n        \r\n        -- ✅ BUSCAR platform_payables DIRECTAMENTE por account_type\r\n        SELECT id INTO v_platform_payables_account_id\r\n        FROM public.accounts\r\n        WHERE account_type = 'platform_payables'\r\n        ORDER BY created_at DESC LIMIT 1;\r\n        \r\n        -- Validaciones\r\n        IF v_restaurant_account_id IS NULL THEN\r\n            RAISE EXCEPTION 'Restaurant account not found for restaurant_id=%', NEW.restaurant_id;\r\n        END IF;\r\n        \r\n        IF v_delivery_account_id IS NULL THEN\r\n            RAISE EXCEPTION 'Delivery agent account not found for delivery_agent_id=%', NEW.delivery_agent_id;\r\n        END IF;\r\n        \r\n        IF v_platform_revenue_account_id IS NULL THEN\r\n            RAISE EXCEPTION 'Platform revenue account not found (account_type=platform_revenue)';\r\n        END IF;\r\n        \r\n        IF v_platform_payables_account_id IS NULL THEN\r\n            RAISE EXCEPTION 'Platform payables account not found (account_type=platform_payables)';\r\n        END IF;\r\n        \r\n        -- ==========================================\r\n        -- CALCULAR COMISIÓN DINÁMICA\r\n        -- ==========================================\r\n        \r\n        -- Obtener commission_bps desde restaurants\r\n        SELECT commission_bps INTO v_commission_bps\r\n        FROM public.restaurants\r\n        WHERE id = NEW.restaurant_id;\r\n        \r\n        v_commission_bps := COALESCE(v_commission_bps, 1500); -- Default 15%\r\n        v_commission_bps := LEAST(GREATEST(v_commission_bps, 0), 3000); -- Clamp 0-30%\r\n        \r\n        v_commission_rate := v_commission_bps / 10000.0;\r\n        v_platform_commission := ROUND((NEW.subtotal * v_commission_rate)::numeric, 2);\r\n        v_restaurant_net := NEW.subtotal - v_platform_commission;\r\n        \r\n        -- Delivery earnings: 85% del fee\r\n        v_delivery_earning := ROUND((COALESCE(NEW.delivery_fee, 0) * 0.85)::numeric, 2);\r\n        v_platform_delivery_margin := COALESCE(NEW.delivery_fee, 0) - v_delivery_earning;\r\n        \r\n        -- Leer payment_method desde orders\r\n        v_payment_method := COALESCE(NEW.payment_method, 'cash');\r\n        \r\n        -- ==========================================\r\n        -- INSERTAR TRANSACCIONES CON METADATA\r\n        -- ==========================================\r\n        \r\n        -- 1) Ingreso total de la orden (platform_payables recibe el dinero)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_platform_payables_account_id,\r\n            'ORDER_REVENUE',\r\n            NEW.total_amount,\r\n            NEW.id,\r\n            'Ingreso total pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'payment_method', v_payment_method,\r\n                'restaurant_id', NEW.restaurant_id,\r\n                'subtotal', NEW.subtotal,\r\n                'delivery_fee', NEW.delivery_fee\r\n            )\r\n        );\r\n        \r\n        -- 2) Comisión de plataforma (ingreso a platform_revenue)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_platform_revenue_account_id,\r\n            'PLATFORM_COMMISSION',\r\n            v_platform_commission,\r\n            NEW.id,\r\n            'Comisión plataforma (' || (v_commission_rate * 100)::text || '%) pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'commission_bps', v_commission_bps,\r\n                'commission_rate', v_commission_rate,\r\n                'subtotal', NEW.subtotal,\r\n                'calculated_commission', v_platform_commission\r\n            )\r\n        );\r\n        \r\n        -- 3) Pago al restaurante (neto después de comisión)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_restaurant_account_id,\r\n            'RESTAURANT_PAYABLE',\r\n            v_restaurant_net,\r\n            NEW.id,\r\n            'Pago neto restaurante pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'subtotal', NEW.subtotal,\r\n                'commission_bps', v_commission_bps,\r\n                'commission_deducted', v_platform_commission,\r\n                'net_amount', v_restaurant_net\r\n            )\r\n        );\r\n        \r\n        -- 4) Ganancia del delivery (85% del fee)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_delivery_account_id,\r\n            'DELIVERY_EARNING',\r\n            v_delivery_earning,\r\n            NEW.id,\r\n            'Ganancia delivery (85%) pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'delivery_fee', NEW.delivery_fee,\r\n                'delivery_percentage', 0.85,\r\n                'calculated_earning', v_delivery_earning\r\n            )\r\n        );\r\n        \r\n        -- 5) Margen de plataforma por delivery (15% del fee)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_platform_revenue_account_id,\r\n            'PLATFORM_DELIVERY_MARGIN',\r\n            v_platform_delivery_margin,\r\n            NEW.id,\r\n            'Margen plataforma delivery (15%) pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'delivery_fee', NEW.delivery_fee,\r\n                'platform_percentage', 0.15,\r\n                'calculated_margin', v_platform_delivery_margin\r\n            )\r\n        );\r\n        \r\n        -- 6) Balance cero: efectivo recolectado (negativo en platform_payables)\r\n        INSERT INTO public.account_transactions (\r\n            account_id, type, amount, order_id, description, metadata\r\n        ) VALUES (\r\n            v_platform_payables_account_id,\r\n            'CASH_COLLECTED',\r\n            -NEW.total_amount,\r\n            NEW.id,\r\n            'Efectivo recolectado pedido #' || NEW.id::text,\r\n            jsonb_build_object(\r\n                'order_id', NEW.id,\r\n                'total', NEW.total_amount,\r\n                'collected_by_delivery', true\r\n            )\r\n        );\r\n        \r\n        RAISE NOTICE '✅ Payment processing completed for order %', NEW.id;\r\n        \r\n    END IF;\r\n    \r\n    RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "record_client_debt",
    "function_source": "CREATE OR REPLACE FUNCTION public.record_client_debt(p_user_id uuid, p_amount numeric, p_reason text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_client_account uuid;\r\n  v_platform_payables uuid;\r\n  v_now timestamptz := now();\r\nBEGIN\r\n  IF p_amount IS NULL OR p_amount <= 0 THEN\r\n    RAISE EXCEPTION 'Amount must be > 0';\r\n  END IF;\r\n\r\n  -- Asegurar que el cliente tiene perfil/cuenta\r\n  PERFORM public.ensure_client_profile_and_account(p_user_id);\r\n\r\n  SELECT id INTO v_client_account\r\n  FROM public.accounts\r\n  WHERE user_id = p_user_id\r\n  ORDER BY (account_type = 'client') DESC\r\n  LIMIT 1;\r\n\r\n  -- Resolver cuenta flotante de plataforma\r\n  SELECT id INTO v_platform_payables\r\n  FROM public.accounts\r\n  WHERE account_type = 'platform_payables'\r\n  LIMIT 1;\r\n\r\n  IF v_platform_payables IS NULL THEN\r\n    -- Fallback por user_id seeded (según scripts 50/76/77/79/83/84)\r\n    SELECT id INTO v_platform_payables FROM public.accounts\r\n    WHERE user_id = '00000000-0000-0000-0000-000000000002'::uuid\r\n    LIMIT 1;\r\n  END IF;\r\n\r\n  IF v_client_account IS NULL OR v_platform_payables IS NULL THEN\r\n    RAISE EXCEPTION 'No se pudieron resolver cuentas (client/platform_payables)';\r\n  END IF;\r\n\r\n  -- Asiento doble (mantiene Balance 0)\r\n  INSERT INTO public.account_transactions(account_id, type, amount, description, created_at)\r\n  VALUES (v_client_account, 'CLIENT_DEBT', -p_amount, COALESCE(p_reason,'Deuda de cliente'), v_now);\r\n\r\n  INSERT INTO public.account_transactions(account_id, type, amount, description, created_at)\r\n  VALUES (v_platform_payables, 'CLIENT_DEBT', p_amount, COALESCE(p_reason,'Deuda de cliente (plataforma)'), v_now);\r\n\r\n  -- Recalcular balances\r\n  UPDATE public.accounts a SET balance = COALESCE( (\r\n    SELECT SUM(amount) FROM public.account_transactions t WHERE t.account_id = a.id\r\n  ), 0)\r\n  WHERE a.id IN (v_client_account, v_platform_payables);\r\n\r\n  RETURN jsonb_build_object('success', true);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_amount numeric, p_reason text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_client",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_client(p_email text, p_password text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'auth'\nAS $function$\r\nDECLARE\r\n  v_user_id uuid;\r\n  v_result jsonb;\r\nBEGIN\r\n  -- 1) Crear usuario en auth.users (Supabase maneja esto automáticamente con signUp)\r\n  -- Para este RPC, asumimos que el usuario YA está creado en auth.users\r\n  -- y simplemente tomamos auth.uid()\r\n  v_user_id := auth.uid();\r\n  \r\n  IF v_user_id IS NULL THEN\r\n    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';\r\n  END IF;\r\n\r\n  -- 2) Insertar en public.users\r\n  INSERT INTO public.users (\r\n    id, \r\n    email, \r\n    name, \r\n    phone, \r\n    role,\r\n    email_confirm,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    v_user_id,\r\n    COALESCE(p_email, ''),\r\n    p_name,\r\n    p_phone,\r\n    'cliente',\r\n    false,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = COALESCE(EXCLUDED.email, public.users.email),\r\n    name = COALESCE(EXCLUDED.name, public.users.name),\r\n    phone = COALESCE(EXCLUDED.phone, public.users.phone),\r\n    role = 'cliente',\r\n    updated_at = now();\r\n\r\n  -- 3) Insertar en client_profiles\r\n  INSERT INTO public.client_profiles (\r\n    user_id,\r\n    address,\r\n    lat,\r\n    lon,\r\n    address_structured,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    v_user_id,\r\n    p_address,\r\n    p_lat,\r\n    p_lon,\r\n    p_address_structured,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET\r\n    address = COALESCE(EXCLUDED.address, public.client_profiles.address),\r\n    lat = COALESCE(EXCLUDED.lat, public.client_profiles.lat),\r\n    lon = COALESCE(EXCLUDED.lon, public.client_profiles.lon),\r\n    address_structured = COALESCE(EXCLUDED.address_structured, public.client_profiles.address_structured),\r\n    updated_at = now();\r\n\r\n  -- 4) Crear preferencias de usuario\r\n  INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n  VALUES (v_user_id, now(), now())\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  -- 5) Retornar resultado\r\n  v_result := jsonb_build_object(\r\n    'success', true,\r\n    'user_id', v_user_id,\r\n    'role', 'cliente',\r\n    'message', 'Cliente registrado exitosamente'\r\n  );\r\n\r\n  RETURN v_result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text, p_password text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_delivery_agent",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_delivery_agent(p_email text, p_password text, p_name text, p_phone text DEFAULT NULL::text, p_vehicle_type text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'auth'\nAS $function$\r\nDECLARE\r\n  v_user_id uuid;\r\n  v_result jsonb;\r\nBEGIN\r\n  -- 1) Obtener user_id de auth\r\n  v_user_id := auth.uid();\r\n  \r\n  IF v_user_id IS NULL THEN\r\n    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';\r\n  END IF;\r\n\r\n  -- 2) Insertar en public.users\r\n  INSERT INTO public.users (\r\n    id, \r\n    email, \r\n    name, \r\n    phone, \r\n    role,\r\n    email_confirm,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    v_user_id,\r\n    COALESCE(p_email, ''),\r\n    p_name,\r\n    p_phone,\r\n    'repartidor',\r\n    false,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = COALESCE(EXCLUDED.email, public.users.email),\r\n    name = COALESCE(EXCLUDED.name, public.users.name),\r\n    phone = COALESCE(EXCLUDED.phone, public.users.phone),\r\n    role = 'repartidor',\r\n    updated_at = now();\r\n\r\n  -- 3) Insertar en delivery_agent_profiles\r\n  INSERT INTO public.delivery_agent_profiles (\r\n    user_id,\r\n    vehicle_type,\r\n    status,\r\n    account_state,\r\n    onboarding_completed,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    v_user_id,\r\n    p_vehicle_type,\r\n    'pending',\r\n    'pending',\r\n    false,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET\r\n    vehicle_type = COALESCE(EXCLUDED.vehicle_type, public.delivery_agent_profiles.vehicle_type),\r\n    updated_at = now();\r\n\r\n  -- 4) Crear preferencias de usuario\r\n  INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n  VALUES (v_user_id, now(), now())\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  -- 5) Crear cuenta financiera del repartidor\r\n  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (gen_random_uuid(), v_user_id, 'delivery_agent', 0.00, now(), now())\r\n  ON CONFLICT DO NOTHING;\r\n\r\n  -- 6) Crear notificación para admins\r\n  INSERT INTO public.admin_notifications (\r\n    target_role,\r\n    category,\r\n    entity_type,\r\n    entity_id,\r\n    title,\r\n    message,\r\n    metadata,\r\n    created_at\r\n  ) VALUES (\r\n    'admin',\r\n    'registration',\r\n    'delivery_agent',\r\n    v_user_id,\r\n    'Nuevo repartidor registrado',\r\n    'El repartidor \"' || p_name || '\" ha solicitado registro.',\r\n    jsonb_build_object(\r\n      'name', p_name,\r\n      'phone', p_phone,\r\n      'email', p_email,\r\n      'vehicle_type', p_vehicle_type\r\n    ),\r\n    now()\r\n  );\r\n\r\n  -- 7) Retornar resultado\r\n  v_result := jsonb_build_object(\r\n    'success', true,\r\n    'user_id', v_user_id,\r\n    'role', 'repartidor',\r\n    'message', 'Repartidor registrado exitosamente. Pendiente de aprobación.'\r\n  );\r\n\r\n  RETURN v_result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text, p_password text, p_name text, p_phone text DEFAULT NULL::text, p_vehicle_type text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_delivery_agent_atomic",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(p_user_id uuid, p_email text, p_name text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_vehicle_type text DEFAULT 'motocicleta'::text, p_vehicle_plate text DEFAULT ''::text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_delivery_agent_id uuid;\r\n  v_account_id uuid;\r\n  v_now timestamptz := now();\r\nBEGIN\r\n  -- Validar que el auth.user existe\r\n  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'data', NULL,\r\n      'error', 'auth.user does not exist'\r\n    );\r\n  END IF;\r\n\r\n  -- 1) LIMPIAR cualquier perfil/cuenta de cliente creado por trigger o error anterior\r\n  DELETE FROM public.client_profiles WHERE user_id = p_user_id;\r\n  DELETE FROM public.accounts WHERE user_id = p_user_id AND account_type = 'client';\r\n\r\n  -- 2) CREAR/ACTUALIZAR usuario en public.users con role='delivery_agent'\r\n  INSERT INTO public.users (\r\n    id, \r\n    email, \r\n    name, \r\n    phone, \r\n    address, \r\n    role, \r\n    lat, \r\n    lon, \r\n    address_structured, \r\n    email_confirm,\r\n    created_at, \r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id,\r\n    p_email,\r\n    p_name,\r\n    COALESCE(p_phone, ''),\r\n    COALESCE(p_address, ''),\r\n    'delivery_agent',  -- ⭐ ROLE FORZADO\r\n    p_lat,\r\n    p_lon,\r\n    p_address_structured,\r\n    false,\r\n    v_now,\r\n    v_now\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n    SET email = EXCLUDED.email,\r\n        name = EXCLUDED.name,\r\n        phone = EXCLUDED.phone,\r\n        address = EXCLUDED.address,\r\n        role = 'delivery_agent',  -- ⭐ SIEMPRE forzar delivery_agent\r\n        lat = EXCLUDED.lat,\r\n        lon = EXCLUDED.lon,\r\n        address_structured = EXCLUDED.address_structured,\r\n        updated_at = v_now;\r\n\r\n  -- 3) CREAR delivery_agent_profiles (con RETURNING para capturar el ID)\r\n  INSERT INTO public.delivery_agent_profiles (\r\n    user_id,\r\n    profile_image_url,\r\n    id_document_front_url,\r\n    id_document_back_url,\r\n    vehicle_type,\r\n    vehicle_plate,\r\n    vehicle_model,\r\n    vehicle_color,\r\n    vehicle_registration_url,\r\n    vehicle_insurance_url,\r\n    vehicle_photo_url,\r\n    emergency_contact_name,\r\n    emergency_contact_phone,\r\n    status,\r\n    account_state,\r\n    onboarding_completed,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id,\r\n    p_profile_image_url,\r\n    p_id_document_front_url,\r\n    p_id_document_back_url,\r\n    COALESCE(p_vehicle_type, 'motocicleta'),\r\n    COALESCE(p_vehicle_plate, ''),\r\n    p_vehicle_model,\r\n    p_vehicle_color,\r\n    p_vehicle_registration_url,\r\n    p_vehicle_insurance_url,\r\n    p_vehicle_photo_url,\r\n    p_emergency_contact_name,\r\n    p_emergency_contact_phone,\r\n    'pending',        -- Estado inicial: pendiente de aprobación\r\n    'pending',        -- Account state: pendiente\r\n    false,            -- Onboarding no completado aún\r\n    v_now,\r\n    v_now\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE\r\n    SET profile_image_url = EXCLUDED.profile_image_url,\r\n        id_document_front_url = EXCLUDED.id_document_front_url,\r\n        id_document_back_url = EXCLUDED.id_document_back_url,\r\n        vehicle_type = EXCLUDED.vehicle_type,\r\n        vehicle_plate = EXCLUDED.vehicle_plate,\r\n        vehicle_model = EXCLUDED.vehicle_model,\r\n        vehicle_color = EXCLUDED.vehicle_color,\r\n        vehicle_registration_url = EXCLUDED.vehicle_registration_url,\r\n        vehicle_insurance_url = EXCLUDED.vehicle_insurance_url,\r\n        vehicle_photo_url = EXCLUDED.vehicle_photo_url,\r\n        emergency_contact_name = EXCLUDED.emergency_contact_name,\r\n        emergency_contact_phone = EXCLUDED.emergency_contact_phone,\r\n        updated_at = v_now\r\n  RETURNING user_id INTO v_delivery_agent_id;\r\n\r\n  -- 4) CREAR cuenta financiera tipo 'delivery_agent'\r\n  INSERT INTO public.accounts (\r\n    user_id, \r\n    account_type, \r\n    balance, \r\n    created_at, \r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id, \r\n    'delivery_agent', \r\n    0.0, \r\n    v_now, \r\n    v_now\r\n  )\r\n  ON CONFLICT (user_id, account_type) DO UPDATE\r\n    SET updated_at = v_now\r\n  RETURNING id INTO v_account_id;\r\n\r\n  -- 5) CREAR user_preferences (sin restaurant_id para delivery agents)\r\n  INSERT INTO public.user_preferences (\r\n    user_id, \r\n    has_seen_onboarding,\r\n    created_at, \r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id, \r\n    false,\r\n    v_now, \r\n    v_now\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE\r\n    SET updated_at = v_now;\r\n\r\n  -- 6) RETORNAR éxito con todos los IDs\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'data', jsonb_build_object(\r\n      'user_id', p_user_id,\r\n      'delivery_agent_id', v_delivery_agent_id,\r\n      'account_id', v_account_id,\r\n      'role', 'delivery_agent'\r\n    ),\r\n    'error', NULL\r\n  );\r\n\r\nEXCEPTION WHEN OTHERS THEN\r\n  -- Retornar error detallado\r\n  RETURN jsonb_build_object(\r\n    'success', false,\r\n    'data', NULL,\r\n    'error', SQLERRM\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_vehicle_type text DEFAULT 'motocicleta'::text, p_vehicle_plate text DEFAULT ''::text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_restaurant",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_restaurant(p_email text, p_password text, p_restaurant_name text, p_contact_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'auth'\nAS $function$\r\nDECLARE\r\n  v_user_id uuid;\r\n  v_restaurant_id uuid;\r\n  v_result jsonb;\r\nBEGIN\r\n  -- 1) Obtener user_id de auth\r\n  v_user_id := auth.uid();\r\n  \r\n  IF v_user_id IS NULL THEN\r\n    RAISE EXCEPTION 'Usuario no autenticado. Debes llamar a auth.signUp primero.';\r\n  END IF;\r\n\r\n  -- 2) Insertar en public.users\r\n  INSERT INTO public.users (\r\n    id, \r\n    email, \r\n    name, \r\n    phone, \r\n    role,\r\n    email_confirm,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    v_user_id,\r\n    COALESCE(p_email, ''),\r\n    p_contact_name,\r\n    p_phone,\r\n    'restaurante',\r\n    false,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = COALESCE(EXCLUDED.email, public.users.email),\r\n    name = COALESCE(EXCLUDED.name, public.users.name),\r\n    phone = COALESCE(EXCLUDED.phone, public.users.phone),\r\n    role = 'restaurante',\r\n    updated_at = now();\r\n\r\n  -- 3) Insertar en restaurants\r\n  INSERT INTO public.restaurants (\r\n    id,\r\n    user_id,\r\n    name,\r\n    description,\r\n    address,\r\n    phone,\r\n    location_lat,\r\n    location_lon,\r\n    address_structured,\r\n    status,\r\n    online,\r\n    onboarding_completed,\r\n    onboarding_step,\r\n    profile_completion_percentage,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    gen_random_uuid(),\r\n    v_user_id,\r\n    p_restaurant_name,\r\n    '',\r\n    p_address,\r\n    p_phone,\r\n    p_location_lat,\r\n    p_location_lon,\r\n    p_address_structured,\r\n    'pending',\r\n    false,\r\n    false,\r\n    0,\r\n    0,\r\n    now(),\r\n    now()\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET\r\n    name = COALESCE(EXCLUDED.name, public.restaurants.name),\r\n    address = COALESCE(EXCLUDED.address, public.restaurants.address),\r\n    phone = COALESCE(EXCLUDED.phone, public.restaurants.phone),\r\n    location_lat = COALESCE(EXCLUDED.location_lat, public.restaurants.location_lat),\r\n    location_lon = COALESCE(EXCLUDED.location_lon, public.restaurants.location_lon),\r\n    address_structured = COALESCE(EXCLUDED.address_structured, public.restaurants.address_structured),\r\n    updated_at = now()\r\n  RETURNING id INTO v_restaurant_id;\r\n\r\n  -- 4) Crear preferencias de usuario\r\n  INSERT INTO public.user_preferences (user_id, restaurant_id, created_at, updated_at)\r\n  VALUES (v_user_id, v_restaurant_id, now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET restaurant_id = v_restaurant_id;\r\n\r\n  -- 5) Crear cuenta financiera del restaurante\r\n  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (gen_random_uuid(), v_user_id, 'restaurant', 0.00, now(), now())\r\n  ON CONFLICT DO NOTHING;\r\n\r\n  -- 6) Crear notificación para admins\r\n  INSERT INTO public.admin_notifications (\r\n    target_role,\r\n    category,\r\n    entity_type,\r\n    entity_id,\r\n    title,\r\n    message,\r\n    metadata,\r\n    created_at\r\n  ) VALUES (\r\n    'admin',\r\n    'registration',\r\n    'restaurant',\r\n    v_user_id,\r\n    'Nuevo restaurante registrado',\r\n    'El restaurante \"' || p_restaurant_name || '\" ha solicitado registro.',\r\n    jsonb_build_object(\r\n      'restaurant_name', p_restaurant_name,\r\n      'contact_name', p_contact_name,\r\n      'phone', p_phone,\r\n      'email', p_email\r\n    ),\r\n    now()\r\n  );\r\n\r\n  -- 7) Retornar resultado\r\n  v_result := jsonb_build_object(\r\n    'success', true,\r\n    'user_id', v_user_id,\r\n    'restaurant_id', v_restaurant_id,\r\n    'role', 'restaurante',\r\n    'message', 'Restaurante registrado exitosamente. Pendiente de aprobación.'\r\n  );\r\n\r\n  RETURN v_result;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text, p_password text, p_restaurant_name text, p_contact_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_restaurant_v2",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_restaurant_v2(p_user_id uuid, p_email text, p_restaurant_name text, p_name text, p_phone text, p_address text, p_address_structured jsonb, p_location_lat double precision, p_location_lon double precision, p_location_place_id text)\n RETURNS jsonb\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n  v_restaurant_id uuid;\r\n  v_account_id uuid;\r\nBEGIN\r\n  -- 1) ensure user profile\r\n  -- AHORA USA p_name PARA EL NOMBRE DEL PERFIL, COMO DEBE SER\r\n  PERFORM public.ensure_user_profile_public(\r\n    p_user_id => p_user_id,\r\n    p_email => p_email,\r\n    p_name => p_name, -- CORREGIDO\r\n    p_role => 'restaurant',\r\n    p_phone => p_phone,\r\n    p_address => p_address,\r\n    p_lat => p_location_lat,\r\n    p_lon => p_location_lon,\r\n    p_address_structured => p_address_structured\r\n  );\r\n\r\n  -- 2) create restaurant if missing\r\n  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id LIMIT 1;\r\n  IF v_restaurant_id IS NULL THEN\r\n    INSERT INTO public.restaurants (\r\n      user_id, name, status, location_lat, location_lon, location_place_id, address, address_structured, phone, online, created_at, updated_at\r\n    ) VALUES (\r\n      p_user_id, p_restaurant_name, 'pending', p_location_lat, p_location_lon, p_location_place_id, p_address, p_address_structured, p_phone, false, now(), now()\r\n    ) RETURNING id INTO v_restaurant_id;\r\n  END IF;\r\n\r\n  -- 3) ensure financial account for restaurant\r\n  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (p_user_id, 'restaurant', 0.0, now(), now())\r\n  ON CONFLICT (user_id, account_type) DO UPDATE\r\n    SET updated_at = EXCLUDED.updated_at\r\n  RETURNING id INTO v_account_id;\r\n\r\n  -- 4) ensure user_preferences row with restaurant_id (idempotent)\r\n  INSERT INTO public.user_preferences (user_id, restaurant_id, created_at, updated_at)\r\n  VALUES (p_user_id, v_restaurant_id, now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE\r\n    SET restaurant_id = COALESCE(public.user_preferences.restaurant_id, EXCLUDED.restaurant_id),\r\n        updated_at = now();\r\n\r\n  -- 5) normalize role to restaurant if needed\r\n  UPDATE public.users SET role = 'restaurant', updated_at = now()\r\n  WHERE id = p_user_id AND COALESCE(role,'') IN ('', 'client', 'cliente');\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'data', jsonb_build_object('user_id', p_user_id, 'restaurant_id', v_restaurant_id, 'account_id', v_account_id),\r\n    'error', NULL\r\n  );\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_restaurant_name text, p_name text, p_phone text, p_address text, p_address_structured jsonb, p_location_lat double precision, p_location_lon double precision, p_location_place_id text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "register_restaurant_v2",
    "function_source": "CREATE OR REPLACE FUNCTION public.register_restaurant_v2(p_user_id uuid, p_email text, p_restaurant_name text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_location_place_id text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_restaurant_id uuid;\r\n  v_account_id uuid;\r\nBEGIN\r\n  -- 1) ensure user profile\r\n  PERFORM public.ensure_user_profile_public(\r\n    p_user_id => p_user_id,\r\n    p_email => p_email,\r\n    p_name => COALESCE(p_restaurant_name, ''),\r\n    p_role => 'restaurant',\r\n    p_phone => p_phone,\r\n    p_address => p_address,\r\n    p_lat => p_location_lat,\r\n    p_lon => p_location_lon,\r\n    p_address_structured => p_address_structured\r\n  );\r\n\r\n  -- 2) create restaurant if missing\r\n  SELECT id INTO v_restaurant_id FROM public.restaurants WHERE user_id = p_user_id LIMIT 1;\r\n  IF v_restaurant_id IS NULL THEN\r\n    INSERT INTO public.restaurants (\r\n      user_id, name, status, location_lat, location_lon, location_place_id, address, address_structured, phone, online, created_at, updated_at\r\n    ) VALUES (\r\n      p_user_id, p_restaurant_name, 'pending', p_location_lat, p_location_lon, p_location_place_id, p_address, p_address_structured, p_phone, false, now(), now()\r\n    ) RETURNING id INTO v_restaurant_id;\r\n  END IF;\r\n\r\n  -- 3) ensure financial account for restaurant\r\n  INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (p_user_id, 'restaurant', 0.0, now(), now())\r\n  ON CONFLICT (user_id, account_type) DO UPDATE\r\n    SET updated_at = EXCLUDED.updated_at\r\n  RETURNING id INTO v_account_id;\r\n\r\n  -- 4) ensure user_preferences row with restaurant_id (idempotent)\r\n  --    Do not overwrite restaurant_id if it already exists; only set when NULL.\r\n  INSERT INTO public.user_preferences (user_id, restaurant_id, created_at, updated_at)\r\n  VALUES (p_user_id, v_restaurant_id, now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE\r\n    SET restaurant_id = COALESCE(public.user_preferences.restaurant_id, EXCLUDED.restaurant_id),\r\n        updated_at = now();\r\n\r\n  -- 5) normalize role to restaurant if needed\r\n  UPDATE public.users SET role = 'restaurant', updated_at = now()\r\n  WHERE id = p_user_id AND COALESCE(role,'') IN ('', 'client', 'cliente');\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'data', jsonb_build_object('user_id', p_user_id, 'restaurant_id', v_restaurant_id, 'account_id', v_account_id),\r\n    'error', NULL\r\n  );\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_email text, p_restaurant_name text, p_phone text DEFAULT ''::text, p_address text DEFAULT ''::text, p_location_lat double precision DEFAULT NULL::double precision, p_location_lon double precision DEFAULT NULL::double precision, p_location_place_id text DEFAULT NULL::text, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "repair_user_registration_misclassification",
    "function_source": "CREATE OR REPLACE FUNCTION public.repair_user_registration_misclassification(p_user_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_has_restaurant boolean;\r\n  v_account_id uuid;\r\nBEGIN\r\n  SELECT EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) INTO v_has_restaurant;\r\n  IF NOT v_has_restaurant THEN\r\n    RETURN jsonb_build_object('success', false, 'error', 'No restaurant for this user');\r\n  END IF;\r\n\r\n  -- Set role and account type\r\n  UPDATE public.users SET role = 'restaurant', updated_at = now() WHERE id = p_user_id;\r\n\r\n  SELECT id INTO v_account_id FROM public.accounts WHERE user_id = p_user_id LIMIT 1;\r\n  IF v_account_id IS NULL THEN\r\n    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n    VALUES (p_user_id, 'restaurant', 0.0, now(), now())\r\n    RETURNING id INTO v_account_id;\r\n  ELSE\r\n    UPDATE public.accounts SET account_type = 'restaurant', updated_at = now() WHERE id = v_account_id;\r\n  END IF;\r\n\r\n  -- Remove client profile if present\r\n  DELETE FROM public.client_profiles WHERE user_id = p_user_id;\r\n\r\n  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_admin_create_settlement",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_admin_create_settlement(p_payer_account_id uuid, p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text, p_auto_complete boolean DEFAULT true)\n RETURNS settlements\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ declare v_row public.settlements; begin if p_amount is null or p_amount <= 0 then raise exception 'Monto inválido'; end if; if p_payer_account_id is null or p_receiver_account_id is null then raise exception 'Cuentas requeridas'; end if; if p_payer_account_id = p_receiver_account_id then raise exception 'Pagador y receptor no pueden ser la misma cuenta'; end if;insert into public.settlements (payer_account_id, receiver_account_id, amount, status, notes, initiated_at) values (p_payer_account_id, p_receiver_account_id, p_amount, 'pending', p_notes, now()) returning * into v_row;if p_auto_complete then update public.settlements set status = 'completed', completed_by = auth.uid(), completed_at = now() where id = v_row.id returning * into v_row; end if;return v_row; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_payer_account_id uuid, p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text, p_auto_complete boolean DEFAULT true",
    "return_type": "settlements"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_create_settlement",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_create_settlement(p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text)\n RETURNS settlements\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ declare v_payer_account_id uuid; v_row public.settlements; v_code text; begin if p_amount is null or p_amount <= 0 then raise exception 'El monto debe ser mayor a cero'; end if; if p_receiver_account_id is null then raise exception 'Cuenta destino requerida'; end if;\r\n-- Resolver cuenta del usuario actual (prioriza tipo delivery, si no, la primera) \r\nselect a.id into v_payer_account_id from public.accounts a where a.user_id = auth.uid() order by case when lower(a.account_type) like 'deliver%' then 0 else 1 end, a.created_at asc limit 1;if v_payer_account_id is null then raise exception 'No se encontró cuenta del pagador'; end if;if v_payer_account_id = p_receiver_account_id then raise exception 'Pagador y receptor no pueden ser la misma cuenta'; end if;\r\n-- Código de confirmación de 8 dígitos \r\nv_code := lpad((floor(random()*1e8))::int::text, 8, '0');insert into public.settlements (payer_account_id, receiver_account_id, amount, status, confirmation_code, notes, initiated_at) values (v_payer_account_id, p_receiver_account_id, p_amount, 'pending', v_code, p_notes, now()) returning * into v_row;return v_row; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_receiver_account_id uuid, p_amount numeric, p_notes text DEFAULT NULL::text",
    "return_type": "settlements"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_get_driver_location_for_order",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_get_driver_location_for_order(p_order_id uuid)\n RETURNS TABLE(lat double precision, lon double precision, updated_at timestamp with time zone)\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ with ord as ( select o.user_id, o.delivery_agent_id from public.orders o where o.id = p_order_id limit 1 ), guard as ( \r\n  -- Restricción básica: solo el cliente dueño, el repartidor asignado o roles admin/restaurant pueden leer \r\n  select 1 from ord join public.users me on me.id = auth.uid() where me.role in ('admin','restaurant') or me.id in (ord.user_id, ord.delivery_agent_id) ) select ST_Y(u.current_location::geometry) as lat, ST_X(u.current_location::geometry) as lon, u.updated_at from ord join public.users u on u.id = ord.delivery_agent_id where ord.delivery_agent_id is not null and u.current_location is not null and exists (select 1 from guard); $function$\n",
    "volatility": "STABLE",
    "arguments": "p_order_id uuid",
    "return_type": "TABLE(lat double precision, lon double precision, updated_at timestamp with time zone)"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_get_restaurant_account_id",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_get_restaurant_account_id(p_user_id uuid)\n RETURNS uuid\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ select a.id from public.accounts a where a.user_id = p_user_id and lower(a.account_type) like 'restaur%' order by a.created_at asc limit 1; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid",
    "return_type": "uuid"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_get_settlement_code",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_get_settlement_code(p_settlement_id uuid)\n RETURNS text\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ declare v_code text; v_receiver_account_id uuid; v_is_admin boolean := false; begin select s.confirmation_code, s.receiver_account_id into v_code, v_receiver_account_id from public.settlements s where s.id = p_settlement_id;\r\nif v_code is null then raise exception 'Settlement not found'; end if;\r\n-- admin/platform (opcional, según tu modelo) \r\nselect exists(select 1 from public.users u where u.id = auth.uid() and u.role in ('admin','platform')) into v_is_admin;\r\n-- Receiver puede ver el código \r\nif exists( select 1 from public.accounts a where a.id = v_receiver_account_id and a.user_id = auth.uid() ) or v_is_admin then return v_code; end if;\r\nraise exception 'Not authorized to view code'; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_settlement_id uuid",
    "return_type": "text"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_get_user_location",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_get_user_location(p_user_id uuid)\n RETURNS TABLE(lat double precision, lon double precision, updated_at timestamp with time zone)\n LANGUAGE sql\n STABLE SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ select ST_Y(current_location::geometry)::double precision as lat, ST_X(current_location::geometry)::double precision as lon, updated_at from public.users where id = p_user_id limit 1; $function$\n",
    "volatility": "STABLE",
    "arguments": "p_user_id uuid",
    "return_type": "TABLE(lat double precision, lon double precision, updated_at timestamp with time zone)"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_initiate_restaurant_settlement",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_initiate_restaurant_settlement(p_amount double precision, p_notes text DEFAULT NULL::text)\n RETURNS json\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ DECLARE v_restaurant_acc_id uuid; v_platform_acc_id uuid; v_code text; v_hash bytea; v_settlement_id uuid; BEGIN IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Monto inválido'; END IF;\r\n-- Cuenta del restaurante del usuario actual \r\nSELECT a.id INTO v_restaurant_acc_id FROM public.accounts a WHERE a.user_id = auth.uid() AND lower(a.account_type) LIKE 'restaur%' ORDER BY a.created_at ASC LIMIT 1;IF v_restaurant_acc_id IS NULL THEN RAISE EXCEPTION 'No se encontró cuenta del restaurante para el usuario'; END IF;\r\n-- Cuenta de plataforma vía helper (security definer) \r\nv_platform_acc_id := public.rpc_get_platform_account_id(); IF v_platform_acc_id IS NULL THEN RAISE EXCEPTION 'No se encontró cuenta de plataforma'; END IF;\r\n-- Código de 6 dígitos con ceros a la izquierda \r\nv_code := lpad((floor(random()*1000000))::int::text, 6, '0');\r\n-- Hash correcto usando la extensión explícitamente \r\nv_hash := extensions.digest(convert_to(v_code, 'UTF8'), 'sha256');v_settlement_id := extensions.gen_random_uuid();INSERT INTO public.settlements ( id, payer_account_id, receiver_account_id, amount, status, initiated_by, initiated_at, notes, confirmation_code, code_hash ) VALUES ( v_settlement_id, v_restaurant_acc_id, v_platform_acc_id, round(p_amount::numeric, 2), 'pending', auth.uid(), now(), NULLIF(p_notes, ''), v_code, v_hash );RETURN json_build_object( 'settlement_id', v_settlement_id, 'plain_code', v_code ); END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_amount double precision, p_notes text DEFAULT NULL::text",
    "return_type": "json"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_list_restaurants_with_debt_for_delivery",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_list_restaurants_with_debt_for_delivery(p_delivery_account_id uuid)\n RETURNS TABLE(restaurant_user_id uuid, account_id uuid, name text, amount_due numeric)\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ declare v_delivery_user_id uuid; begin \r\n-- Resolver user_id del repartidor a partir de su account_id \r\nselect a.user_id into v_delivery_user_id from public.accounts a where a.id = p_delivery_account_id;if v_delivery_user_id is null then return; end if;return query with r as ( select r.user_id as restaurant_user_id, r.name as name, (select a.id from public.accounts a where a.user_id = r.user_id and lower(a.account_type) like 'restaur%' order by a.created_at asc limit 1) as account_id from public.restaurants r ), cash_orders as ( select o.restaurant_id, sum(coalesce(o.total_amount, 0))::numeric as total_cash from public.orders o where o.delivery_agent_id = v_delivery_user_id and o.status = 'delivered' and o.payment_method = 'cash' group by o.restaurant_id ), settled as ( select ar.user_id as restaurant_user_id, sum(coalesce(s.amount, 0))::numeric as total_settled from public.settlements s join public.accounts ad on ad.id = s.payer_account_id   \r\n-- cuenta del repartidor \r\njoin public.accounts ar on ar.id = s.receiver_account_id \r\n-- cuenta del restaurante \r\nwhere ad.user_id = v_delivery_user_id and lower(ar.account_type) like 'restaur%' and s.status = 'completed' group by ar.user_id ) select r.restaurant_user_id, r.account_id, r.name, greatest(coalesce(co.total_cash, 0) - coalesce(st.total_settled, 0), 0) as amount_due from r left join public.restaurants rr on rr.user_id = r.restaurant_user_id left join cash_orders co on co.restaurant_id = rr.id left join settled st on st.restaurant_user_id = r.restaurant_user_id where greatest(coalesce(co.total_cash, 0) - coalesce(st.total_settled, 0), 0) > 0 order by amount_due desc, r.name asc; end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_delivery_account_id uuid",
    "return_type": "TABLE(restaurant_user_id uuid, account_id uuid, name text, amount_due numeric)"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_post_client_default",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_post_client_default(p_order_id uuid, p_reason text DEFAULT 'Falla de Cliente'::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_order RECORD;\r\n  v_restaurant_account uuid;\r\n  v_delivery_account uuid;\r\n  v_client_account uuid;\r\n  v_platform_revenue uuid;\r\n  v_subtotal numeric;\r\n  v_commission numeric;\r\n  v_restaurant_net numeric;\r\n  v_delivery_earning numeric;\r\n  v_platform_delivery_margin numeric;\r\n  v_now timestamptz := now();\r\n  v_status_changed boolean := false;\r\n  v_commission_bps integer;\r\n  v_commission_rate numeric;\r\nBEGIN\r\n  SELECT o.*, COALESCE(r.commission_bps, 1500) AS c_bps\r\n  INTO v_order\r\n  FROM public.orders o\r\n  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id\r\n  WHERE o.id = p_order_id;\r\n  IF NOT FOUND THEN RAISE EXCEPTION 'Orden % no existe', p_order_id; END IF;\r\n\r\n  -- Idempotency: skip if already posted client_default for this order\r\n  IF EXISTS (\r\n    SELECT 1 FROM public.account_transactions \r\n    WHERE order_id = p_order_id AND (metadata ->> 'reason') = 'client_default'\r\n  ) THEN\r\n    RETURN jsonb_build_object('success', true, 'skipped', true, 'message', 'Asientos ya creados previamente');\r\n  END IF;\r\n\r\n  -- Resolve accounts\r\n  SELECT a.id INTO v_restaurant_account\r\n  FROM public.accounts a JOIN public.restaurants r ON r.user_id = a.user_id\r\n  WHERE r.id = v_order.restaurant_id AND a.account_type = 'restaurant'\r\n  ORDER BY a.created_at ASC LIMIT 1;\r\n\r\n  SELECT a.id INTO v_delivery_account FROM public.accounts a \r\n  WHERE a.user_id = v_order.delivery_agent_id AND a.account_type = 'delivery_agent'\r\n  ORDER BY a.created_at ASC LIMIT 1;\r\n\r\n  PERFORM public.ensure_client_profile_and_account(v_order.user_id);\r\n  SELECT id INTO v_client_account FROM public.accounts WHERE user_id = v_order.user_id AND account_type = 'client' LIMIT 1;\r\n\r\n  SELECT id INTO v_platform_revenue FROM public.accounts WHERE account_type = 'platform_revenue' ORDER BY created_at ASC LIMIT 1;\r\n\r\n  IF v_restaurant_account IS NULL OR v_delivery_account IS NULL OR v_client_account IS NULL OR v_platform_revenue IS NULL THEN\r\n    RAISE EXCEPTION 'No se pudieron resolver cuentas necesarias (restaurante/repartidor/cliente/plataforma)';\r\n  END IF;\r\n\r\n  v_subtotal := COALESCE(v_order.total_amount, 0) - COALESCE(v_order.delivery_fee, 0);\r\n  v_commission_bps := COALESCE(v_order.c_bps, 1500);\r\n  v_commission_rate := v_commission_bps::numeric / 10000.0;\r\n  v_commission := ROUND(v_subtotal * v_commission_rate, 2);\r\n  v_restaurant_net := v_subtotal - v_commission;\r\n  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);\r\n  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;\r\n\r\n  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)\r\n  VALUES (\r\n    v_restaurant_account,\r\n    'ORDER_REVENUE',\r\n    v_restaurant_net,\r\n    p_order_id,\r\n    format('Ingreso neto (comisión %s) - Orden #%%s', public._fmt_pct(v_commission_rate))::text || LEFT(p_order_id::text, 8),\r\n    jsonb_build_object('reason','client_default','subtotal', v_subtotal, 'commission', v_commission, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps),\r\n    v_now\r\n  );\r\n\r\n  IF v_delivery_earning > 0 THEN\r\n    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)\r\n    VALUES (\r\n      v_delivery_account,\r\n      'DELIVERY_EARNING',\r\n      v_delivery_earning,\r\n      p_order_id,\r\n      format('Ganancia delivery por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),\r\n      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),\r\n      v_now\r\n    );\r\n  END IF;\r\n\r\n  INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)\r\n  VALUES (\r\n    v_client_account,\r\n    'CLIENT_DEBT',\r\n    -COALESCE(v_order.total_amount, 0),\r\n    p_order_id,\r\n    format('Deuda por falla de cliente - Orden #%s', LEFT(p_order_id::text, 8)),\r\n    jsonb_build_object('reason','client_default'),\r\n    v_now\r\n  );\r\n\r\n  IF v_commission > 0 THEN\r\n    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)\r\n    VALUES (\r\n      v_platform_revenue,\r\n      'PLATFORM_COMMISSION',\r\n      v_commission,\r\n      p_order_id,\r\n      format('Comisión %s - Orden #%s', public._fmt_pct(v_commission_rate), LEFT(p_order_id::text, 8)),\r\n      jsonb_build_object('reason','client_default','subtotal', v_subtotal, 'commission_rate', v_commission_rate, 'commission_bps', v_commission_bps),\r\n      v_now\r\n    );\r\n  END IF;\r\n\r\n  IF v_platform_delivery_margin > 0 THEN\r\n    INSERT INTO public.account_transactions(account_id, type, amount, order_id, description, metadata, created_at)\r\n    VALUES (\r\n      v_platform_revenue,\r\n      'PLATFORM_DELIVERY_MARGIN',\r\n      v_platform_delivery_margin,\r\n      p_order_id,\r\n      format('Margen delivery - Orden #%s', LEFT(p_order_id::text, 8)),\r\n      jsonb_build_object('reason','client_default','delivery_fee', v_order.delivery_fee),\r\n      v_now\r\n    );\r\n  END IF;\r\n\r\n  PERFORM public.rpc_recompute_account_balance(v_restaurant_account);\r\n  PERFORM public.rpc_recompute_account_balance(v_delivery_account);\r\n  PERFORM public.rpc_recompute_account_balance(v_client_account);\r\n  PERFORM public.rpc_recompute_account_balance(v_platform_revenue);\r\n\r\n  IF v_order.status <> 'canceled' THEN\r\n    UPDATE public.orders SET status = 'canceled', updated_at = v_now WHERE id = p_order_id;\r\n    v_status_changed := true;\r\n  END IF;\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'order_id', p_order_id,\r\n    'posted', 5,\r\n    'order_status_marked_canceled', v_status_changed,\r\n    'amounts', jsonb_build_object(\r\n      'subtotal', v_subtotal,\r\n      'commission', v_commission,\r\n      'commission_rate', v_commission_rate,\r\n      'commission_bps', v_commission_bps,\r\n      'restaurant_net', v_restaurant_net,\r\n      'delivery_earning', v_delivery_earning,\r\n      'platform_delivery_margin', v_platform_delivery_margin,\r\n      'client_debt', COALESCE(v_order.total_amount,0)\r\n    )\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_order_id uuid, p_reason text DEFAULT 'Falla de Cliente'::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_preview_order_financials",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_preview_order_financials(p_order_id uuid)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_order RECORD;\r\n  v_subtotal numeric;\r\n  v_commission_bps integer;\r\n  v_commission_rate numeric;\r\n  v_commission numeric;\r\n  v_delivery_earning numeric;\r\n  v_platform_delivery_margin numeric;\r\nBEGIN\r\n  SELECT o.*, COALESCE(r.commission_bps, 1500) AS c_bps\r\n  INTO v_order\r\n  FROM public.orders o\r\n  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id\r\n  WHERE o.id = p_order_id;\r\n\r\n  IF NOT FOUND THEN\r\n    RETURN jsonb_build_object('success', false, 'error', 'Order not found');\r\n  END IF;\r\n\r\n  v_subtotal := COALESCE(v_order.total_amount,0) - COALESCE(v_order.delivery_fee,0);\r\n  v_commission_bps := COALESCE(v_order.c_bps, 1500);\r\n  v_commission_rate := v_commission_bps::numeric / 10000.0;\r\n  v_commission := ROUND(v_subtotal * v_commission_rate, 2);\r\n  v_delivery_earning := ROUND(COALESCE(v_order.delivery_fee, 0) * 0.85, 2);\r\n  v_platform_delivery_margin := COALESCE(v_order.delivery_fee, 0) - v_delivery_earning;\r\n\r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'order_id', p_order_id,\r\n    'commission_bps', v_commission_bps,\r\n    'commission_rate', v_commission_rate,\r\n    'subtotal', v_subtotal,\r\n    'commission', v_commission,\r\n    'delivery_earning', v_delivery_earning,\r\n    'platform_delivery_margin', v_platform_delivery_margin\r\n  );\r\nEND; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_order_id uuid",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_set_order_delivery_location",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_set_order_delivery_location(p_order_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text)\n RETURNS void\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ update public.orders set delivery_lat = p_lat, delivery_lon = p_lon, delivery_place_id = p_place_id, updated_at = now() where id = p_order_id; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_order_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_set_restaurant_location",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_set_restaurant_location(p_restaurant_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text)\n RETURNS void\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ update public.restaurants set location_lat = p_lat, location_lon = p_lon, location_place_id = p_place_id, updated_at = now() where id = p_restaurant_id; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_restaurant_id uuid, p_lat double precision, p_lon double precision, p_place_id text DEFAULT NULL::text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "rpc_update_my_location",
    "function_source": "CREATE OR REPLACE FUNCTION public.rpc_update_my_location(lat double precision, lon double precision, heading double precision DEFAULT NULL::double precision)\n RETURNS void\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public', 'extensions'\nAS $function$ update public.users set current_location = ST_SetSRID(ST_MakePoint(lon, lat), 4326)::extensions.geography, current_heading = coalesce(heading, current_heading), updated_at = now() where id = auth.uid(); $function$\n",
    "volatility": "VOLATILE",
    "arguments": "lat double precision, lon double precision, heading double precision DEFAULT NULL::double precision",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "set_delivery_welcome_seen",
    "function_source": "CREATE OR REPLACE FUNCTION public.set_delivery_welcome_seen()\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ begin update public.user_preferences set has_seen_delivery_welcome = true, delivery_welcome_seen_at = now() where user_id = auth.uid(); end; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "set_user_phone_if_missing",
    "function_source": "CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing(p_user_id uuid, p_phone text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_updated boolean := false;\r\nBEGIN\r\n  UPDATE public.users SET phone = p_phone, updated_at = now()\r\n  WHERE id = p_user_id AND (phone IS NULL OR phone = '');\r\n  -- FOUND is true if the previous SQL statement affected at least one row\r\n  v_updated := FOUND;\r\n  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('updated', v_updated), 'error', NULL);\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_phone text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "set_user_phone_if_missing_safe",
    "function_source": "CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing_safe(p_user_id uuid, p_phone text DEFAULT NULL::text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  BEGIN\r\n    -- Call legacy function if present (works regardless of its return type)\r\n    PERFORM public.set_user_phone_if_missing(p_user_id, p_phone);\r\n    RETURN;\r\n  EXCEPTION\r\n    WHEN undefined_function THEN\r\n      -- Fallback to v2 if legacy is not defined\r\n      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);\r\n      RETURN;\r\n    WHEN OTHERS THEN\r\n      -- If legacy exists but fails, do not block; try v2 as best-effort\r\n      RAISE NOTICE 'legacy set_user_phone_if_missing failed: %', SQLERRM;\r\n      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);\r\n      RETURN;\r\n  END;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "set_user_phone_if_missing_v2",
    "function_source": "CREATE OR REPLACE FUNCTION public.set_user_phone_if_missing_v2(p_user_id uuid, p_phone text DEFAULT NULL::text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_phone   TEXT;\r\n  v_updated INT;\r\nBEGIN\r\n  IF p_user_id IS NULL THEN\r\n    RETURN FALSE;\r\n  END IF;\r\n\r\n  -- Prefer explicit phone; otherwise use auth.users raw_user_meta_data->>'phone'\r\n  v_phone := NULLIF(btrim(COALESCE(p_phone,\r\n    (SELECT au.raw_user_meta_data->>'phone'\r\n       FROM auth.users au\r\n      WHERE au.id = p_user_id)\r\n  )), '');\r\n\r\n  IF v_phone IS NULL THEN\r\n    RETURN FALSE;\r\n  END IF;\r\n\r\n  UPDATE public.users u\r\n     SET phone = v_phone,\r\n         updated_at = NOW()\r\n   WHERE u.id = p_user_id\r\n     AND COALESCE(btrim(u.phone), '') = ''\r\n  RETURNING 1 INTO v_updated;\r\n\r\n  RETURN COALESCE(v_updated, 0) > 0;\r\nEXCEPTION WHEN OTHERS THEN\r\n  -- Do not block callers; just log and return false\r\n  RAISE NOTICE 'set_user_phone_if_missing_v2: %', SQLERRM;\r\n  RETURN FALSE;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "submit_review",
    "function_source": "CREATE OR REPLACE FUNCTION public.submit_review(p_order_id uuid, p_rating smallint, p_subject_user_id uuid DEFAULT NULL::uuid, p_subject_restaurant_id uuid DEFAULT NULL::uuid, p_comment text DEFAULT ''::text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_author_id uuid := auth.uid();\r\n  v_author_role_en text;\r\n  v_author_role_es text;\r\nBEGIN\r\n  IF v_author_id IS NULL THEN\r\n    RAISE EXCEPTION 'Not authenticated';\r\n  END IF;\r\n\r\n  -- Validate inputs\r\n  IF p_order_id IS NULL THEN\r\n    RAISE EXCEPTION 'p_order_id is required';\r\n  END IF;\r\n  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN\r\n    RAISE EXCEPTION 'p_rating must be between 1 and 5';\r\n  END IF;\r\n  IF (p_subject_user_id IS NULL AND p_subject_restaurant_id IS NULL)\r\n     OR (p_subject_user_id IS NOT NULL AND p_subject_restaurant_id IS NOT NULL) THEN\r\n    RAISE EXCEPTION 'Provide either p_subject_user_id OR p_subject_restaurant_id, exclusively';\r\n  END IF;\r\n\r\n  -- Determine author role (EN) from users\r\n  SELECT role INTO v_author_role_en\r\n  FROM public.users\r\n  WHERE id = v_author_id;\r\n\r\n  IF v_author_role_en IS NULL THEN\r\n    v_author_role_en := 'client';\r\n  END IF;\r\n\r\n  -- Map EN -> ES for reviews.author_role\r\n  v_author_role_es := CASE lower(v_author_role_en)\r\n    WHEN 'client' THEN 'cliente'\r\n    WHEN 'restaurant' THEN 'restaurante'\r\n    WHEN 'delivery_agent' THEN 'repartidor'\r\n    WHEN 'admin' THEN 'admin'\r\n    ELSE 'cliente'\r\n  END;\r\n\r\n  INSERT INTO public.reviews (\r\n    order_id, author_id, author_role, subject_user_id, subject_restaurant_id, rating, comment\r\n  ) VALUES (\r\n    p_order_id, v_author_id, v_author_role_es, p_subject_user_id, p_subject_restaurant_id, p_rating, NULLIF(coalesce(p_comment, ''), '')\r\n  );\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_order_id uuid, p_rating smallint, p_subject_user_id uuid DEFAULT NULL::uuid, p_subject_restaurant_id uuid DEFAULT NULL::uuid, p_comment text DEFAULT ''::text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "trg_debug_log_delivery_agent_profiles",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_debug_log_delivery_agent_profiles()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN INSERT INTO public._debug_events(source, event, data) VALUES ('delivery_agent_profiles', TG_OP, to_jsonb(NEW)); RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "trg_debug_log_public_users_after_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_debug_log_public_users_after_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN INSERT INTO public._debug_events(source, event, data) VALUES ('public.users', 'after_insert', to_jsonb(NEW)); RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "trg_log_public_users_after_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_log_public_users_after_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.debug_user_signup_log(source, event, role, user_id, email, details) VALUES ('public.users', 'after_insert', NEW.role, NEW.id, NEW.email, jsonb_build_object('name', NEW.name, 'created_at', now())); RETURN NEW; EXCEPTION WHEN others THEN RETURN NEW; END $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "trg_set_user_phone_from_metadata",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_set_user_phone_from_metadata()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  PERFORM public.set_user_phone_if_missing(NEW.user_id, NULL);\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "trg_users_normalize_role",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_users_normalize_role()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$ BEGIN NEW.role := public.normalize_user_role(NEW.role); RETURN NEW; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "update_average_ratings",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_average_ratings()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n    -- Si la reseña es para un usuario (cliente o repartidor)\r\n    IF NEW.subject_user_id IS NOT NULL THEN\r\n        UPDATE public.users u\r\n        SET \r\n            total_reviews = (SELECT COUNT(*) FROM public.reviews WHERE subject_user_id = NEW.subject_user_id),\r\n            average_rating = (SELECT AVG(rating) FROM public.reviews WHERE subject_user_id = NEW.subject_user_id)\r\n        WHERE u.id = NEW.subject_user_id;\r\n    END IF;\r\n\r\n    -- Si la reseña es para un restaurante\r\n    IF NEW.subject_restaurant_id IS NOT NULL THEN\r\n        UPDATE public.restaurants r\r\n        SET \r\n            total_reviews = (SELECT COUNT(*) FROM public.reviews WHERE subject_restaurant_id = NEW.subject_restaurant_id),\r\n            average_rating = (SELECT AVG(rating) FROM public.reviews WHERE subject_restaurant_id = NEW.subject_restaurant_id)\r\n        WHERE r.id = NEW.subject_restaurant_id;\r\n    END IF;\r\n\r\n    RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "update_client_default_address",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_client_default_address(p_user_id uuid, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\ndeclare\r\n  v_result jsonb;\r\nbegin\r\n  perform public.ensure_client_profile_and_account(p_user_id);\r\n\r\n  update public.client_profiles\r\n  set\r\n    address = coalesce(p_address, address),\r\n    lat = coalesce(p_lat, lat),\r\n    lon = coalesce(p_lon, lon),\r\n    address_structured = coalesce(p_address_structured, address_structured),\r\n    updated_at = now()\r\n  where user_id = p_user_id;\r\n\r\n  select jsonb_build_object(\r\n    'success', true,\r\n    'user_id', p_user_id,\r\n    'address', (select address from public.client_profiles where user_id = p_user_id),\r\n    'lat', (select lat from public.client_profiles where user_id = p_user_id),\r\n    'lon', (select lon from public.client_profiles where user_id = p_user_id)\r\n  ) into v_result;\r\n\r\n  return v_result;\r\nexception when others then\r\n  return jsonb_build_object('success', false, 'error', sqlerrm);\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "update_my_delivery_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_my_delivery_profile(p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text)\n RETURNS delivery_agent_profiles\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public', 'pg_temp'\nAS $function$ SELECT public.upsert_delivery_agent_profile( p_user_id := p_user_id, p_vehicle_type := p_vehicle_type, p_vehicle_plate := p_vehicle_plate, p_vehicle_model := p_vehicle_model, p_vehicle_color := p_vehicle_color, p_emergency_contact_name := p_emergency_contact_name, p_emergency_contact_phone := p_emergency_contact_phone, p_place_id := p_place_id, p_lat := p_lat, p_lon := p_lon, p_address_structured := p_address_structured, p_profile_image_url := p_profile_image_url, p_id_document_front_url := p_id_document_front_url, p_id_document_back_url := p_id_document_back_url, p_vehicle_photo_url := p_vehicle_photo_url, p_vehicle_registration_url := p_vehicle_registration_url, p_vehicle_insurance_url := p_vehicle_insurance_url ); $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "return_type": "delivery_agent_profiles"
  },
  {
    "schema_name": "public",
    "function_name": "update_my_delivery_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_my_delivery_profile(p_profile_image_url text, p_vehicle_type text, p_vehicle_plate text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n    -- UPSERT actualiza la fila si existe, o la inserta si no.\r\n    INSERT INTO public.delivery_agent_profiles (\r\n        user_id,\r\n        profile_image_url,\r\n        vehicle_type,\r\n        vehicle_plate\r\n        -- ...\r\n    )\r\n    VALUES (\r\n        auth.uid(), -- ID del usuario autenticado\r\n        p_profile_image_url,\r\n        p_vehicle_type,\r\n        p_vehicle_plate\r\n        -- ...\r\n    )\r\n    ON CONFLICT (user_id) DO UPDATE SET\r\n        profile_image_url = EXCLUDED.profile_image_url,\r\n        vehicle_type = EXCLUDED.vehicle_type,\r\n        vehicle_plate = EXCLUDED.vehicle_plate,\r\n        -- ...\r\n        updated_at = NOW();\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_profile_image_url text, p_vehicle_type text, p_vehicle_plate text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "update_my_delivery_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_my_delivery_profile(p jsonb)\n RETURNS delivery_agent_profiles\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public', 'pg_temp'\nAS $function$ DECLARE v_user_id uuid := auth.uid(); v_row public.delivery_agent_profiles; BEGIN IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;INSERT INTO public.delivery_agent_profiles AS dap ( user_id, profile_image_url, vehicle_type, vehicle_plate, full_name, phone, address, place_id, lat, lon, document_id, is_active, availability_status ) VALUES ( v_user_id, p->>'profile_image_url', p->>'vehicle_type', p->>'vehicle_plate', p->>'full_name', p->>'phone', p->>'address', p->>'place_id', NULLIF(p->>'lat','')::double precision, NULLIF(p->>'lon','')::double precision, p->>'document_id', COALESCE((p->>'is_active')::boolean, true), COALESCE(p->>'availability_status', 'offline') ) ON CONFLICT (user_id) DO UPDATE SET profile_image_url    = COALESCE(EXCLUDED.profile_image_url, dap.profile_image_url), vehicle_type         = COALESCE(EXCLUDED.vehicle_type, dap.vehicle_type), vehicle_plate        = COALESCE(EXCLUDED.vehicle_plate, dap.vehicle_plate), full_name            = COALESCE(EXCLUDED.full_name, dap.full_name), phone                = COALESCE(EXCLUDED.phone, dap.phone), address              = COALESCE(EXCLUDED.address, dap.address), place_id             = COALESCE(EXCLUDED.place_id, dap.place_id), lat                  = COALESCE(EXCLUDED.lat, dap.lat), lon                  = COALESCE(EXCLUDED.lon, dap.lon), document_id          = COALESCE(EXCLUDED.document_id, dap.document_id), is_active            = COALESCE(EXCLUDED.is_active, dap.is_active), availability_status  = COALESCE(EXCLUDED.availability_status, dap.availability_status), updated_at           = now() RETURNING * INTO v_row;RETURN v_row; END; $function$\n",
    "volatility": "VOLATILE",
    "arguments": "p jsonb",
    "return_type": "delivery_agent_profiles"
  },
  {
    "schema_name": "public",
    "function_name": "update_my_phone_if_unique",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_my_phone_if_unique(p_phone text)\n RETURNS void\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\ndeclare\r\n  v_conflict uuid;\r\nbegin\r\n  if p_phone is null or length(trim(p_phone)) = 0 then\r\n    raise exception 'phone_required';\r\n  end if;\r\n\r\n  -- Check uniqueness across users excluding current user\r\n  select u.id into v_conflict\r\n  from public.users u\r\n  where u.phone = trim(p_phone)\r\n    and u.id <> auth.uid()\r\n  limit 1;\r\n\r\n  if v_conflict is not null then\r\n    raise exception 'phone_in_use';\r\n  end if;\r\n\r\n  update public.users\r\n  set phone = trim(p_phone),\r\n      updated_at = now()\r\n  where id = auth.uid();\r\n\r\n  if not found then\r\n    raise exception 'profile_not_found';\r\n  end if;\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_phone text",
    "return_type": "void"
  },
  {
    "schema_name": "public",
    "function_name": "update_restaurant_completion_on_product_change",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_restaurant_completion_on_product_change()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nBEGIN\r\n    UPDATE restaurants\r\n    SET profile_completion_percentage = calculate_restaurant_completion(COALESCE(NEW.restaurant_id, OLD.restaurant_id))\r\n    WHERE id = COALESCE(NEW.restaurant_id, OLD.restaurant_id);\r\n    \r\n    RETURN COALESCE(NEW, OLD);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "update_restaurant_completion_trigger",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_restaurant_completion_trigger()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nBEGIN\r\n    NEW.profile_completion_percentage := calculate_restaurant_completion(NEW.id);\r\n    RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "update_user_location",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_user_location(p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nbegin\r\n  -- uses auth.uid() to determine user\r\n  return public.update_client_default_address(\r\n    auth.uid(), p_address, p_lat, p_lon, p_address_structured\r\n  );\r\nend;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "update_user_preferences_updated_at",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_user_preferences_updated_at()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nBEGIN\r\n  NEW.updated_at = NOW();\r\n  RETURN NEW;\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "",
    "return_type": "trigger"
  },
  {
    "schema_name": "public",
    "function_name": "upsert_delivery_agent_profile",
    "function_source": "CREATE OR REPLACE FUNCTION public.upsert_delivery_agent_profile(p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text)\n RETURNS jsonb\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User ID does not exist in auth.users';\r\n  END IF;\r\n\r\n  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN\r\n    RAISE EXCEPTION 'User profile does not exist. Create user profile first.';\r\n  END IF;\r\n\r\n  UPDATE public.users\r\n  SET role = 'delivery_agent', updated_at = NOW()\r\n  WHERE id = p_user_id AND COALESCE(role, '') <> 'delivery_agent';\r\n\r\n  INSERT INTO public.delivery_agent_profiles (\r\n    user_id,\r\n    vehicle_type,\r\n    vehicle_plate,\r\n    vehicle_model,\r\n    vehicle_color,\r\n    emergency_contact_name,\r\n    emergency_contact_phone,\r\n    place_id,\r\n    lat,\r\n    lon,\r\n    address_structured,\r\n    profile_image_url,\r\n    id_document_front_url,\r\n    id_document_back_url,\r\n    vehicle_photo_url,\r\n    vehicle_registration_url,\r\n    vehicle_insurance_url,\r\n    created_at,\r\n    updated_at\r\n  ) VALUES (\r\n    p_user_id,\r\n    p_vehicle_type,\r\n    p_vehicle_plate,\r\n    p_vehicle_model,\r\n    p_vehicle_color,\r\n    p_emergency_contact_name,\r\n    p_emergency_contact_phone,\r\n    p_place_id,\r\n    p_lat,\r\n    p_lon,\r\n    p_address_structured,\r\n    p_profile_image_url,\r\n    p_id_document_front_url,\r\n    p_id_document_back_url,\r\n    p_vehicle_photo_url,\r\n    p_vehicle_registration_url,\r\n    p_vehicle_insurance_url,\r\n    NOW(),\r\n    NOW()\r\n  )\r\n  ON CONFLICT (user_id) DO UPDATE SET\r\n    vehicle_type = COALESCE(EXCLUDED.vehicle_type, delivery_agent_profiles.vehicle_type),\r\n    vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, delivery_agent_profiles.vehicle_plate),\r\n    vehicle_model = COALESCE(EXCLUDED.vehicle_model, delivery_agent_profiles.vehicle_model),\r\n    vehicle_color = COALESCE(EXCLUDED.vehicle_color, delivery_agent_profiles.vehicle_color),\r\n    emergency_contact_name = COALESCE(EXCLUDED.emergency_contact_name, delivery_agent_profiles.emergency_contact_name),\r\n    emergency_contact_phone = COALESCE(EXCLUDED.emergency_contact_phone, delivery_agent_profiles.emergency_contact_phone),\r\n    place_id = COALESCE(EXCLUDED.place_id, delivery_agent_profiles.place_id),\r\n    lat = COALESCE(EXCLUDED.lat, delivery_agent_profiles.lat),\r\n    lon = COALESCE(EXCLUDED.lon, delivery_agent_profiles.lon),\r\n    address_structured = COALESCE(EXCLUDED.address_structured, delivery_agent_profiles.address_structured),\r\n    profile_image_url = COALESCE(EXCLUDED.profile_image_url, delivery_agent_profiles.profile_image_url),\r\n    id_document_front_url = COALESCE(EXCLUDED.id_document_front_url, delivery_agent_profiles.id_document_front_url),\r\n    id_document_back_url = COALESCE(EXCLUDED.id_document_back_url, delivery_agent_profiles.id_document_back_url),\r\n    vehicle_photo_url = COALESCE(EXCLUDED.vehicle_photo_url, delivery_agent_profiles.vehicle_photo_url),\r\n    vehicle_registration_url = COALESCE(EXCLUDED.vehicle_registration_url, delivery_agent_profiles.vehicle_registration_url),\r\n    vehicle_insurance_url = COALESCE(EXCLUDED.vehicle_insurance_url, delivery_agent_profiles.vehicle_insurance_url),\r\n    updated_at = NOW();\r\n\r\n  RETURN jsonb_build_object('success', true, 'user_id', p_user_id, 'message', 'Delivery agent profile upserted');\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    RETURN jsonb_build_object('success', false, 'error', SQLERRM);\r\nEND;\r\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_user_id uuid, p_vehicle_type text, p_vehicle_plate text, p_vehicle_model text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_emergency_contact_name text DEFAULT NULL::text, p_emergency_contact_phone text DEFAULT NULL::text, p_place_id text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_profile_image_url text DEFAULT NULL::text, p_id_document_front_url text DEFAULT NULL::text, p_id_document_back_url text DEFAULT NULL::text, p_vehicle_photo_url text DEFAULT NULL::text, p_vehicle_registration_url text DEFAULT NULL::text, p_vehicle_insurance_url text DEFAULT NULL::text",
    "return_type": "jsonb"
  },
  {
    "schema_name": "public",
    "function_name": "validate_email",
    "function_source": "CREATE OR REPLACE FUNCTION public.validate_email(p_email text, p_user_type text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\nBEGIN\n  -- Se ignora p_user_type, la consulta es directa a public.users\n  RETURN EXISTS(SELECT 1 FROM public.users WHERE email = p_email);\nEND;\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_email text, p_user_type text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "validate_name",
    "function_source": "CREATE OR REPLACE FUNCTION public.validate_name(p_name text, p_user_type text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\nBEGIN\n  IF p_user_type = 'restaurant' THEN\n    RETURN EXISTS(SELECT 1 FROM public.restaurants WHERE name = p_name);\n  ELSE\n    RETURN FALSE;\n  END IF;\nEND;\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_name text, p_user_type text",
    "return_type": "boolean"
  },
  {
    "schema_name": "public",
    "function_name": "validate_phone",
    "function_source": "CREATE OR REPLACE FUNCTION public.validate_phone(p_phone text, p_user_type text)\n RETURNS boolean\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\nBEGIN\n  -- Se ignora p_user_type, la consulta es directa a public.users\n  RETURN EXISTS(SELECT 1 FROM public.users WHERE phone = p_phone);\nEND;\n$function$\n",
    "volatility": "VOLATILE",
    "arguments": "p_phone text, p_user_type text",
    "return_type": "boolean"
  }
]