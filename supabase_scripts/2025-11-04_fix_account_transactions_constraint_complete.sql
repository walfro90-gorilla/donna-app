-- =====================================================================
-- FIX CONSTRAINT: account_transactions_type_check
-- Agrega TODOS los tipos válidos según DATABASE_SCHEMA.sql
-- Incluye: RESTAURANT_PAYABLE, DELIVERY_PAYABLE
-- =====================================================================

DO $$
BEGIN
  -- Eliminar constraint existente si existe
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON c.conrelid = t.oid
    JOIN pg_namespace n ON t.relnamespace = n.oid
    WHERE n.nspname = 'public'
      AND t.relname = 'account_transactions'
      AND c.conname = 'account_transactions_type_check'
  ) THEN
    ALTER TABLE public.account_transactions DROP CONSTRAINT account_transactions_type_check;
    RAISE NOTICE 'Constraint eliminado';
  END IF;

  -- Crear constraint con TODOS los tipos válidos
  ALTER TABLE public.account_transactions
    ADD CONSTRAINT account_transactions_type_check
    CHECK (type IN (
      'ORDER_REVENUE',
      'PLATFORM_COMMISSION',
      'DELIVERY_EARNING',
      'CASH_COLLECTED',
      'SETTLEMENT_PAYMENT',
      'SETTLEMENT_RECEPTION',
      'RESTAURANT_PAYABLE',
      'DELIVERY_PAYABLE',
      'PLATFORM_DELIVERY_MARGIN',
      'CLIENT_DEBT'
    ));

  RAISE NOTICE 'Constraint recreado con todos los tipos válidos';
END $$;
