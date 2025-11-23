-- ============================================================
-- PARTE 1: VERIFICAR ESTRUCTURA DE TABLAS INVOLUCRADAS
-- ============================================================

-- 1.1 Verificar columnas de public.users:
[
  {
    "seccion": "TABLA: public.users",
    "column_name": "id",
    "data_type": "uuid",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "email",
    "data_type": "text",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "name",
    "data_type": "text",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "phone",
    "data_type": "text",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "role",
    "data_type": "text",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "updated_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.users",
    "column_name": "email_confirm",
    "data_type": "boolean",
    "is_nullable": "YES"
  }
]

-- 1.2 Verificar columnas de public.client_profiles:
[
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "user_id",
    "data_type": "uuid",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "updated_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "address",
    "data_type": "text",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "lat",
    "data_type": "double precision",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "lon",
    "data_type": "double precision",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "address_structured",
    "data_type": "jsonb",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "average_rating",
    "data_type": "numeric",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "total_reviews",
    "data_type": "integer",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "profile_image_url",
    "data_type": "text",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.client_profiles",
    "column_name": "status",
    "data_type": "text",
    "is_nullable": "NO"
  }
]

-- 1.3 Verificar columnas de public.user_preferences:
[
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "user_id",
    "data_type": "uuid",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "has_seen_onboarding",
    "data_type": "boolean",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "created_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "updated_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "has_seen_restaurant_welcome",
    "data_type": "boolean",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "restaurant_welcome_seen_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "email_verified_congrats_shown",
    "data_type": "boolean",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "first_login_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "last_login_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "login_count",
    "data_type": "integer",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "restaurant_id",
    "data_type": "uuid",
    "is_nullable": "YES"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "has_seen_delivery_welcome",
    "data_type": "boolean",
    "is_nullable": "NO"
  },
  {
    "seccion": "TABLA: public.user_preferences",
    "column_name": "delivery_welcome_seen_at",
    "data_type": "timestamp with time zone",
    "is_nullable": "YES"
  }
]


-- ============================================================
-- PARTE 2: VERIFICAR ÚLTIMO REGISTRO DE CLIENTE
-- ============================================================

-- 2.1 Ver último cliente registrado en public.users:
[
  {
    "seccion": "ÚLTIMO CLIENTE EN USERS",
    "id": "d2624ce1-0188-40b0-af5b-ca49b85487ba",
    "email": "",
    "name": null,
    "phone": null,
    "role": "client",
    "created_at": "2025-11-12 03:13:03.179312+00",
    "updated_at": "2025-11-12 03:13:03.179312+00",
    "email_confirm": false
  }
]

-- 2.2 Ver datos del último cliente en public.client_profiles:
[
  {
    "seccion": "ÚLTIMO CLIENTE EN CLIENT_PROFILES",
    "user_id": "d2624ce1-0188-40b0-af5b-ca49b85487ba",
    "email": "",
    "name": null,
    "address": null,
    "lat": null,
    "lon": null,
    "address_structured": null,
    "status": "active",
    "created_at": "2025-11-12 03:13:03.179312+00"
  }
]

-- 2.3 Ver datos del último cliente en public.user_preferences:
[
  {
    "seccion": "ÚLTIMO CLIENTE EN USER_PREFERENCES",
    "user_id": "d2624ce1-0188-40b0-af5b-ca49b85487ba",
    "email": "",
    "name": null,
    "has_seen_onboarding": false,
    "login_count": 0,
    "first_login_at": null,
    "last_login_at": null,
    "created_at": "2025-11-12 03:13:03.69668+00"
  }
]


-- ============================================================
-- PARTE 3: BUSCAR CLIENTES CON DATOS INCOMPLETOS
-- ============================================================

-- 3.1 Clientes SIN nombre o teléfono en public.users:
[
  {
    "problema": "CLIENTES SIN NOMBRE/TELÉFONO",
    "id": "d2624ce1-0188-40b0-af5b-ca49b85487ba",
    "email": "",
    "name": null,
    "phone": null,
    "created_at": "2025-11-12 03:13:03.179312+00"
  }
]

-- 3.2 Clientes SIN registro en client_profiles: 0

-- 3.3 Clientes CON perfil pero SIN ubicación: 
[
  {
    "problema": "CLIENTES SIN UBICACIÓN",
    "id": "d2624ce1-0188-40b0-af5b-ca49b85487ba",
    "email": "",
    "name": null,
    "lat": null,
    "lon": null,
    "address": null,
    "created_at": "2025-11-12 03:13:03.179312+00"
  }
]


-- ============================================================
-- PARTE 4: VERIFICAR FUNCIONES Y TRIGGERS
-- ============================================================

