-- ===============================================
-- 🔧 SCRIPT DE CORRECCIÓN: TRIGGER CON MAPEO DE ACCOUNT_TYPE
-- ===============================================
-- Elimina y recrea el trigger con mapeo correcto de roles a tipos de cuenta

-- PASO 1: Eliminar trigger y función existentes
DROP TRIGGER IF EXISTS trigger_create_account_on_approval ON public.users;
DROP FUNCTION IF EXISTS create_account_on_user_approval();

-- PASO 2: Crear función mejorada con mapeo de account_type
CREATE OR REPLACE FUNCTION create_account_on_user_approval()
RETURNS TRIGGER AS $$
DECLARE
    mapped_account_type TEXT;
BEGIN
    -- Solo procesar cuando se actualiza status a 'approved'
    IF TG_OP = 'UPDATE' AND 
       OLD.status != 'approved' AND 
       NEW.status = 'approved' THEN
        
        -- Mapear rol del usuario a tipo de cuenta
        CASE NEW.role
            WHEN 'restaurante' THEN
                mapped_account_type := 'restaurant';
            WHEN 'restaurant' THEN
                mapped_account_type := 'restaurant';
            WHEN 'delivery_agent' THEN
                mapped_account_type := 'delivery_agent';
            WHEN 'repartidor' THEN
                mapped_account_type := 'delivery_agent';
            ELSE
                -- No crear cuenta para admin o cliente
                RETURN NEW;
        END CASE;
        
        -- Verificar si ya existe una cuenta para este usuario
        IF NOT EXISTS (SELECT 1 FROM public.accounts WHERE user_id = NEW.id) THEN
            -- Crear cuenta con balance inicial 0
            INSERT INTO public.accounts (
                id,
                user_id,
                account_type,
                balance,
                created_at,
                updated_at
            ) VALUES (
                gen_random_uuid(),
                NEW.id,
                mapped_account_type,
                0.0,
                NOW(),
                NOW()
            );
            
            RAISE NOTICE 'Cuenta creada para usuario % con tipo %', NEW.id, mapped_account_type;
        ELSE
            RAISE NOTICE 'Cuenta ya existe para usuario %', NEW.id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- PASO 3: Crear trigger
CREATE TRIGGER trigger_create_account_on_approval
    AFTER UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION create_account_on_user_approval();

-- PASO 4: Verificar el trigger se creó correctamente
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers 
WHERE trigger_name = 'trigger_create_account_on_approval';

-- ===============================================
-- 📝 VERIFICACIÓN: Mostrar estructura de tablas
-- ===============================================

-- Verificar columnas de users
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'users' AND table_schema = 'public'
ORDER BY ordinal_position;

-- Verificar columnas de accounts
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'accounts' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ===============================================
-- 🧪 TESTING: Crear cuentas faltantes para usuarios ya aprobados
-- ===============================================

-- Crear cuentas para usuarios aprobados que no tienen cuenta
INSERT INTO public.accounts (id, user_id, account_type, balance, created_at, updated_at)
SELECT 
    gen_random_uuid() as id,
    u.id as user_id,
    CASE 
        WHEN u.role IN ('restaurante', 'restaurant') THEN 'restaurant'
        WHEN u.role IN ('delivery_agent', 'repartidor') THEN 'delivery_agent'
        ELSE 'restaurant' -- Default fallback
    END as account_type,
    0.0 as balance,
    NOW() as created_at,
    NOW() as updated_at
FROM public.users u
WHERE u.status = 'approved'
  AND u.role IN ('restaurante', 'restaurant', 'delivery_agent', 'repartidor')
  AND NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.user_id = u.id);

-- Mostrar resultado
SELECT 
    u.id,
    u.email,
    u.name,
    u.role,
    u.status,
    a.account_type,
    a.balance,
    CASE WHEN a.id IS NOT NULL THEN '✅ Tiene cuenta' ELSE '❌ Sin cuenta' END as account_status
FROM public.users u
LEFT JOIN public.accounts a ON u.id = a.user_id
WHERE u.role IN ('restaurante', 'restaurant', 'delivery_agent', 'repartidor')
ORDER BY u.created_at DESC;