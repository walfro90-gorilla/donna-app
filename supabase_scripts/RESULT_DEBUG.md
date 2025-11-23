-- 1️⃣ Ver logs del trigger de confirmación (trigger_debug_log): 0, no existen ningun registro en la tabla.

-- 2️⃣ Ver usuarios SIN confirmar email (email_confirm = false):
[
  {
    "seccion": "USUARIOS SIN CONFIRMAR",
    "id": "b601143a-17bb-413c-bfaf-71cccea8ed7a",
    "email": "walfre.am@gmail.com",
    "name": "TESTO",
    "role": "client",
    "email_confirm": false,
    "created_at": "2025-11-09 19:03:32.491166+00",
    "email_confirmed_at": null,
    "confirmed_at": null
  },
  {
    "seccion": "USUARIOS SIN CONFIRMAR",
    "id": "4f420d94-3c17-4d24-a022-e610451de5a9",
    "email": "test_v2_1762657280@test.com",
    "name": "Test V2 Client",
    "role": "client",
    "email_confirm": false,
    "created_at": "2025-11-09 03:01:20.205603+00",
    "email_confirmed_at": null,
    "confirmed_at": null
  }
]

-- 3️⃣ Verificar el estado del trigger en auth.users:
[
  {
    "seccion": "ESTADO DEL TRIGGER",
    "trigger_name": "on_auth_email_confirmed",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION handle_email_confirmation()"
  },
  {
    "seccion": "ESTADO DEL TRIGGER",
    "trigger_name": "on_auth_user_created",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION handle_user_signup()"
  },
  {
    "seccion": "ESTADO DEL TRIGGER",
    "trigger_name": "on_auth_user_email_confirmed",
    "event": "UPDATE",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION handle_email_confirmed()"
  },
  {
    "seccion": "ESTADO DEL TRIGGER",
    "trigger_name": "trg_log_auth_user_insert",
    "event": "INSERT",
    "timing": "AFTER",
    "function_call": "EXECUTE FUNCTION log_auth_user_insert()"
  }
]

-- 4️⃣ Políticas RLS de UPDATE en public.users:
[
  {
    "seccion": "POLÍTICAS RLS UPDATE",
    "policyname": "users_update_email_confirm",
    "roles": "{authenticated}",
    "cmd": "UPDATE",
    "condition": "(auth.uid() = id)",
    "with_check": "(auth.uid() = id)"
  },
  {
    "seccion": "POLÍTICAS RLS UPDATE",
    "policyname": "users_update_own",
    "roles": "{authenticated}",
    "cmd": "UPDATE",
    "condition": "(id = auth.uid())",
    "with_check": null
  }
]

-- 5️⃣ Verificar si RLS está habilitado en public.users:
[
  {
    "seccion": "RLS HABILITADO",
    "tablename": "users",
    "rls_enabled": true
  }
]

-- 6️⃣ Ver últimos registros de auth.users (últimos 5):
[
  {
    "seccion": "ÚLTIMOS REGISTROS AUTH.USERS",
    "id": "b601143a-17bb-413c-bfaf-71cccea8ed7a",
    "email": "walfre.am@gmail.com",
    "email_confirmed_at": null,
    "confirmed_at": null,
    "created_at": "2025-11-09 19:03:32.491559+00",
    "updated_at": "2025-11-09 19:03:33.047906+00",
    "last_sign_in_at": null
  },
  {
    "seccion": "ÚLTIMOS REGISTROS AUTH.USERS",
    "id": "4f420d94-3c17-4d24-a022-e610451de5a9",
    "email": "test_v2_1762657280@test.com",
    "email_confirmed_at": null,
    "confirmed_at": null,
    "created_at": "2025-11-09 03:01:20.205603+00",
    "updated_at": "2025-11-09 03:01:20.205603+00",
    "last_sign_in_at": null
  },
  {
    "seccion": "ÚLTIMOS REGISTROS AUTH.USERS",
    "id": "9fd3a562-d607-4b48-9b94-57c9cc6b01a4",
    "email": "platform+payables@doarepartos.com",
    "email_confirmed_at": "2025-10-17 01:28:03.162542+00",
    "confirmed_at": "2025-10-17 01:28:03.162542+00",
    "created_at": "2025-10-17 01:28:03.057993+00",
    "updated_at": "2025-10-17 01:28:03.166941+00",
    "last_sign_in_at": null
  },
  {
    "seccion": "ÚLTIMOS REGISTROS AUTH.USERS",
    "id": "7c6fea48-0fe3-4f2a-92d3-ba5605978d8d",
    "email": "platform+revenue@doarepartos.com",
    "email_confirmed_at": "2025-10-17 01:01:53.258114+00",
    "confirmed_at": "2025-10-17 01:01:53.258114+00",
    "created_at": "2025-10-17 01:01:53.083837+00",
    "updated_at": "2025-10-17 01:01:53.267852+00",
    "last_sign_in_at": null
  },
  {
    "seccion": "ÚLTIMOS REGISTROS AUTH.USERS",
    "id": "94fa1987-7543-423c-8f6c-851753936281",
    "email": "admin@donna.app",
    "email_confirmed_at": "2025-10-15 03:43:09.162903+00",
    "confirmed_at": "2025-10-15 03:43:09.162903+00",
    "created_at": "2025-10-15 03:43:08.872686+00",
    "updated_at": "2025-11-06 02:06:13.328624+00",
    "last_sign_in_at": "2025-11-04 01:57:20.900409+00"
  }
]