-- 4.1 Listar todas las funciones relacionadas con 'user':
[
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "admin_approve_user",
    "arguments": "p_user_id uuid, p_status text",
    "source_code": "\r\nDECLARE\r\n  v_result jsonb;\r\nBEGIN\r\n  -- Validate that the caller is an admin\r\n  IF NOT public.is_admin() THEN\r\n    RAISE EXCEPTION 'FORBIDDEN: admin only' \r\n      USING ERRCODE = '42501';\r\n  END IF;\r\n\r\n  -- Validate status parameter\r\n  IF p_status NOT IN ('approved', 'rejected', 'pending') THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'message', 'Invalid status. Must be approved, rejected, or pending'\r\n    );\r\n  END IF;\r\n\r\n  -- Update users table\r\n  UPDATE users\r\n  SET \r\n    status = p_status,\r\n    updated_at = NOW()\r\n  WHERE id = p_user_id;\r\n\r\n  -- Check if update was successful\r\n  IF NOT FOUND THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'message', 'User not found'\r\n    );\r\n  END IF;\r\n\r\n  -- Return success with updated data\r\n  SELECT jsonb_build_object(\r\n    'success', true,\r\n    'message', 'User status updated successfully',\r\n    'status', status,\r\n    'updated_at', updated_at\r\n  )\r\n  INTO v_result\r\n  FROM users\r\n  WHERE id = p_user_id;\r\n\r\n  RETURN v_result;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "calculate_distance_between_users",
    "arguments": "user_id_1 uuid, user_id_2 uuid",
    "source_code": "\r\nDECLARE\r\n  lat1 DOUBLE PRECISION;\r\n  lon1 DOUBLE PRECISION;\r\n  lat2 DOUBLE PRECISION;\r\n  lon2 DOUBLE PRECISION;\r\n  R CONSTANT DOUBLE PRECISION := 6371; -- Earth radius in kilometers\r\n  dLat DOUBLE PRECISION;\r\n  dLon DOUBLE PRECISION;\r\n  a DOUBLE PRECISION;\r\n  c DOUBLE PRECISION;\r\nBEGIN\r\n  -- Get coordinates for user 1\r\n  SELECT (address_structured->>'lat')::double precision, \r\n         (address_structured->>'lon')::double precision\r\n  INTO lat1, lon1\r\n  FROM public.users WHERE id = user_id_1;\r\n\r\n  -- Get coordinates for user 2\r\n  SELECT (address_structured->>'lat')::double precision, \r\n         (address_structured->>'lon')::double precision\r\n  INTO lat2, lon2\r\n  FROM public.users WHERE id = user_id_2;\r\n\r\n  -- Return NULL if any coordinate is missing\r\n  IF lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN\r\n    RETURN NULL;\r\n  END IF;\r\n\r\n  -- Haversine formula\r\n  dLat := radians(lat2 - lat1);\r\n  dLon := radians(lon2 - lon1);\r\n  \r\n  a := sin(dLat/2) * sin(dLat/2) +\r\n       cos(radians(lat1)) * cos(radians(lat2)) *\r\n       sin(dLon/2) * sin(dLon/2);\r\n  \r\n  c := 2 * atan2(sqrt(a), sqrt(1-a));\r\n  \r\n  RETURN R * c; -- Distance in kilometers\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "create_account_on_user_approval",
    "arguments": "",
    "source_code": "\r\nDECLARE\r\n    mapped_account_type TEXT;\r\nBEGIN\r\n    -- Solo procesar cuando se actualiza status a 'approved'\r\n    IF TG_OP = 'UPDATE' AND \r\n       OLD.status != 'approved' AND \r\n       NEW.status = 'approved' THEN\r\n        \r\n        -- Mapear rol del usuario a tipo de cuenta\r\n        CASE NEW.role\r\n            WHEN 'restaurante' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'restaurant' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'delivery_agent' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            WHEN 'repartidor' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            ELSE\r\n                -- No crear cuenta para admin o cliente\r\n                RETURN NEW;\r\n        END CASE;\r\n        \r\n        -- Verificar si ya existe una cuenta para este usuario\r\n        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = NEW.id) THEN\r\n            -- Crear cuenta con balance inicial 0\r\n            INSERT INTO public.accounts (\r\n                id,\r\n                user_id,\r\n                account_type,\r\n                balance,\r\n                created_at,\r\n                updated_at\r\n            ) VALUES (\r\n                gen_random_uuid(),\r\n                NEW.id,\r\n                mapped_account_type,\r\n                0.0,\r\n                NOW(),\r\n                NOW()\r\n            );\r\n            \r\n            RAISE NOTICE 'Cuenta creada para usuario % con tipo %', NEW.id, mapped_account_type;\r\n        ELSE\r\n            RAISE NOTICE 'Cuenta ya existe para usuario %', NEW.id;\r\n        END IF;\r\n    END IF;\r\n    \r\n    RETURN NEW;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "create_user_profile_public",
    "arguments": "p_user_id uuid, p_email text, p_name text DEFAULT ''::text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_role text DEFAULT 'client'::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb, p_is_temp_password boolean DEFAULT false",
    "source_code": "\r\nbegin\r\n  perform public.ensure_user_profile_public(\r\n    p_user_id => p_user_id,\r\n    p_email => p_email,\r\n    p_name => p_name,\r\n    p_role => p_role,\r\n    p_phone => p_phone,\r\n    p_address => p_address,\r\n    p_lat => p_lat,\r\n    p_lon => p_lon,\r\n    p_address_structured => p_address_structured,\r\n    p_is_temp_password => p_is_temp_password\r\n  );\r\nend "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "ensure_user_preferences",
    "arguments": "_user_id uuid, _restaurant_id uuid DEFAULT NULL::uuid",
    "source_code": " begin insert into public.user_preferences (user_id, restaurant_id, first_login_at, last_login_at, login_count) values (_user_id, _restaurant_id, now(), now(), 1) on conflict (user_id) do update set last_login_at = now(), login_count = public.user_preferences.login_count + 1, restaurant_id = coalesce(excluded.restaurant_id, public.user_preferences.restaurant_id), updated_at = now(); end; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "ensure_user_profile_public",
    "arguments": "p_user_id uuid, p_email text, p_role text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text",
    "source_code": "\r\nDECLARE\r\n  v_existing_user record;\r\n  v_user_meta jsonb;\r\n  v_lat double precision;\r\n  v_lon double precision;\r\n  v_address_structured jsonb;\r\n  v_result json;\r\nBEGIN\r\n  -- Validar rol\r\n  IF p_role NOT IN ('client', 'restaurant', 'delivery_agent', 'admin') THEN\r\n    RAISE EXCEPTION 'Invalid role: %. Must be one of: client, restaurant, delivery_agent, admin', p_role;\r\n  END IF;\r\n\r\n  -- Obtener metadata del usuario desde auth.users\r\n  SELECT raw_user_meta_data INTO v_user_meta\r\n  FROM auth.users\r\n  WHERE id = p_user_id;\r\n\r\n  -- Extraer datos de ubicación (para clientes)\r\n  IF p_role = 'client' AND v_user_meta IS NOT NULL THEN\r\n    v_lat := (v_user_meta->>'lat')::double precision;\r\n    v_lon := (v_user_meta->>'lon')::double precision;\r\n    v_address_structured := v_user_meta->'address_structured';\r\n  END IF;\r\n\r\n  -- Buscar usuario existente\r\n  SELECT * INTO v_existing_user\r\n  FROM public.users\r\n  WHERE id = p_user_id;\r\n\r\n  IF v_existing_user IS NULL THEN\r\n    -- Crear nuevo usuario\r\n    INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at)\r\n    VALUES (p_user_id, p_email, p_role, p_name, p_phone, now(), now());\r\n\r\n    -- Si es cliente, crear client_profiles con ubicación\r\n    IF p_role = 'client' THEN\r\n      INSERT INTO public.client_profiles (\r\n        user_id,\r\n        lat,\r\n        lon,\r\n        address_structured,\r\n        created_at,\r\n        updated_at\r\n      )\r\n      VALUES (\r\n        p_user_id,\r\n        v_lat,\r\n        v_lon,\r\n        v_address_structured,\r\n        now(),\r\n        now()\r\n      );\r\n    END IF;\r\n\r\n    -- Crear user_preferences\r\n    INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n    VALUES (p_user_id, now(), now())\r\n    ON CONFLICT (user_id) DO NOTHING;\r\n\r\n    v_result := json_build_object(\r\n      'user_id', p_user_id,\r\n      'created', true,\r\n      'role', p_role\r\n    );\r\n  ELSE\r\n    -- Usuario existe: actualizar datos\r\n    UPDATE public.users\r\n    SET \r\n      email = p_email,\r\n      role = p_role,\r\n      name = COALESCE(p_name, name),\r\n      phone = COALESCE(p_phone, phone),\r\n      updated_at = now()\r\n    WHERE id = p_user_id;\r\n\r\n    -- Si es cliente, actualizar ubicación en client_profiles\r\n    IF p_role = 'client' THEN\r\n      UPDATE public.client_profiles\r\n      SET\r\n        lat = COALESCE(v_lat, lat),\r\n        lon = COALESCE(v_lon, lon),\r\n        address_structured = COALESCE(v_address_structured, address_structured),\r\n        updated_at = now()\r\n      WHERE user_id = p_user_id;\r\n    END IF;\r\n\r\n    -- Asegurar user_preferences existe\r\n    INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n    VALUES (p_user_id, now(), now())\r\n    ON CONFLICT (user_id) DO NOTHING;\r\n\r\n    v_result := json_build_object(\r\n      'user_id', p_user_id,\r\n      'created', false,\r\n      'updated', true,\r\n      'role', p_role\r\n    );\r\n  END IF;\r\n\r\n  RETURN v_result;\r\n\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    RAISE EXCEPTION 'Error in ensure_user_profile_public: %', SQLERRM;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "ensure_user_profile_public",
    "arguments": "p_user_id uuid, p_email text, p_name text, p_role text, p_phone text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "source_code": "\r\nDECLARE\r\n  v_existing_user_id uuid;\r\n  v_existing_role text;\r\n  v_result jsonb;\r\nBEGIN\r\n  -- ===============================================\r\n  -- LOGS DE DEBUG AGREGADOS\r\n  -- ===============================================\r\n  RAISE NOTICE '========================================';\r\n  RAISE NOTICE '📍 [DEBUG] ensure_user_profile_public() llamado';\r\n  RAISE NOTICE '   - p_user_id: %', p_user_id;\r\n  RAISE NOTICE '   - p_email: %', p_email;\r\n  RAISE NOTICE '   - p_name: %', p_name;\r\n  RAISE NOTICE '   - p_role: %', p_role;\r\n  RAISE NOTICE '   - p_phone: %', p_phone;\r\n  RAISE NOTICE '   - p_address: %', p_address;\r\n  RAISE NOTICE '   - p_lat: %', p_lat;\r\n  RAISE NOTICE '   - p_lon: %', p_lon;\r\n  RAISE NOTICE '   - p_address_structured: %', p_address_structured;\r\n  RAISE NOTICE '========================================';\r\n\r\n  -- Check if user exists in public.users\r\n  SELECT id, role INTO v_existing_user_id, v_existing_role\r\n  FROM public.users\r\n  WHERE id = p_user_id;\r\n\r\n  IF v_existing_user_id IS NOT NULL THEN\r\n    RAISE NOTICE '✅ [DEBUG] Usuario YA existe en public.users (role: %)', v_existing_role;\r\n    \r\n    -- ===============================================\r\n    -- ACTUALIZAR USUARIO EXISTENTE\r\n    -- ===============================================\r\n    UPDATE public.users\r\n    SET\r\n      name = COALESCE(p_name, name),\r\n      phone = COALESCE(p_phone, phone),\r\n      address = COALESCE(p_address, address),\r\n      updated_at = now()\r\n    WHERE id = p_user_id;\r\n\r\n    RAISE NOTICE '✅ [DEBUG] Usuario actualizado en public.users';\r\n\r\n    -- Si es cliente, actualizar ubicación en client_profiles\r\n    IF v_existing_role = 'client' THEN\r\n      RAISE NOTICE '📍 [DEBUG] Actualizando ubicación en client_profiles...';\r\n      \r\n      UPDATE public.client_profiles\r\n      SET\r\n        lat = COALESCE(p_lat, lat),\r\n        lon = COALESCE(p_lon, lon),\r\n        address = COALESCE(p_address, address),\r\n        address_structured = COALESCE(p_address_structured, address_structured),\r\n        updated_at = now()\r\n      WHERE user_id = p_user_id;\r\n\r\n      IF FOUND THEN\r\n        RAISE NOTICE '✅ [DEBUG] client_profiles actualizado con ubicación';\r\n      ELSE\r\n        RAISE NOTICE '❌ [DEBUG] NO se encontró client_profiles para user_id: %', p_user_id;\r\n      END IF;\r\n    END IF;\r\n\r\n    v_result := jsonb_build_object(\r\n      'success', true,\r\n      'user_id', p_user_id,\r\n      'action', 'updated'\r\n    );\r\n    RETURN v_result;\r\n  ELSE\r\n    RAISE NOTICE '🆕 [DEBUG] Usuario NO existe. Creando nuevo usuario...';\r\n    RAISE NOTICE '   - Insertando en public.users:';\r\n    RAISE NOTICE '     * id: %', p_user_id;\r\n    RAISE NOTICE '     * email: %', p_email;\r\n    RAISE NOTICE '     * name: %', p_name;\r\n    RAISE NOTICE '     * role: %', p_role;\r\n    RAISE NOTICE '     * phone: %', p_phone;\r\n    RAISE NOTICE '     * address: %', p_address;\r\n    \r\n    -- ===============================================\r\n    -- CREAR NUEVO USUARIO (LÓGICA ORIGINAL RESTAURADA)\r\n    -- ===============================================\r\n    INSERT INTO public.users (id, email, role, name, phone, address, created_at, updated_at)\r\n    VALUES (p_user_id, p_email, p_role, p_name, p_phone, p_address, now(), now());\r\n\r\n    RAISE NOTICE '✅ [DEBUG] Usuario creado exitosamente en public.users';\r\n\r\n    -- Si es cliente, el trigger debe crear client_profiles\r\n    IF p_role = 'client' THEN\r\n      RAISE NOTICE '⏳ [DEBUG] Esperando que trigger cree client_profiles...';\r\n      \r\n      -- Esperar un momento para el trigger\r\n      PERFORM pg_sleep(0.1);\r\n      \r\n      -- Verificar si se creó\r\n      IF EXISTS (SELECT 1 FROM public.client_profiles WHERE user_id = p_user_id) THEN\r\n        RAISE NOTICE '✅ [DEBUG] client_profiles fue creado por el trigger';\r\n        \r\n        -- ===============================================\r\n        -- ACTUALIZAR UBICACIÓN EN client_profiles\r\n        -- ===============================================\r\n        RAISE NOTICE '📍 [DEBUG] Actualizando ubicación en client_profiles...';\r\n        RAISE NOTICE '   - lat: %', p_lat;\r\n        RAISE NOTICE '   - lon: %', p_lon;\r\n        RAISE NOTICE '   - address: %', p_address;\r\n        RAISE NOTICE '   - address_structured: %', p_address_structured;\r\n        \r\n        UPDATE public.client_profiles\r\n        SET\r\n          lat = p_lat,\r\n          lon = p_lon,\r\n          address = p_address,\r\n          address_structured = p_address_structured,\r\n          updated_at = now()\r\n        WHERE user_id = p_user_id;\r\n\r\n        IF FOUND THEN\r\n          RAISE NOTICE '✅ [DEBUG] ¡Ubicación guardada exitosamente en client_profiles!';\r\n          \r\n          -- Verificar valores guardados\r\n          DECLARE\r\n            v_saved_lat double precision;\r\n            v_saved_lon double precision;\r\n            v_saved_address text;\r\n          BEGIN\r\n            SELECT lat, lon, address INTO v_saved_lat, v_saved_lon, v_saved_address\r\n            FROM public.client_profiles\r\n            WHERE user_id = p_user_id;\r\n            \r\n            RAISE NOTICE '🔍 [DEBUG] Valores verificados en DB:';\r\n            RAISE NOTICE '   - lat guardado: %', v_saved_lat;\r\n            RAISE NOTICE '   - lon guardado: %', v_saved_lon;\r\n            RAISE NOTICE '   - address guardado: %', v_saved_address;\r\n          END;\r\n        ELSE\r\n          RAISE NOTICE '❌ [DEBUG] ERROR: No se pudo actualizar client_profiles';\r\n        END IF;\r\n      ELSE\r\n        RAISE NOTICE '❌ [DEBUG] ERROR: client_profiles NO fue creado por el trigger';\r\n        RAISE NOTICE '   - Intentando crear manualmente...';\r\n        \r\n        -- Crear manualmente si el trigger falló\r\n        INSERT INTO public.client_profiles (\r\n          user_id,\r\n          address,\r\n          lat,\r\n          lon,\r\n          address_structured,\r\n          created_at,\r\n          updated_at\r\n        ) VALUES (\r\n          p_user_id,\r\n          p_address,\r\n          p_lat,\r\n          p_lon,\r\n          p_address_structured,\r\n          now(),\r\n          now()\r\n        );\r\n        \r\n        RAISE NOTICE '✅ [DEBUG] client_profiles creado manualmente con ubicación';\r\n      END IF;\r\n    END IF;\r\n\r\n    v_result := jsonb_build_object(\r\n      'success', true,\r\n      'user_id', p_user_id,\r\n      'action', 'created'\r\n    );\r\n    RETURN v_result;\r\n  END IF;\r\n\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    RAISE NOTICE '❌ [DEBUG] EXCEPCIÓN: %', SQLERRM;\r\n    RAISE NOTICE '   - SQLSTATE: %', SQLSTATE;\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'error', SQLERRM,\r\n      'sqlstate', SQLSTATE\r\n    );\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "fn_get_restaurant_owner_user_id",
    "arguments": "p_restaurant_id uuid",
    "source_code": " select r.user_id from public.restaurants r where r.id = p_restaurant_id limit 1 "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "get_all_users_admin",
    "arguments": "",
    "source_code": "\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Return all users (bypasses RLS)\r\n  RETURN QUERY \r\n  SELECT \r\n    u.id,\r\n    u.email,\r\n    u.name,\r\n    u.phone,\r\n    u.address,\r\n    u.role,\r\n    u.email_confirm,\r\n    u.avatar_url,\r\n    u.created_at,\r\n    u.updated_at\r\n  FROM users u\r\n  ORDER BY u.created_at DESC;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "get_user_formatted_address",
    "arguments": "user_id uuid",
    "source_code": "\r\n  SELECT address_structured->>'formatted_address'\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "get_user_lat",
    "arguments": "user_id uuid",
    "source_code": "\r\n  SELECT (address_structured->>'lat')::double precision\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "get_user_lon",
    "arguments": "user_id uuid",
    "source_code": "\r\n  SELECT (address_structured->>'lon')::double precision\r\n  FROM public.users\r\n  WHERE id = user_id;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "get_user_stats_admin",
    "arguments": "",
    "source_code": "\r\nDECLARE\r\n  result JSON;\r\nBEGIN\r\n  -- Check if the user is admin\r\n  IF NOT EXISTS (\r\n    SELECT 1 FROM users \r\n    WHERE id = auth.uid() AND role = 'admin'\r\n  ) THEN\r\n    RAISE EXCEPTION 'Access denied. Admin role required.';\r\n  END IF;\r\n  \r\n  -- Get user statistics\r\n  SELECT json_build_object(\r\n    'total_users', (SELECT COUNT(*) FROM users),\r\n    'clients', (SELECT COUNT(*) FROM users WHERE role = 'cliente'),\r\n    'restaurants', (SELECT COUNT(*) FROM users WHERE role = 'restaurante'), \r\n    'delivery_agents', (SELECT COUNT(*) FROM users WHERE role = 'repartidor'),\r\n    'admins', (SELECT COUNT(*) FROM users WHERE role = 'admin'),\r\n    'confirmed_emails', (SELECT COUNT(*) FROM users WHERE email_confirm = true),\r\n    'unconfirmed_emails', (SELECT COUNT(*) FROM users WHERE email_confirm = false OR email_confirm IS NULL)\r\n  ) INTO result;\r\n  \r\n  RETURN result;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "handle_new_user_delivery_profile",
    "arguments": "",
    "source_code": " begin insert into public.delivery_agent_profiles (user_id) values (new.id) on conflict (user_id) do nothing;insert into public.user_preferences (user_id) values (new.id) on conflict (user_id) do nothing;return new; end; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "handle_new_user_signup_v2",
    "arguments": "",
    "source_code": "\r\nDECLARE\r\n  v_email TEXT;\r\n  v_role TEXT;\r\n  v_name TEXT;\r\n  v_phone TEXT;\r\n  v_address TEXT;\r\n  v_lat DOUBLE PRECISION;\r\n  v_lon DOUBLE PRECISION;\r\n  v_address_structured JSONB;\r\n  v_metadata JSONB;\r\nBEGIN\r\n  -- ========================================================================\r\n  -- EXTRAER METADATA DE auth.users\r\n  -- ========================================================================\r\n  \r\n  v_email := NEW.email;\r\n  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);\r\n  v_role := COALESCE(v_metadata->>'role', 'cliente');\r\n  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));\r\n  v_phone := v_metadata->>'phone';\r\n  v_address := v_metadata->>'address';\r\n  \r\n  -- ========================================================================\r\n  -- 🔥 CAPTURAR UBICACIÓN (CLIENTE)\r\n  -- ========================================================================\r\n  \r\n  -- Capturar lat con conversión segura\r\n  BEGIN\r\n    v_lat := CASE \r\n      WHEN v_metadata->>'lat' IS NOT NULL AND v_metadata->>'lat' != '' \r\n      THEN (v_metadata->>'lat')::DOUBLE PRECISION\r\n      ELSE NULL\r\n    END;\r\n  EXCEPTION WHEN OTHERS THEN\r\n    v_lat := NULL;\r\n  END;\r\n  \r\n  -- Capturar lon con conversión segura\r\n  BEGIN\r\n    v_lon := CASE \r\n      WHEN v_metadata->>'lon' IS NOT NULL AND v_metadata->>'lon' != '' \r\n      THEN (v_metadata->>'lon')::DOUBLE PRECISION\r\n      ELSE NULL\r\n    END;\r\n  EXCEPTION WHEN OTHERS THEN\r\n    v_lon := NULL;\r\n  END;\r\n  \r\n  -- Capturar address_structured (JSONB)\r\n  v_address_structured := CASE\r\n    WHEN v_metadata->'address_structured' IS NOT NULL \r\n    THEN v_metadata->'address_structured'\r\n    ELSE NULL\r\n  END;\r\n\r\n  -- ========================================================================\r\n  -- NORMALIZACIÓN DE ROLES (español → inglés)\r\n  -- ========================================================================\r\n  \r\n  v_role := CASE lower(v_role)\r\n    WHEN 'client' THEN 'client'\r\n    WHEN 'cliente' THEN 'client'\r\n    WHEN 'restaurant' THEN 'restaurant'\r\n    WHEN 'restaurante' THEN 'restaurant'\r\n    WHEN 'delivery_agent' THEN 'delivery_agent'\r\n    WHEN 'delivery' THEN 'delivery_agent'\r\n    WHEN 'repartidor' THEN 'delivery_agent'\r\n    WHEN 'admin' THEN 'admin'\r\n    ELSE 'client'\r\n  END;\r\n\r\n  -- Log inicial con todos los datos capturados\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_new_user_signup_v2', 'START', v_role, NEW.id, v_email, \r\n          jsonb_build_object(\r\n            'input_role', v_metadata->>'role', \r\n            'normalized_role', v_role,\r\n            'name', v_name,\r\n            'phone', v_phone,\r\n            'address', v_address,\r\n            'lat', v_lat,\r\n            'lon', v_lon,\r\n            'has_coordinates', v_lat IS NOT NULL AND v_lon IS NOT NULL,\r\n            'has_address_structured', v_address_structured IS NOT NULL,\r\n            'raw_metadata_keys', jsonb_object_keys(v_metadata)\r\n          ));\r\n\r\n  -- ========================================================================\r\n  -- CREAR REGISTRO EN public.users\r\n  -- ========================================================================\r\n  \r\n  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)\r\n  VALUES (\r\n    NEW.id, \r\n    v_email, \r\n    v_role, \r\n    v_name, \r\n    v_phone, \r\n    now(), \r\n    now(), \r\n    NEW.email_confirmed_at IS NOT NULL\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = EXCLUDED.email,\r\n    role = EXCLUDED.role,\r\n    name = EXCLUDED.name,\r\n    phone = EXCLUDED.phone,\r\n    email_confirm = EXCLUDED.email_confirm,\r\n    updated_at = now();\r\n\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_new_user_signup_v2', 'USER_CREATED', v_role, NEW.id, v_email, \r\n          jsonb_build_object('name', v_name, 'phone', v_phone));\r\n\r\n  -- ========================================================================\r\n  -- CREAR PERFILES SEGÚN ROL\r\n  -- ========================================================================\r\n  \r\n  CASE v_role\r\n    \r\n    -- ======================================================================\r\n    -- 🎯 ROL: CLIENT (AQUÍ ESTÁ EL FIX)\r\n    -- ======================================================================\r\n    WHEN 'client' THEN\r\n      \r\n      -- Crear client_profile CON UBICACIÓN ✅\r\n      INSERT INTO public.client_profiles (\r\n        user_id, \r\n        status, \r\n        address,\r\n        lat,\r\n        lon,\r\n        address_structured,\r\n        created_at, \r\n        updated_at\r\n      )\r\n      VALUES (\r\n        NEW.id, \r\n        'active',\r\n        v_address,\r\n        v_lat,\r\n        v_lon,\r\n        v_address_structured,\r\n        now(), \r\n        now()\r\n      )\r\n      ON CONFLICT (user_id) DO UPDATE \r\n      SET \r\n        address = COALESCE(EXCLUDED.address, client_profiles.address),\r\n        lat = COALESCE(EXCLUDED.lat, client_profiles.lat),\r\n        lon = COALESCE(EXCLUDED.lon, client_profiles.lon),\r\n        address_structured = COALESCE(EXCLUDED.address_structured, client_profiles.address_structured),\r\n        updated_at = now();\r\n\r\n      -- Log con detalles de ubicación guardada\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object(\r\n                'table', 'client_profiles',\r\n                'address_saved', v_address,\r\n                'lat_saved', v_lat,\r\n                'lon_saved', v_lon,\r\n                'address_structured_saved', v_address_structured\r\n              ));\r\n\r\n      -- Crear account\r\n      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n      VALUES (NEW.id, 'client', 0.0, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE\r\n      SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('account_type', 'client'));\r\n\r\n      -- Crear user_preferences\r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO NOTHING;\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'USER_PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);\r\n    \r\n    -- ======================================================================\r\n    -- 🍔 ROL: RESTAURANT (NO SE TOCA)\r\n    -- ======================================================================\r\n    WHEN 'restaurant' THEN\r\n      \r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'RESTAURANT_SKIPPED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('reason', 'Se usa RPC register_restaurant_atomic()'));\r\n    \r\n    -- ======================================================================\r\n    -- 🚗 ROL: DELIVERY_AGENT (NO SE TOCA)\r\n    -- ======================================================================\r\n    WHEN 'delivery_agent' THEN\r\n      \r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'DELIVERY_SKIPPED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('reason', 'Se usa RPC register_delivery_agent_atomic()'));\r\n    \r\n    -- ======================================================================\r\n    -- 👑 ROL: ADMIN (NO SE TOCA)\r\n    -- ======================================================================\r\n    WHEN 'admin' THEN\r\n      \r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO NOTHING;\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'ADMIN_PROFILE_CREATED', v_role, NEW.id, v_email, NULL);\r\n    \r\n    -- ======================================================================\r\n    -- ⚠️ ROL INVÁLIDO\r\n    -- ======================================================================\r\n    ELSE\r\n      \r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_new_user_signup_v2', 'ERROR_INVALID_ROLE', v_role, NEW.id, v_email, \r\n              jsonb_build_object('invalid_role', v_role));\r\n      \r\n      RAISE EXCEPTION 'Rol inválido: %. Los roles permitidos son: client, restaurant, delivery_agent, admin', v_role;\r\n      \r\n  END CASE;\r\n\r\n  -- ========================================================================\r\n  -- LOG SUCCESS\r\n  -- ========================================================================\r\n  \r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_new_user_signup_v2', 'SUCCESS', v_role, NEW.id, v_email, \r\n          jsonb_build_object('completed_at', now()));\r\n\r\n  RETURN NEW;\r\n\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    -- Log ERROR detallado\r\n    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n    VALUES ('handle_new_user_signup_v2', 'ERROR', v_role, NEW.id, v_email, \r\n            jsonb_build_object(\r\n              'error_message', SQLERRM,\r\n              'error_state', SQLSTATE,\r\n              'error_detail', SQLERRM\r\n            ));\r\n    \r\n    RAISE;\r\n    \r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "handle_user_signup",
    "arguments": "",
    "source_code": "\r\nDECLARE\r\n  v_email TEXT;\r\n  v_role TEXT;\r\n  v_name TEXT;\r\n  v_phone TEXT;\r\n  v_metadata JSONB;\r\nBEGIN\r\n  v_email := NEW.email;\r\n  v_metadata := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);\r\n  v_role := COALESCE(v_metadata->>'role', 'client');\r\n  v_name := COALESCE(v_metadata->>'name', split_part(v_email, '@', 1));\r\n  v_phone := v_metadata->>'phone';\r\n\r\n  -- Normalizar a INGLÉS\r\n  v_role := CASE lower(v_role)\r\n    WHEN 'cliente' THEN 'client'\r\n    WHEN 'client' THEN 'client'\r\n    WHEN 'restaurante' THEN 'restaurant'\r\n    WHEN 'restaurant' THEN 'restaurant'\r\n    WHEN 'repartidor' THEN 'delivery_agent'\r\n    WHEN 'delivery_agent' THEN 'delivery_agent'\r\n    WHEN 'delivery' THEN 'delivery_agent'\r\n    WHEN 'admin' THEN 'admin'\r\n    ELSE 'client'\r\n  END;\r\n\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_user_signup', 'START', v_role, NEW.id, v_email, \r\n          jsonb_build_object('input_role', v_metadata->>'role', 'normalized_role', v_role));\r\n\r\n  INSERT INTO public.users (id, email, role, name, phone, created_at, updated_at, email_confirm)\r\n  VALUES (NEW.id, v_email, v_role, v_name, v_phone, now(), now(), false)\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET email = EXCLUDED.email, role = EXCLUDED.role, name = EXCLUDED.name, \r\n      phone = EXCLUDED.phone, updated_at = now();\r\n\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_user_signup', 'USER_CREATED', v_role, NEW.id, v_email, \r\n          jsonb_build_object('name', v_name, 'phone', v_phone));\r\n\r\n  CASE v_role\r\n    \r\n    WHEN 'client' THEN\r\n      \r\n      INSERT INTO public.client_profiles (user_id, status, created_at, updated_at)\r\n      VALUES (NEW.id, 'active', now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'PROFILE_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('table', 'client_profiles'));\r\n\r\n      INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n      VALUES (NEW.id, 'client', 0.0, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'ACCOUNT_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('account_type', 'client'));\r\n\r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);\r\n\r\n    WHEN 'restaurant' THEN\r\n      \r\n      INSERT INTO public.restaurants (user_id, name, status, created_at, updated_at)\r\n      VALUES (NEW.id, v_name, 'pending', now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'RESTAURANT_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('status', 'pending'));\r\n\r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);\r\n\r\n    WHEN 'delivery_agent' THEN\r\n      \r\n      INSERT INTO public.delivery_agent_profiles (user_id, account_state, created_at, updated_at)\r\n      VALUES (NEW.id, 'pending', now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'DELIVERY_PROFILE_CREATED', v_role, NEW.id, v_email, \r\n              jsonb_build_object('account_state', 'pending'));\r\n\r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'PREFERENCES_CREATED', v_role, NEW.id, v_email, NULL);\r\n\r\n    WHEN 'admin' THEN\r\n      \r\n      INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n      VALUES (NEW.id, now(), now())\r\n      ON CONFLICT (user_id) DO UPDATE SET updated_at = now();\r\n\r\n      INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n      VALUES ('handle_user_signup', 'ADMIN_SETUP', v_role, NEW.id, v_email, NULL);\r\n\r\n    ELSE\r\n      RAISE EXCEPTION 'Rol inválido: %', v_role;\r\n      \r\n  END CASE;\r\n\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_user_signup', 'SUCCESS', v_role, NEW.id, v_email, \r\n          jsonb_build_object('completed_at', now()));\r\n\r\n  RETURN NEW;\r\n\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n    VALUES ('handle_user_signup', 'ERROR', v_role, NEW.id, v_email, \r\n            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));\r\n    RAISE;\r\n    \r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "insert_user_to_auth",
    "arguments": "email text, password text",
    "source_code": "\nDECLARE\n  user_id uuid;\n  encrypted_pw text;\nBEGIN\n  user_id := gen_random_uuid();\n  encrypted_pw := crypt(password, gen_salt('bf'));\n  \n  INSERT INTO auth.users\n    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, recovery_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, email_change, email_change_token_new, recovery_token)\n  VALUES\n    (gen_random_uuid(), user_id, 'authenticated', 'authenticated', email, encrypted_pw, '2023-05-03 19:41:43.585805+00', '2023-04-22 13:10:03.275387+00', '2023-04-22 13:10:31.458239+00', '{\"provider\":\"email\",\"providers\":[\"email\"]}', '{}', '2023-05-03 19:41:43.580424+00', '2023-05-03 19:41:43.585948+00', '', '', '', '');\n  \n  INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)\n  VALUES\n    (gen_random_uuid(), user_id, format('{\"sub\":\"%s\",\"email\":\"%s\"}', user_id::text, email)::jsonb, 'email', '2023-05-03 19:41:43.582456+00', '2023-05-03 19:41:43.582497+00', '2023-05-03 19:41:43.582497+00');\n  \n  RETURN user_id;\nEND;\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "is_current_user_admin",
    "arguments": "",
    "source_code": "\r\n  SELECT EXISTS (\r\n    SELECT 1 \r\n    FROM public.users \r\n    WHERE id = auth.uid() \r\n      AND role = 'admin'\r\n  );\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "is_user_admin",
    "arguments": "user_uuid uuid DEFAULT auth.uid()",
    "source_code": "\r\n  SELECT EXISTS (\r\n    SELECT 1 \r\n    FROM public.users \r\n    WHERE id = user_uuid \r\n      AND role = 'admin'\r\n  );\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "log_auth_user_insert",
    "arguments": "",
    "source_code": " BEGIN INSERT INTO public.system_debug_log(tag, data) VALUES ( 'auth_user_insert', jsonb_build_object( 'new_id', NEW.id, 'email', NEW.email, 'meta', NEW.raw_user_meta_data ) ); RETURN NEW; END; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "mark_user_login",
    "arguments": "",
    "source_code": " begin insert into public.user_preferences (user_id, first_login_at, last_login_at, login_count) values (auth.uid(), now(), now(), 1) on conflict (user_id) do update set last_login_at = now(), first_login_at = coalesce(public.user_preferences.first_login_at, excluded.first_login_at), login_count = public.user_preferences.login_count + 1; end; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "normalize_user_role",
    "arguments": "p_role text",
    "source_code": " SELECT CASE lower(trim($1)) WHEN 'cliente' THEN 'client' WHEN 'client' THEN 'client' WHEN 'restaurante' THEN 'restaurant' WHEN 'restaurant' THEN 'restaurant' WHEN 'repartidor' THEN 'delivery_agent' WHEN 'delivery_agent' THEN 'delivery_agent' WHEN 'admin' THEN 'admin' WHEN 'platform' THEN 'platform' ELSE 'client' END "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "repair_user_registration_misclassification",
    "arguments": "p_user_id uuid",
    "source_code": "\r\nDECLARE\r\n  v_has_restaurant boolean;\r\n  v_account_id uuid;\r\nBEGIN\r\n  SELECT EXISTS(SELECT 1 FROM public.restaurants WHERE user_id = p_user_id) INTO v_has_restaurant;\r\n  IF NOT v_has_restaurant THEN\r\n    RETURN jsonb_build_object('success', false, 'error', 'No restaurant for this user');\r\n  END IF;\r\n\r\n  -- Set role and account type\r\n  UPDATE public.users SET role = 'restaurant', updated_at = now() WHERE id = p_user_id;\r\n\r\n  SELECT id INTO v_account_id FROM public.accounts WHERE user_id = p_user_id LIMIT 1;\r\n  IF v_account_id IS NULL THEN\r\n    INSERT INTO public.accounts (user_id, account_type, balance, created_at, updated_at)\r\n    VALUES (p_user_id, 'restaurant', 0.0, now(), now())\r\n    RETURNING id INTO v_account_id;\r\n  ELSE\r\n    UPDATE public.accounts SET account_type = 'restaurant', updated_at = now() WHERE id = v_account_id;\r\n  END IF;\r\n\r\n  -- Remove client profile if present\r\n  DELETE FROM public.client_profiles WHERE user_id = p_user_id;\r\n\r\n  RETURN jsonb_build_object('success', true, 'account_id', v_account_id);\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "rpc_get_user_location",
    "arguments": "p_user_id uuid",
    "source_code": " select ST_Y(current_location::geometry)::double precision as lat, ST_X(current_location::geometry)::double precision as lon, updated_at from public.users where id = p_user_id limit 1; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "set_user_phone_if_missing",
    "arguments": "p_user_id uuid, p_phone text",
    "source_code": "\r\nDECLARE\r\n  v_updated boolean := false;\r\nBEGIN\r\n  UPDATE public.users SET phone = p_phone, updated_at = now()\r\n  WHERE id = p_user_id AND (phone IS NULL OR phone = '');\r\n  -- FOUND is true if the previous SQL statement affected at least one row\r\n  v_updated := FOUND;\r\n  RETURN jsonb_build_object('success', true, 'data', jsonb_build_object('updated', v_updated), 'error', NULL);\r\nEXCEPTION WHEN OTHERS THEN\r\n  RETURN jsonb_build_object('success', false, 'data', NULL, 'error', SQLERRM);\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "set_user_phone_if_missing_safe",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "source_code": "\r\nBEGIN\r\n  BEGIN\r\n    -- Call legacy function if present (works regardless of its return type)\r\n    PERFORM public.set_user_phone_if_missing(p_user_id, p_phone);\r\n    RETURN;\r\n  EXCEPTION\r\n    WHEN undefined_function THEN\r\n      -- Fallback to v2 if legacy is not defined\r\n      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);\r\n      RETURN;\r\n    WHEN OTHERS THEN\r\n      -- If legacy exists but fails, do not block; try v2 as best-effort\r\n      RAISE NOTICE 'legacy set_user_phone_if_missing failed: %', SQLERRM;\r\n      PERFORM public.set_user_phone_if_missing_v2(p_user_id, p_phone);\r\n      RETURN;\r\n  END;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "set_user_phone_if_missing_v2",
    "arguments": "p_user_id uuid, p_phone text DEFAULT NULL::text",
    "source_code": "\r\nDECLARE\r\n  v_phone   TEXT;\r\n  v_updated INT;\r\nBEGIN\r\n  IF p_user_id IS NULL THEN\r\n    RETURN FALSE;\r\n  END IF;\r\n\r\n  -- Prefer explicit phone; otherwise use auth.users raw_user_meta_data->>'phone'\r\n  v_phone := NULLIF(btrim(COALESCE(p_phone,\r\n    (SELECT au.raw_user_meta_data->>'phone'\r\n       FROM auth.users au\r\n      WHERE au.id = p_user_id)\r\n  )), '');\r\n\r\n  IF v_phone IS NULL THEN\r\n    RETURN FALSE;\r\n  END IF;\r\n\r\n  UPDATE public.users u\r\n     SET phone = v_phone,\r\n         updated_at = NOW()\r\n   WHERE u.id = p_user_id\r\n     AND COALESCE(btrim(u.phone), '') = ''\r\n  RETURNING 1 INTO v_updated;\r\n\r\n  RETURN COALESCE(v_updated, 0) > 0;\r\nEXCEPTION WHEN OTHERS THEN\r\n  -- Do not block callers; just log and return false\r\n  RAISE NOTICE 'set_user_phone_if_missing_v2: %', SQLERRM;\r\n  RETURN FALSE;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "trg_debug_log_public_users_after_insert",
    "arguments": "",
    "source_code": " BEGIN INSERT INTO public._debug_events(source, event, data) VALUES ('public.users', 'after_insert', to_jsonb(NEW)); RETURN NEW; END; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "trg_log_public_users_after_insert",
    "arguments": "",
    "source_code": " BEGIN INSERT INTO public.debug_user_signup_log(source, event, role, user_id, email, details) VALUES ('public.users', 'after_insert', NEW.role, NEW.id, NEW.email, jsonb_build_object('name', NEW.name, 'created_at', now())); RETURN NEW; EXCEPTION WHEN others THEN RETURN NEW; END "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "trg_set_user_phone_from_metadata",
    "arguments": "",
    "source_code": "\r\nBEGIN\r\n  PERFORM public.set_user_phone_if_missing(NEW.user_id, NULL);\r\n  RETURN NEW;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "trg_users_normalize_role",
    "arguments": "",
    "source_code": " BEGIN NEW.role := public.normalize_user_role(NEW.role); RETURN NEW; END; "
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "update_user_location",
    "arguments": "p_address text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lon double precision DEFAULT NULL::double precision, p_address_structured jsonb DEFAULT NULL::jsonb",
    "source_code": "\r\nbegin\r\n  -- uses auth.uid() to determine user\r\n  return public.update_client_default_address(\r\n    auth.uid(), p_address, p_lat, p_lon, p_address_structured\r\n  );\r\nend;\r\n"
  },
  {
    "seccion": "FUNCIONES DE USUARIO",
    "function_name": "update_user_preferences_updated_at",
    "arguments": "",
    "source_code": "\r\nBEGIN\r\n  NEW.updated_at = NOW();\r\n  RETURN NEW;\r\nEND;\r\n"
  }
]

