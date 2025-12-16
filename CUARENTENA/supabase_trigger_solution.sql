-- =============================================
-- SOLUCIÓN DEFINITIVA: DATABASE TRIGGER
-- =============================================
-- Este trigger crea automáticamente el perfil del usuario
-- cuando se registra en auth.users

-- 1. Función que crea el perfil automáticamente
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  -- Insertar el nuevo usuario en la tabla public.users
  INSERT INTO public.users (
    id,
    email,
    name,
    role,
    phone,
    address,
    email_confirm,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'name', 'Usuario'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    COALESCE(NEW.raw_user_meta_data->>'address', ''),
    CASE 
      WHEN NEW.email_confirmed_at IS NOT NULL THEN true 
      ELSE false 
    END,
    NOW(),
    NOW()
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger que ejecuta la función cuando se crea un nuevo usuario en auth
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Función para actualizar email_confirm cuando se confirma el email
CREATE OR REPLACE FUNCTION public.handle_user_email_confirmation()
RETURNS trigger AS $$
BEGIN
  -- Solo actualizar si email_confirmed_at cambió de null a no-null
  IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
    UPDATE public.users 
    SET 
      email_confirm = true,
      updated_at = NOW()
    WHERE id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Trigger para actualizar email_confirm automáticamente
DROP TRIGGER IF EXISTS on_auth_user_email_confirmed ON auth.users;
CREATE TRIGGER on_auth_user_email_confirmed
  AFTER UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_user_email_confirmation();

-- =============================================
-- LIMPIEZA DE DATOS CORRUPTOS (OPCIONAL)
-- =============================================
-- Si hay usuarios en auth.users que no tienen perfil en public.users:

INSERT INTO public.users (id, email, name, role, phone, address, email_confirm, created_at, updated_at)
SELECT 
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'name', 'Usuario Migrado'),
  COALESCE(au.raw_user_meta_data->>'role', 'cliente'),
  COALESCE(au.raw_user_meta_data->>'phone', ''),
  COALESCE(au.raw_user_meta_data->>'address', ''),
  CASE WHEN au.email_confirmed_at IS NOT NULL THEN true ELSE false END,
  au.created_at,
  au.updated_at
FROM auth.users au
LEFT JOIN public.users pu ON au.id = pu.id
WHERE pu.id IS NULL;