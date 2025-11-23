# ✅ Checklist de Deployment - Sistema de Transacciones

## 📋 Pre-Requisitos

- [ ] Acceso a Supabase Dashboard (SQL Editor)
- [ ] Supabase CLI instalado (para desplegar Edge Functions)
- [ ] Backup de base de datos (opcional pero recomendado)

---

## 🚀 Pasos de Deployment

### 1️⃣ Validar Estado Actual

**Propósito:** Identificar si el sistema necesita corrección

**Pasos:**
```bash
# Ir a Supabase Dashboard → SQL Editor
# Ejecutar: sql_migrations/2025-01-18_VALIDATE_transaction_system.sql
```

**Resultado esperado:**
```
❌ ÓRDENES DESBALANCEADAS: X
❌ BALANCE GLOBAL: $-XXX.XX
⚠️  SISTEMA REQUIERE CORRECCIONES
```

**Acción:**
- Si todo está ✅: Pasar al paso 3
- Si hay ❌: Continuar al paso 2

---

### 2️⃣ Ejecutar Script de Corrección

**Propósito:** Limpiar transacciones incorrectas y recrear las correctas

**Pasos:**
```bash
# Ir a Supabase Dashboard → SQL Editor
# Ejecutar: sql_migrations/2025-01-18_FIX_card_payment_transactions_balance_zero.sql
```

**Qué hace el script:**
1. Elimina transacciones con tipos inválidos (ORDER_PAYMENT, PAYMENT_DEBT, etc.)
2. Elimina transacciones ORDER_REVENUE redundantes
3. Elimina transacciones PLATFORM_COMMISSION negativas duplicadas
4. Recrea transacciones para órdenes entregadas sin transacciones completas
5. Valida que el balance de 0 por orden y globalmente

**Resultado esperado:**
```
========================================
VALIDACIÓN DE BALANCE 0
========================================
📊 Total órdenes entregadas: X
⚖️  Órdenes con desbalance: 0
✅ Todas las órdenes tienen balance 0
========================================

========================================
BALANCE POR TIPO DE CUENTA
========================================
RESTAURANT (X): $XXX.XX MXN
DELIVERY_AGENT (X): $XXX.XX MXN
PLATFORM_REVENUE (X): $XXX.XX MXN
PLATFORM_PAYABLES (X): $-XXX.XX MXN
----------------------------------------
BALANCE GLOBAL: $0.00 MXN
✅ Sistema en balance 0
========================================
```

**⚠️ IMPORTANTE:**
- Este script es **idempotente** (se puede ejecutar múltiples veces sin problemas)
- Usa transacciones (BEGIN/COMMIT) para asegurar atomicidad
- Si algo falla, hacer ROLLBACK y reportar error

---

### 3️⃣ Desplegar Edge Functions Actualizadas

**Propósito:** Asegurar que el webhook NO cree transacciones incorrectas

**Pasos:**
```bash
# Desde la raíz del proyecto:
cd /hologram/data/workspace/project

# Desplegar webhook actualizado:
supabase functions deploy mercadopago-webhook

# Verificar deployment:
supabase functions list
```

**Resultado esperado:**
```
✅ mercadopago-webhook deployed successfully
```

**Cambios en el webhook:**
- ✅ Ya NO crea transacciones ORDER_PAYMENT/PAYMENT_DEBT
- ✅ Solo actualiza status de payments y marca deudas como pagadas
- ✅ Las transacciones se crean cuando la orden es entregada (trigger SQL)

---

### 4️⃣ Re-Validar Sistema

**Propósito:** Confirmar que todo está correcto

**Pasos:**
```bash
# Ir a Supabase Dashboard → SQL Editor
# Ejecutar NUEVAMENTE: sql_migrations/2025-01-18_VALIDATE_transaction_system.sql
```

**Resultado esperado:**
```
🎉 ✅ SISTEMA COMPLETAMENTE VÁLIDO
```

