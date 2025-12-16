-- ============================================================================
-- ⚠️ SURGICAL CLEANUP - DROP INTRUDER TABLES ⚠️
-- ============================================================================
-- PRECAUCIÓN: Este script ELIMINA DATOS permanentemente.
-- Ejecutar solo si estás seguro de que 'transactions', 'wallets', 'services', 'profiles'
-- son las tablas intrusas y no contienen datos vitales de producción.
-- ============================================================================

BEGIN;

-- 1. Eliminar tabla 'transactions' (Intrusa - La real es 'account_transactions')
DROP TABLE IF EXISTS public.transactions CASCADE;

-- 2. Eliminar tabla 'wallets' (Intrusa - La real es 'accounts')
DROP TABLE IF EXISTS public.wallets CASCADE;

-- 3. Eliminar tabla 'services' (Intrusa - La real es 'products')
DROP TABLE IF EXISTS public.services CASCADE;

-- 4. Eliminar tabla 'profiles' (Intrusa - La real es 'users' + 'client_profiles')
DROP TABLE IF EXISTS public.profiles CASCADE;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN
-- Asegúrate de que las tablas críticas sigan existiendo:
-- SELECT * FROM public.users LIMIT 1;
-- SELECT * FROM public.accounts LIMIT 1;
-- ============================================================================
