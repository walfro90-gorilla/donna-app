-- =====================================================================
-- 12_create_auto_registration_trigger.sql (OPCIONAL)
-- =====================================================================
-- Crea un trigger que automáticamente registra usuarios en public.users
-- cuando se crean en auth.users
--
-- IMPORTANTE: Este trigger es OPCIONAL. Solo úsalo si quieres que
-- la tabla public.users se sincronice automáticamente con auth.users
-- SIN necesidad de llamar a las funciones register_*
--
-- PROS:
-- ✅ Sincronización automática
-- ✅ Menos código en el cliente
-- ✅ Garantiza que public.users siempre tenga registro
--
-- CONTRAS:
-- ❌ No puedes capturar datos adicionales durante el registro
-- ❌ Todos los usuarios empiezan como 'cliente' por defecto
-- ❌ Requiere que el cliente llame manualmente a register_restaurant
--    o register_delivery_agent DESPUÉS del signUp
-- =====================================================================

-- ====================================
-- FUNCIÓN: handle_new_user
-- ====================================
-- Se ejecuta automáticamente cuando se crea un usuario en auth.users
-- ====================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Insertar usuario en public.users con rol 'cliente' por defecto
  INSERT INTO public.users (
    id,
    email,
    name,
    phone,
    role,
    email_confirm,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', NULL),
    COALESCE(NEW.raw_user_meta_data->>'phone', NULL),
    'cliente',
    false,
    now(),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  -- Crear preferencias de usuario
  INSERT INTO public.user_preferences (
    user_id,
    created_at,
    updated_at
  ) VALUES (
    NEW.id,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- ====================================
-- TRIGGER: on_auth_user_created
-- ====================================
-- Se dispara cuando se crea un nuevo usuario en auth.users
-- ====================================
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ====================================
-- VERIFICACIÓN
-- ====================================
SELECT 
  '✅ TRIGGER CREADO EXITOSAMENTE' as status,
  'Trigger: on_auth_user_created' as trigger_name,
  'Function: public.handle_new_user()' as function_name;

-- Ver triggers existentes en auth.users
SELECT 
  trigger_name,
  event_manipulation,
  event_object_table,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth'
  AND event_object_table = 'users'
ORDER BY trigger_name;

-- ====================================
-- NOTA IMPORTANTE
-- ====================================
SELECT 
  '⚠️  IMPORTANTE: FLUJO DE REGISTRO RECOMENDADO' as nota,
  '
  CON ESTE TRIGGER:
  ─────────────────
  1. Cliente registra:
     → supabase.auth.signUp(email, password, {name, phone})
     → Trigger automáticamente crea registro en public.users
     → Cliente debe llamar register_client() para completar perfil
  
  2. Restaurante registra:
     → supabase.auth.signUp(email, password)
     → Trigger crea registro en public.users como "cliente"
     → Cliente llama register_restaurant() para cambiar rol y crear perfil
  
  3. Repartidor registra:
     → supabase.auth.signUp(email, password)
     → Trigger crea registro en public.users como "cliente"
     → Cliente llama register_delivery_agent() para cambiar rol y crear perfil
  
  SIN ESTE TRIGGER (RECOMENDADO):
  ────────────────────────────────
  1. Cliente registra:
     → supabase.auth.signUp(email, password)
     → supabase.rpc("register_client", {...})
  
  2. Restaurante registra:
     → supabase.auth.signUp(email, password)
     → supabase.rpc("register_restaurant", {...})
  
  3. Repartidor registra:
     → supabase.auth.signUp(email, password)
     → supabase.rpc("register_delivery_agent", {...})
  
  RECOMENDACIÓN:
  ──────────────
  • Si tu flujo de registro es simple: USA EL TRIGGER
  • Si necesitas capturar datos específicos por rol: NO USES EL TRIGGER
  ' as recomendacion;