-- 7️⃣ Comparar sincronización entre auth.users y public.users: 0 registros.

-- 8️⃣ Ver función que maneja la confirmación:
[
  {
    "seccion": "FUNCIÓN DE CONFIRMACIÓN",
    "function_name": "handle_email_confirmation",
    "source_code": "\r\nBEGIN\r\n  -- Solo actualizar si email_confirmed_at cambió de NULL a un valor\r\n  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN\r\n    \r\n    -- Actualizar public.users.email_confirm\r\n    UPDATE public.users\r\n    SET email_confirm = true,\r\n        updated_at = now()\r\n    WHERE id = NEW.id;\r\n    \r\n    -- Log para debugging\r\n    INSERT INTO public.debug_logs (scope, message, meta)\r\n    VALUES (\r\n      'email_confirmation',\r\n      'Email confirmed',\r\n      jsonb_build_object(\r\n        'user_id', NEW.id,\r\n        'email', NEW.email,\r\n        'confirmed_at', NEW.email_confirmed_at\r\n      )\r\n    );\r\n    \r\n  END IF;\r\n  \r\n  RETURN NEW;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIÓN DE CONFIRMACIÓN",
    "function_name": "handle_email_confirmed",
    "source_code": "\r\nDECLARE\r\n  v_user_exists BOOLEAN;\r\n  v_error_msg TEXT;\r\nBEGIN\r\n  -- Log inicial (solo si función log existe)\r\n  BEGIN\r\n    INSERT INTO public.function_logs (function_name, message, metadata)\r\n    VALUES ('handle_email_confirmed', 'Trigger fired', jsonb_build_object(\r\n      'user_id', NEW.id,\r\n      'email', NEW.email,\r\n      'old_confirmed_at', OLD.email_confirmed_at,\r\n      'new_confirmed_at', NEW.email_confirmed_at\r\n    ));\r\n  EXCEPTION WHEN OTHERS THEN\r\n    -- Ignorar si tabla de logs no existe\r\n    NULL;\r\n  END;\r\n\r\n  -- Verificar si esto es una confirmación de email (NULL → timestamp)\r\n  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN\r\n    \r\n    -- Verificar si el usuario existe en public.users\r\n    SELECT EXISTS(\r\n      SELECT 1 FROM public.users WHERE id = NEW.id\r\n    ) INTO v_user_exists;\r\n    \r\n    IF v_user_exists THEN\r\n      -- Usuario existe: actualizar email_confirm a true\r\n      BEGIN\r\n        UPDATE public.users\r\n        SET \r\n          email_confirm = true,\r\n          updated_at = now()\r\n        WHERE id = NEW.id;\r\n        \r\n        -- Log éxito\r\n        BEGIN\r\n          INSERT INTO public.function_logs (function_name, message, metadata)\r\n          VALUES ('handle_email_confirmed', 'Email confirmed successfully', jsonb_build_object(\r\n            'user_id', NEW.id,\r\n            'email', NEW.email\r\n          ));\r\n        EXCEPTION WHEN OTHERS THEN\r\n          NULL;\r\n        END;\r\n        \r\n      EXCEPTION WHEN OTHERS THEN\r\n        -- CRÍTICO: NO LANZAR ERROR - solo loguear\r\n        v_error_msg := SQLERRM;\r\n        \r\n        BEGIN\r\n          INSERT INTO public.function_logs (function_name, message, metadata, level)\r\n          VALUES ('handle_email_confirmed', 'ERROR updating users table', jsonb_build_object(\r\n            'user_id', NEW.id,\r\n            'email', NEW.email,\r\n            'error', v_error_msg\r\n          ), 'ERROR');\r\n        EXCEPTION WHEN OTHERS THEN\r\n          NULL;\r\n        END;\r\n        \r\n        -- NO ROMPER LA TRANSACCIÓN - dejar que Supabase Auth complete\r\n        -- RETURN NEW permite que el proceso continúe\r\n      END;\r\n    ELSE\r\n      -- Usuario no existe en public.users - esto es extraño pero no fatal\r\n      BEGIN\r\n        INSERT INTO public.function_logs (function_name, message, metadata, level)\r\n        VALUES ('handle_email_confirmed', 'WARNING: user not found in public.users', jsonb_build_object(\r\n          'user_id', NEW.id,\r\n          'email', NEW.email\r\n        ), 'WARNING');\r\n      EXCEPTION WHEN OTHERS THEN\r\n        NULL;\r\n      END;\r\n    END IF;\r\n  END IF;\r\n  \r\n  -- SIEMPRE retornar NEW para no interrumpir el proceso\r\n  RETURN NEW;\r\n  \r\nEXCEPTION WHEN OTHERS THEN\r\n  -- CATCH-ALL: Loguear cualquier error inesperado pero NO FALLAR\r\n  BEGIN\r\n    INSERT INTO public.function_logs (function_name, message, metadata, level)\r\n    VALUES ('handle_email_confirmed', 'CRITICAL ERROR in trigger', jsonb_build_object(\r\n      'user_id', NEW.id,\r\n      'email', NEW.email,\r\n      'error', SQLERRM,\r\n      'sqlstate', SQLSTATE\r\n    ), 'CRITICAL');\r\n  EXCEPTION WHEN OTHERS THEN\r\n    -- Si hasta el log falla, no hacer nada\r\n    NULL;\r\n  END;\r\n  \r\n  -- SIEMPRE retornar NEW - NUNCA romper la confirmación de email\r\n  RETURN NEW;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIÓN DE CONFIRMACIÓN",
    "function_name": "handle_user_email_confirmation",
    "source_code": "\r\nBEGIN\r\n  -- Start log\r\n  BEGIN\r\n    INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)\r\n    VALUES ('email_confirmation', 'START', NEW.id, NEW.email,\r\n            jsonb_build_object(\r\n              'old_email_confirmed_at', OLD.email_confirmed_at,\r\n              'new_email_confirmed_at', NEW.email_confirmed_at,\r\n              'now', now()\r\n            ));\r\n  EXCEPTION WHEN OTHERS THEN\r\n    -- Logging must not break the flow\r\n    NULL;\r\n  END;\r\n\r\n  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN\r\n    -- Transition to confirmed: update public.users\r\n    UPDATE public.users \r\n      SET email_confirm = TRUE,\r\n          updated_at    = now()\r\n    WHERE id = NEW.id;\r\n\r\n    BEGIN\r\n      INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)\r\n      VALUES ('email_confirmation', 'UPDATED_PUBLIC_USERS', NEW.id, NEW.email,\r\n              jsonb_build_object('updated', true));\r\n    EXCEPTION WHEN OTHERS THEN NULL; END;\r\n  ELSE\r\n    -- No relevant change, skip\r\n    BEGIN\r\n      INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)\r\n      VALUES ('email_confirmation', 'SKIP_NO_CHANGE', NEW.id, NEW.email,\r\n              jsonb_build_object('reason', 'no_transition'));\r\n    EXCEPTION WHEN OTHERS THEN NULL; END;\r\n  END IF;\r\n\r\n  RETURN NEW;\r\nEXCEPTION WHEN OTHERS THEN\r\n  -- Log the failure and rethrow to surface upstream (so Supabase returns error)\r\n  BEGIN\r\n    INSERT INTO public.debug_user_signup_log(source, event, user_id, email, details)\r\n    VALUES ('email_confirmation', 'ERROR', NEW.id, NEW.email,\r\n            jsonb_build_object('error', SQLERRM, 'state', SQLSTATE));\r\n  EXCEPTION WHEN OTHERS THEN NULL; END;\r\n  RAISE;\r\nEND;\r\n"
  },
  {
    "seccion": "FUNCIÓN DE CONFIRMACIÓN",
    "function_name": "resend_email_confirmation",
    "source_code": "\r\nDECLARE\r\n  v_user_id uuid;\r\n  v_already_confirmed boolean;\r\n  v_result jsonb;\r\nBEGIN\r\n  -- Buscar usuario por email\r\n  SELECT id, email_confirmed_at IS NOT NULL\r\n  INTO v_user_id, v_already_confirmed\r\n  FROM auth.users\r\n  WHERE email = p_user_email;\r\n\r\n  IF v_user_id IS NULL THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'error', 'Usuario no encontrado',\r\n      'email', p_user_email\r\n    );\r\n  END IF;\r\n\r\n  IF v_already_confirmed THEN\r\n    RETURN jsonb_build_object(\r\n      'success', false,\r\n      'error', 'Email ya confirmado',\r\n      'user_id', v_user_id,\r\n      'email', p_user_email\r\n    );\r\n  END IF;\r\n\r\n  -- Nota: Esta función solo valida, el reenvío real lo hace Supabase Auth\r\n  -- desde el cliente con: supabase.auth.resend({ type: 'signup', email: '...' })\r\n  \r\n  RETURN jsonb_build_object(\r\n    'success', true,\r\n    'message', 'Listo para reenviar - usa supabase.auth.resend() desde cliente',\r\n    'user_id', v_user_id,\r\n    'email', p_user_email\r\n  );\r\nEND;\r\n"
  }
]




