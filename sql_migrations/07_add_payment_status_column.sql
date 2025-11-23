-- ===================================================================
-- 🔧 MIGRACIÓN: Agregar columna payment_status a la tabla orders
-- ===================================================================
-- Fecha: 2025
-- Propósito: Separar método de pago del estado del pago para MercadoPago
-- ===================================================================

-- 1️⃣ Agregar columna payment_status
ALTER TABLE public.orders 
ADD COLUMN IF NOT EXISTS payment_status TEXT 
CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')) 
DEFAULT 'pending';

-- 2️⃣ Establecer valor por defecto basado en payment_method existente
-- Las órdenes con efectivo se marcan como 'pending' (pago al entregar)
-- Las órdenes con tarjeta existentes se marcan como 'paid' (asumiendo pagos legacy completados)
UPDATE public.orders 
SET payment_status = CASE 
  WHEN payment_method = 'cash' THEN 'pending'
  WHEN payment_method = 'card' THEN 'paid'
  ELSE 'pending'
END
WHERE payment_status = 'pending';

-- 3️⃣ Crear índice para mejorar queries de búsqueda por payment_status
CREATE INDEX IF NOT EXISTS idx_orders_payment_status 
ON public.orders(payment_status);

-- 4️⃣ Crear índice compuesto para búsquedas frecuentes (user + status + payment_status)
CREATE INDEX IF NOT EXISTS idx_orders_user_payment_lookup 
ON public.orders(user_id, payment_status, created_at DESC);

-- ===================================================================
-- ✅ COMPLETADO
-- ===================================================================