**Verificaciones:**
- [ ] ✅ Trigger "trg_on_order_delivered_process_v3" ACTIVO
- [ ] ✅ Constraint "uq_account_txn_order_account_type" EXISTE
- [ ] ✅ Todos los tipos de transacciones son VÁLIDOS
- [ ] ✅ Todas las órdenes tienen BALANCE = 0
- [ ] ✅ Balance global = $0.00 (CORRECTO)
- [ ] ✅ Las últimas X órdenes entregadas tienen estructura COMPLETA

---

### 5️⃣ Prueba End-to-End

**Propósito:** Validar que nuevas órdenes funcionan correctamente

#### **Caso 1: Pago con Tarjeta**

**Pasos:**
1. Crear nueva orden en la app
2. Pagar con tarjeta (MercadoPago)
3. Verificar que el pago se aprobó
4. Asignar repartidor y marcar como entregada
5. Validar transacciones en Supabase

**Validación en SQL:**
```sql
-- Reemplazar 'ORDER_ID' con el ID de la orden de prueba
SELECT 
  type,
  account_id,
  amount,
  description
FROM account_transactions
WHERE order_id = 'ORDER_ID'
ORDER BY created_at;

-- Debe retornar 5 transacciones:
-- 1. RESTAURANT_PAYABLE (+)
-- 2. PLATFORM_COMMISSION (+)
-- 3. DELIVERY_EARNING (+)
-- 4. PLATFORM_DELIVERY_MARGIN (+)
-- 5. CASH_COLLECTED (-) en platform_payables

-- Verificar que suman 0:
SELECT SUM(amount) as balance
FROM account_transactions
WHERE order_id = 'ORDER_ID';
-- Debe dar: 0.00
```

**Resultado esperado:**
- [ ] 5 transacciones creadas
- [ ] Balance de la orden = $0.00
- [ ] Settlements pendientes creados:
  - [ ] platform_payables → restaurant
  - [ ] platform_payables → delivery_agent

---

#### **Caso 2: Pago en Efectivo**

**Pasos:**
1. Crear nueva orden en la app
2. Seleccionar pago en efectivo
3. Asignar repartidor y marcar como entregada
4. Validar transacciones en Supabase

**Validación en SQL:**
```sql
-- Reemplazar 'ORDER_ID' con el ID de la orden de prueba
SELECT 
  type,
  account_id,
  amount,
  description
FROM account_transactions
WHERE order_id = 'ORDER_ID'
ORDER BY created_at;

-- Debe retornar 5 transacciones:
-- 1. RESTAURANT_PAYABLE (+)
-- 2. PLATFORM_COMMISSION (+)
-- 3. DELIVERY_EARNING (+)
-- 4. PLATFORM_DELIVERY_MARGIN (+)
-- 5. CASH_COLLECTED (-) en delivery_agent

-- Verificar que suman 0:
SELECT SUM(amount) as balance
FROM account_transactions
WHERE order_id = 'ORDER_ID';
-- Debe dar: 0.00
```

**Resultado esperado:**
- [ ] 5 transacciones creadas
- [ ] Balance de la orden = $0.00
- [ ] Settlement pendiente creado:
  - [ ] delivery_agent → platform_payables

---

### 6️⃣ Monitoreo Post-Deployment

**Propósito:** Asegurar que el sistema funciona correctamente en producción

**Queries de Monitoreo:**

#### **1. Balance Global (Ejecutar diariamente)**
```sql
SELECT 
  COALESCE(SUM(amount), 0) as global_balance,
  COUNT(*) as total_transactions
FROM account_transactions;

-- global_balance DEBE ser 0.00 SIEMPRE
```

#### **2. Órdenes con Desbalance (Ejecutar cuando balance global != 0)**
```sql
SELECT 
  LEFT(order_id::text, 8) as order_short,
  COUNT(*) as tx_count,
  SUM(amount) as balance
FROM account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01
ORDER BY ABS(SUM(amount)) DESC;
```

