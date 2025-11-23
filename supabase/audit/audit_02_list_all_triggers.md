[
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "_trg_call_ensure_client_profile_and_account",
    "function_source": "CREATE OR REPLACE FUNCTION public._trg_call_ensure_client_profile_and_account()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  PERFORM public.ensure_client_profile_and_account(NEW.id);\r\n  RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "audit_delivery_agent_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.audit_delivery_agent_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nDECLARE\r\n  v_user_role TEXT;\r\n  v_call_stack TEXT;\r\nBEGIN\r\n  -- Obtener el rol del usuario que se intenta insertar\r\n  SELECT role INTO v_user_role\r\n  FROM public.users\r\n  WHERE id = NEW.user_id;\r\n  \r\n  -- Obtener el call stack\r\n  GET DIAGNOSTICS v_call_stack = PG_CONTEXT;\r\n  \r\n  -- Registrar en el log de auditoría\r\n  INSERT INTO delivery_agent_profiles_audit_log (\r\n    user_id,\r\n    user_role,\r\n    call_stack,\r\n    db_user,\r\n    auth_uid,\r\n    ip_address\r\n  ) VALUES (\r\n    NEW.user_id,\r\n    COALESCE(v_user_role, 'ROLE_NOT_FOUND'),\r\n    v_call_stack,\r\n    current_user::TEXT,\r\n    auth.uid(),\r\n    inet_client_addr()::TEXT\r\n  );\r\n  \r\n  -- Si el usuario NO es repartidor, BLOQUEAR la inserción\r\n  IF v_user_role IS NULL OR v_user_role NOT IN ('repartidor', 'delivery_agent') THEN\r\n    RAISE EXCEPTION 'BLOCKED: Cannot create delivery_agent_profile for user with role: %. User ID: %', \r\n      COALESCE(v_user_role, 'NULL'), NEW.user_id;\r\n  END IF;\r\n  \r\n  -- Si es repartidor, permitir la inserción\r\n  RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "create_account_on_user_approval",
    "function_source": "CREATE OR REPLACE FUNCTION public.create_account_on_user_approval()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nDECLARE\r\n    mapped_account_type TEXT;\r\nBEGIN\r\n    -- Solo procesar cuando se actualiza status a 'approved'\r\n    IF TG_OP = 'UPDATE' AND \r\n       OLD.status != 'approved' AND \r\n       NEW.status = 'approved' THEN\r\n        \r\n        -- Mapear rol del usuario a tipo de cuenta\r\n        CASE NEW.role\r\n            WHEN 'restaurante' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'restaurant' THEN\r\n                mapped_account_type := 'restaurant';\r\n            WHEN 'delivery_agent' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            WHEN 'repartidor' THEN\r\n                mapped_account_type := 'delivery_agent';\r\n            ELSE\r\n                -- No crear cuenta para admin o cliente\r\n                RETURN NEW;\r\n        END CASE;\r\n        \r\n        -- Verificar si ya existe una cuenta para este usuario\r\n        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = NEW.id) THEN\r\n            -- Crear cuenta con balance inicial 0\r\n            INSERT INTO public.accounts (\r\n                id,\r\n                user_id,\r\n                account_type,\r\n                balance,\r\n                created_at,\r\n                updated_at\r\n            ) VALUES (\r\n                gen_random_uuid(),\r\n                NEW.id,\r\n                mapped_account_type,\r\n                0.0,\r\n                NOW(),\r\n                NOW()\r\n            );\r\n            \r\n            RAISE NOTICE 'Cuenta creada para usuario % con tipo %', NEW.id, mapped_account_type;\r\n        ELSE\r\n            RAISE NOTICE 'Cuenta ya existe para usuario %', NEW.id;\r\n        END IF;\r\n    END IF;\r\n    \r\n    RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "delivery_agent_profiles_guard",
    "function_source": "CREATE OR REPLACE FUNCTION public.delivery_agent_profiles_guard()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN IF NOT EXISTS ( SELECT 1 FROM public.users u WHERE u.id = NEW.user_id AND COALESCE(u.role,'') IN ('repartidor','delivery_agent') ) THEN INSERT INTO public._debug_events(source, event, data) VALUES ('delivery_agent_profiles_guard', 'skip_insert_non_delivery', jsonb_build_object('user_id', NEW.user_id)); RETURN NULL; END IF; RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_client",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_client()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  uname text;\r\nbegin\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_client disparado para user_id=%', new.user_id;\r\n  \r\n  select coalesce(u.name, u.email, 'Cliente') into uname\r\n  from public.users u where u.id = new.user_id;\r\n\r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'user', new.user_id, 'Nuevo cliente registrado',\r\n          coalesce(uname, 'Cliente') || ' creó una cuenta',\r\n          jsonb_build_object('user_id', new.user_id));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para cliente: %', uname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para cliente %: %', new.user_id, sqlerrm;\r\n    return new;\r\nend;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_delivery_agent",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_delivery_agent()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  uname text;\r\nbegin\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_delivery_agent disparado para user_id=%', new.user_id;\r\n  \r\n  select coalesce(u.name, u.email, 'Repartidor') into uname\r\n  from public.users u where u.id = new.user_id;\r\n\r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'delivery_agent', new.user_id, 'Nuevo repartidor registrado',\r\n          coalesce(uname, 'Repartidor') || ' se registró y espera revisión',\r\n          jsonb_build_object('user_id', new.user_id, 'account_state', new.account_state));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para repartidor: %', uname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para repartidor %: %', new.user_id, sqlerrm;\r\n    return new;\r\nend;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "fn_notify_admin_on_new_restaurant",
    "function_source": "CREATE OR REPLACE FUNCTION public.fn_notify_admin_on_new_restaurant()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\ndeclare\r\n  rname text;\r\nbegin\r\n  -- Log para debugging\r\n  raise notice '🔔 [TRIGGER] fn_notify_admin_on_new_restaurant disparado para restaurant_id=%', new.id;\r\n  \r\n  rname := coalesce(new.name, 'Restaurante sin nombre');\r\n  \r\n  insert into public.admin_notifications(category, entity_type, entity_id, title, message, metadata)\r\n  values ('registration', 'restaurant', new.id, 'Nuevo restaurante registrado',\r\n          rname || ' se registró y está en revisión',\r\n          jsonb_build_object('restaurant_id', new.id, 'status', new.status, 'user_id', new.user_id));\r\n  \r\n  raise notice '✅ [TRIGGER] Notificación creada para restaurante: %', rname;\r\n  return new;\r\nexception\r\n  when others then\r\n    raise warning '❌ [TRIGGER] Error creando notificación para restaurante %: %', new.id, sqlerrm;\r\n    return new; -- No fallar el insert del restaurante si falla la notificación\r\nend;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "guard_delivery_profile_role",
    "function_source": "CREATE OR REPLACE FUNCTION public.guard_delivery_profile_role()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ DECLARE u record; BEGIN SELECT id, email, role INTO u FROM public.users WHERE id = NEW.user_id; IF u.id IS NULL THEN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) VALUES ('delivery_agent_profiles','before_insert_denied', NEW.user_id, NULL, NULL, jsonb_build_object('reason','user_not_found')); RAISE EXCEPTION 'user_not_found'; END IF; IF lower(coalesce(u.role,'')) NOT IN ('repartidor','delivery_agent') THEN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) VALUES ('delivery_agent_profiles','before_insert_denied', u.id, u.email, u.role, jsonb_build_object('reason','invalid_role','payload', row_to_json(NEW)::jsonb)); RAISE EXCEPTION 'invalid_role_for_delivery_profile'; END IF; RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "handle_new_user",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_new_user()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nDECLARE\r\n  v_email TEXT;\r\n  v_role TEXT := 'cliente'; -- Por defecto todos son clientes\r\nBEGIN\r\n  -- Obtener email del nuevo usuario en auth.users\r\n  v_email := NEW.email;\r\n  \r\n  -- Log de inicio (para debugging)\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n  VALUES ('handle_new_user', 'START', v_role, NEW.id, v_email, jsonb_build_object('raw_user_meta_data', NEW.raw_user_meta_data));\r\n\r\n  -- 📝 PASO 1: Insertar en public.users\r\n  INSERT INTO public.users (id, email, role, name, created_at, updated_at, email_confirm)\r\n  VALUES (\r\n    NEW.id,\r\n    v_email,\r\n    v_role,\r\n    COALESCE(NEW.raw_user_meta_data->>'name', v_email), -- Usar nombre del meta_data o email\r\n    now(),\r\n    now(),\r\n    false\r\n  )\r\n  ON CONFLICT (id) DO UPDATE\r\n  SET \r\n    email = EXCLUDED.email,\r\n    updated_at = now();\r\n\r\n  -- Log de public.users creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'USER_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 2: Crear client_profile (status='active' es el default)\r\n  INSERT INTO public.client_profiles (user_id, created_at, updated_at)\r\n  VALUES (NEW.id, now(), now())\r\n  ON CONFLICT (user_id) DO UPDATE\r\n  SET updated_at = now();\r\n\r\n  -- Log de client_profile creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'CLIENT_PROFILE_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 3: Crear cuenta (account) para el cliente\r\n  INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)\r\n  VALUES (uuid_generate_v4(), NEW.id, 'client', 0.00, now(), now())\r\n  ON CONFLICT DO NOTHING;\r\n\r\n  -- Log de account creado\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'ACCOUNT_CREATED', v_role, NEW.id, v_email);\r\n\r\n  -- 📝 PASO 4: Crear user_preferences\r\n  INSERT INTO public.user_preferences (user_id, created_at, updated_at)\r\n  VALUES (NEW.id, now(), now())\r\n  ON CONFLICT (user_id) DO NOTHING;\r\n\r\n  -- Log de SUCCESS\r\n  INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email)\r\n  VALUES ('handle_new_user', 'SUCCESS', v_role, NEW.id, v_email);\r\n\r\n  RETURN NEW;\r\nEXCEPTION\r\n  WHEN OTHERS THEN\r\n    -- Log de ERROR con detalles\r\n    INSERT INTO public.debug_user_signup_log (source, event, role, user_id, email, details)\r\n    VALUES ('handle_new_user', 'ERROR', v_role, NEW.id, v_email, \r\n            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));\r\n    \r\n    -- Re-lanzar el error para que Supabase Auth devuelva 500\r\n    RAISE;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "handle_user_email_confirmation",
    "function_source": "CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$\r\nBEGIN\r\n  -- Solo actualizar si email_confirmed_at cambió de null a no-null\r\n  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN\r\n    UPDATE public.users \r\n    SET \r\n      email_confirm = true,\r\n      updated_at = NOW()\r\n    WHERE id = NEW.id;\r\n  END IF;\r\n  RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "log_auth_user_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.log_auth_user_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.system_debug_log(tag, data) VALUES ( 'auth_user_insert', jsonb_build_object( 'new_id', NEW.id, 'email', NEW.email, 'meta', NEW.raw_user_meta_data ) ); RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "log_dap_after_upsert",
    "function_source": "CREATE OR REPLACE FUNCTION public.log_dap_after_upsert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.debug_user_signup_log(source, event, user_id, email, role, details) SELECT 'delivery_agent_profiles','after_upsert', u.id, u.email, u.role, jsonb_build_object('profile', row_to_json(NEW)::jsonb) FROM public.users u WHERE u.id = NEW.user_id; RETURN NEW; END $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "trg_debug_log_delivery_agent_profiles",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_debug_log_delivery_agent_profiles()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN INSERT INTO public._debug_events(source, event, data) VALUES ('delivery_agent_profiles', TG_OP, to_jsonb(NEW)); RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "trg_debug_log_public_users_after_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_debug_log_public_users_after_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\nAS $function$ BEGIN INSERT INTO public._debug_events(source, event, data) VALUES ('public.users', 'after_insert', to_jsonb(NEW)); RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "trg_log_public_users_after_insert",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_log_public_users_after_insert()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$ BEGIN INSERT INTO public.debug_user_signup_log(source, event, role, user_id, email, details) VALUES ('public.users', 'after_insert', NEW.role, NEW.id, NEW.email, jsonb_build_object('name', NEW.name, 'created_at', now())); RETURN NEW; EXCEPTION WHEN others THEN RETURN NEW; END $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "trg_set_user_phone_from_metadata",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_set_user_phone_from_metadata()\n RETURNS trigger\n LANGUAGE plpgsql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\r\nBEGIN\r\n  PERFORM public.set_user_phone_if_missing(NEW.user_id, NULL);\r\n  RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "trg_users_normalize_role",
    "function_source": "CREATE OR REPLACE FUNCTION public.trg_users_normalize_role()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$ BEGIN NEW.role := public.normalize_user_role(NEW.role); RETURN NEW; END; $function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "update_restaurant_completion_trigger",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_restaurant_completion_trigger()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\r\nBEGIN\r\n    NEW.profile_completion_percentage := calculate_restaurant_completion(NEW.id);\r\n    RETURN NEW;\r\nEND;\r\n$function$\n"
  },
  {
    "step": "TRIGGER_FUNCTION_CODE",
    "schema_name": "public",
    "function_name": "update_updated_at_column",
    "function_source": "CREATE OR REPLACE FUNCTION public.update_updated_at_column()\n RETURNS trigger\n LANGUAGE plpgsql\nAS $function$\nBEGIN\n  NEW.updated_at = NOW();\n  RETURN NEW;\nEND;\n$function$\n"
  }
]