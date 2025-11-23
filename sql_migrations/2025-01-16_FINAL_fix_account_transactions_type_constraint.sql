-- ============================================================================
-- FIX: Account Transactions Type Constraint
-- ============================================================================
-- Problema: El constraint de 'type' en account_transactions rechaza los nuevos
--           tipos 'PLATFORM_NOT_DELIVERED_REFUND' y 'CLIENT_DEBT'
--
-- Solución: Eliminar el constraint actual y recrearlo con todos los tipos
-- ============================================================================

BEGIN;

-- ============================================================
-- PASO 1: Eliminar el constraint actual
-- ============================================================
-- PostgreSQL crea un nombre automático para constraints inline
-- Buscamos todos los constraints de tipo CHECK en la columna 'type'
DO $$
DECLARE
  constraint_name text;
BEGIN
  -- Buscar el nombre del constraint actual en la columna 'type'
  SELECT con.conname INTO constraint_name
  FROM pg_constraint con
  INNER JOIN pg_class rel ON rel.oid = con.conrelid
  INNER JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
  WHERE nsp.nspname = 'public'
    AND rel.relname = 'account_transactions'
    AND con.contype = 'c'  -- CHECK constraint
    AND pg_get_constraintdef(con.oid) LIKE '%type%';

  -- Si existe, eliminarlo
  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.account_transactions DROP CONSTRAINT %I', constraint_name);
    RAISE NOTICE 'Constraint % eliminado exitosamente', constraint_name;
  ELSE
    RAISE NOTICE 'No se encontró constraint en la columna type';
  END IF;
END $$;

-- ============================================================
-- PASO 2: Crear el nuevo constraint con TODOS los tipos
-- ============================================================
ALTER TABLE public.account_transactions
ADD CONSTRAINT account_transactions_type_check CHECK (
  type = ANY (ARRAY[
    'ORDER_REVENUE'::text,
    'PLATFORM_COMMISSION'::text,
    'DELIVERY_EARNING'::text,
    'CASH_COLLECTED'::text,
    'SETTLEMENT_PAYMENT'::text,
    'SETTLEMENT_RECEPTION'::text,
    'RESTAURANT_PAYABLE'::text,
    'DELIVERY_PAYABLE'::text,
    'PLATFORM_DELIVERY_MARGIN'::text,
    'PLATFORM_NOT_DELIVERED_REFUND'::text,  -- ✅ NUEVO
    'CLIENT_DEBT'::text                      -- ✅ NUEVO
  ])
);

COMMIT;

-- ============================================================
-- VERIFICACIÓN
-- ============================================================
-- Verificar que el nuevo constraint existe
SELECT 
  conname AS constraint_name,
  pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.account_transactions'::regclass
  AND contype = 'c'
  AND pg_get_constraintdef(oid) LIKE '%type%';