#### **3. Balance por Tipo de Cuenta (Ejecutar semanalmente)**
```sql
SELECT 
  a.account_type,
  COUNT(DISTINCT a.id) as account_count,
  COALESCE(SUM(at.amount), 0) as total_balance
FROM accounts a
LEFT JOIN account_transactions at ON at.account_id = a.id
WHERE a.account_type IN ('restaurant', 'delivery_agent', 'platform_revenue', 'platform_payables')
GROUP BY a.account_type
ORDER BY a.account_type;

-- Nota: Los balances individuales pueden ser != 0, pero la SUMA debe ser 0
```

#### **4. Tipos de Transacciones (Ejecutar cuando haya problemas)**
```sql
SELECT 
  type,
  COUNT(*) as count,
  SUM(amount) as total_amount
FROM account_transactions
GROUP BY type
ORDER BY type;

-- Verificar que solo hay tipos válidos del DATABASE_SCHEMA.sql
```

---

## 🚨 Troubleshooting

### Problema: Balance global != 0 después del fix

**Diagnóstico:**
```sql
-- 1. Identificar órdenes con desbalance
SELECT 
  order_id,
  SUM(amount) as balance,
  COUNT(*) as tx_count,
  STRING_AGG(type, ', ') as types
FROM account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01;

-- 2. Ver detalle de transacciones de esa orden
SELECT * 
FROM account_transactions 
WHERE order_id = 'PROBLEM_ORDER_ID'
ORDER BY created_at;
```

**Solución:**
1. Si hay tipos inválidos: Eliminar esas transacciones manualmente
2. Si falta alguna transacción: Re-ejecutar el trigger manualmente:
   ```sql
   -- Cambiar status temporalmente para re-disparar el trigger
   UPDATE orders SET status = 'preparing' WHERE id = 'PROBLEM_ORDER_ID';
   UPDATE orders SET status = 'delivered' WHERE id = 'PROBLEM_ORDER_ID';
   ```

---

### Problema: Nueva orden NO crea transacciones al entregar

**Diagnóstico:**
```sql
-- Verificar que el trigger existe
SELECT * FROM pg_trigger WHERE tgname = 'trg_on_order_delivered_process_v3';

-- Verificar logs de la función
-- (En Supabase Dashboard → Database → Functions → process_order_delivery_v3)
```

**Solución:**
1. Re-ejecutar script de trigger:
   ```bash
   # sql_migrations/2025-11-09-01_UPDATE_process_order_delivery_v3_zero_sum.sql
   ```

---

### Problema: Transacciones duplicadas después de varios updates

**Diagnóstico:**
```sql
-- Buscar duplicados
SELECT 
  order_id,
  account_id,
  type,
  COUNT(*) as count
FROM account_transactions
GROUP BY order_id, account_id, type
HAVING COUNT(*) > 1;
```

**Solución:**
```sql
-- Eliminar duplicados (mantener el más reciente)
WITH duplicates AS (
  SELECT 
    id,
    ROW_NUMBER() OVER (
      PARTITION BY order_id, account_id, type 
      ORDER BY created_at DESC
    ) as rn
  FROM account_transactions
  WHERE order_id IS NOT NULL
)
DELETE FROM account_transactions
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);
```

---

## 📊 Métricas de Éxito

Después del deployment exitoso, deberías ver:

- **Balance global:** $0.00 ✅
- **Órdenes desbalanceadas:** 0 ✅
- **Tipos inválidos:** 0 ✅
- **Transacciones por orden entregada:** 5 ✅
- **Settlements creados:** ✅
- **Nuevas órdenes funcionando:** ✅

---

## 📝 Notas Finales

1. **Este deployment NO afecta órdenes en proceso** - Solo ordenes ya entregadas
2. **Los balances de cuentas se actualizarán correctamente** - Pueden verse negativos/positivos pero el global es 0
3. **Los settlements se crean automáticamente** - Según el payment_method
4. **El sistema es resistente a errores** - El constraint previene duplicados
5. **Se puede re-ejecutar el fix** - El script es idempotente

---

**Contacto de soporte:** Si algo falla, reportar en el canal de desarrollo con:
- Screenshot del error
- Query SQL ejecutado
- Logs de Edge Functions (si aplica)
- ID de orden problemática

---

**Última actualización:** 2025-01-18  
**Versión:** 1.0  
**Estado:** ✅ Listo para producción
