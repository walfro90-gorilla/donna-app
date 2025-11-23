-- ================================================================
-- ELIMINAR CONSTRAINT DUPLICADO "type_check" 
-- ================================================================
-- Este script elimina el constraint viejo "type_check" que está
-- causando conflicto con el constraint actualizado 
-- "account_transactions_type_check"
--
-- PROBLEMA: Existen 2 constraints validando el campo "type":
--   1. account_transactions_type_check (ACTUALIZADO ✅)
--   2. type_check (VIEJO ❌) <- Este es el que eliminaremos
--
-- SOLUCIÓN: Eliminar el constraint viejo "type_check"
-- ================================================================

-- PASO 1: Eliminar el constraint viejo "type_check"
ALTER TABLE public.account_transactions 
DROP CONSTRAINT IF EXISTS type_check;

-- PASO 2: Verificar que solo quede el constraint correcto
-- Ejecuta este query para confirmar:
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conname LIKE '%type%'
  AND connamespace = 'public'::regnamespace
  AND conrelid = 'account_transactions'::regclass;

-- ================================================================
-- RESULTADO ESPERADO:
-- Solo debe aparecer "account_transactions_type_check" con los 
-- valores actualizados incluyendo:
--   - PLATFORM_NOT_DELIVERED_REFUND
--   - CLIENT_DEBT
-- ================================================================