-- 4.2 Listar triggers en la tabla public.users:
[
  {
    "seccion": "TRIGGERS EN PUBLIC.USERS",
    "trigger_name": "users_updated_at_trigger",
    "trigger_type": 19,
    "is_enabled": "O",
    "trigger_definition": "CREATE TRIGGER users_updated_at_trigger BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column()"
  }
]

-- 4.3 Listar triggers en la tabla public.client_profiles: 0


-- ============================================================
-- PARTE 5: VERIFICAR LOGS DE DEBUG (si existen registros)
-- ============================================================

-- 5.1 Ver últimos logs de debug_user_signup_log:
[
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 297,
    "source": "delivery_agent_profiles",
    "event": "after_upsert",
    "role": "delivery_agent",
    "user_id": "f3f6dee8-6fd9-4986-9be4-5d1788bfb51d",
    "email": "walfre.am@gmail.com",
    "details": {
      "profile": {
        "status": "pending",
        "user_id": "f3f6dee8-6fd9-4986-9be4-5d1788bfb51d",
        "created_at": "2025-11-11T04:59:52.562228+00:00",
        "updated_at": "2025-11-11T04:59:52.562228+00:00",
        "vehicle_type": null,
        "account_state": "pending",
        "vehicle_color": null,
        "vehicle_model": null,
        "vehicle_plate": null,
        "profile_image_url": null,
        "vehicle_photo_url": null,
        "id_document_back_url": null,
        "onboarding_completed": false,
        "id_document_front_url": null,
        "vehicle_insurance_url": null,
        "emergency_contact_name": null,
        "emergency_contact_phone": null,
        "onboarding_completed_at": null,
        "vehicle_registration_url": null
      }
    },
    "created_at": "2025-11-11 04:59:52.562228+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 296,
    "source": "delivery_agent_profiles",
    "event": "after_upsert",
    "role": "delivery_agent",
    "user_id": "1ffe0bd6-1d58-460b-9b5a-cbf3e8f32f98",
    "email": "walfre.am@gmail.com",
    "details": {
      "profile": {
        "status": "pending",
        "user_id": "1ffe0bd6-1d58-460b-9b5a-cbf3e8f32f98",
        "created_at": "2025-11-11T04:42:16.172013+00:00",
        "updated_at": "2025-11-11T04:42:16.172013+00:00",
        "vehicle_type": null,
        "account_state": "pending",
        "vehicle_color": null,
        "vehicle_model": null,
        "vehicle_plate": null,
        "profile_image_url": null,
        "vehicle_photo_url": null,
        "id_document_back_url": null,
        "onboarding_completed": false,
        "id_document_front_url": null,
        "vehicle_insurance_url": null,
        "emergency_contact_name": null,
        "emergency_contact_phone": null,
        "onboarding_completed_at": null,
        "vehicle_registration_url": null
      }
    },
    "created_at": "2025-11-11 04:42:16.172013+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 295,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "0494590b-34c0-4573-9704-b33f04420eaf",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Juan Jaime",
      "created_at": "2025-11-10T22:42:36.338363+00:00"
    },
    "created_at": "2025-11-10 22:42:36.338363+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 294,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "dcab9481-45ae-4be3-9618-4c1ca5432b9f",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Juan Jaiime",
      "created_at": "2025-11-10T21:49:36.28309+00:00"
    },
    "created_at": "2025-11-10 21:49:36.28309+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 293,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "bb0d2127-2d42-4730-88da-6b39592675a2",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Juan JAime",
      "created_at": "2025-11-10T21:31:22.804358+00:00"
    },
    "created_at": "2025-11-10 21:31:22.804358+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 292,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "0e2580d9-4fc9-40d2-92c2-2d8dad164133",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Juan Jaime",
      "created_at": "2025-11-10T21:27:22.315368+00:00"
    },
    "created_at": "2025-11-10 21:27:22.315368+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 291,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "05716c34-3200-4854-ae83-5c6a1b80cc3a",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Jimmy Tco",
      "created_at": "2025-11-10T04:35:46.690541+00:00"
    },
    "created_at": "2025-11-10 04:35:46.690541+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 290,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "594390f0-397c-4a8f-9b05-fdcd5065a16b",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Juan Jaime",
      "created_at": "2025-11-10T04:09:52.303234+00:00"
    },
    "created_at": "2025-11-10 04:09:52.303234+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 285,
    "source": "public.users",
    "event": "after_insert",
    "role": "restaurant",
    "user_id": "bd466f52-dc67-4459-abbf-4eba04b30a1e",
    "email": "walfre.am@gmail.com",
    "details": {
      "name": "Jimmy Tacos",
      "created_at": "2025-11-10T03:23:52.111098+00:00"
    },
    "created_at": "2025-11-10 03:23:52.111098+00"
  },
  {
    "seccion": "DEBUG SIGNUP LOG",
    "id": 288,
    "source": "master_handle_signup",
    "event": "PREFERENCES_CREATED",
    "role": "restaurante",
    "user_id": "bd466f52-dc67-4459-abbf-4eba04b30a1e",
    "email": "walfre.am@gmail.com",
    "details": null,
    "created_at": "2025-11-10 03:23:52.111098+00"
  }
]

-- 5.2 Ver últimos logs de function_logs relacionados con signup: 0


