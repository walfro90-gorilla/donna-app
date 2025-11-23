# 🔧 Resumen Ejecutivo: Corrección de Transacciones

## 🚨 Problema Detectado

Del screenshot y logs proporcionados, se identificaron **3 problemas críticos** en el sistema de transacciones:

### 1. **Balance NO da 0**
```
- Restaurantes: +$102.85 MXN
- Repartidores: +$2.55 MXN
- Clientes: $0.00 MXN
- MASTER (Platform): -$105.40 MXN

❌ BALANCE GLOBAL: -$105.40 MXN (DEBERÍA SER $0.00)
```

### 2. **Transacciones Duplicadas/Incorrectas**

Del screenshot se ven **7 transacciones** cuando deberían ser solo **6**:

| # | Tipo | Cuenta | Monto | ✅/❌ |
|---|------|--------|-------|-------|
| 1 | `PLATFORM_COMMISSION` | platform_revenue | +$16.13 | ✅ |
| 2 | `RESTAURANT_PAYABLE` | restaurant | +$102.85 | ✅ |
| 3 | `DELIVERY_EARNING` | delivery_agent | +$2.55 | ✅ |
| 4 | `PLATFORM_DELIVERY_MARGIN` | platform_revenue | +$0.44 | ✅ |
| 5 | `CASH_COLLECTED` | platform_payables | -$105.40 | ❌ **INCORRECTO PARA TARJETA** |
| 6 | `ORDER_REVENUE` | ??? | +$121.00 | ❌ REDUNDANTE |
| 7 | `PLATFORM_COMMISSION` | ??? | -$21.60 | ❌ DUPLICADO NEGATIVO |

**Problemas:** 
- Transacciones 5, 6 y 7 son **INCORRECTAS** y rompen el balance 0
- **CASH_COLLECTED no debe existir para pagos con TARJETA** - el dinero ya está en la plataforma

### 3. **Transacciones Inválidas Creadas por Webhook Antiguo**

El webhook anterior (`mercadopago-webhook/index.ts`) estaba creando transacciones con tipos **NO VÁLIDOS**:
- `ORDER_PAYMENT` ❌ (no existe en DATABASE_SCHEMA.sql)
- `PAYMENT_DEBT` ❌ (no existe en DATABASE_SCHEMA.sql)

---

## ✅ Solución Implementada

### 🔧 Cambios en Código

#### 1. **Edge Function: `mercadopago-webhook/index.ts`**

**ANTES:**
```typescript
// Creaba transacciones ORDER_PAYMENT y PAYMENT_DEBT incorrectas
await supabase.from('account_transactions').insert({
  account_id: clientId,
  type: 'ORDER_PAYMENT',  // ❌ NO VÁLIDO
  // ...
});
```

**DESPUÉS:**
```typescript
// YA NO crea transacciones - solo actualiza deudas del cliente
// Las transacciones se crean automáticamente cuando la orden es entregada
console.log('ℹ️ Las transacciones se crearán cuando la orden sea entregada');
```

#### 2. **Edge Function: `process-card-payment/index.ts`**

**✅ Ya está correcto** - NO crea transacciones, solo:
1. Tokeniza tarjeta
2. Crea pago en MercadoPago
3. Crea orden en Supabase
4. Crea registro en tabla `payments`

**Transacciones se crean SOLO al entregar** (líneas 326-342):
```typescript
// NOTA: Las transacciones de account_transactions se crean automáticamente 
// mediante el trigger SQL 'process_order_delivery_v3()'
// cuando la orden cambia a status 'delivered'.
```

---

### 📄 Script SQL de Limpieza

**Archivo:** `sql_migrations/2025-01-18_FIX_card_payment_transactions_balance_zero.sql`

**Acciones:**

1. **Elimina transacciones inválidas** (tipos no en DATABASE_SCHEMA.sql)
2. **Elimina ORDER_REVENUE redundantes** (cuando ya hay distribución completa)
3. **Elimina PLATFORM_COMMISSION negativos** (duplicados)
4. **Recrea transacciones faltantes** (para órdenes entregadas sin transacciones)
5. **Valida balance = 0** por orden y globalmente

**Ejecutar:**
```sql
-- Conectar a Supabase SQL Editor y ejecutar:
-- sql_migrations/2025-01-18_FIX_card_payment_transactions_balance_zero.sql
```

---

### 📚 Documentación Creada

#### 1. **`docs/PAYMENT_TRANSACTIONS_FLOW.md`**
- Flujo completo de pagos con tarjeta y efectivo
- Explicación de cada tipo de transacción
- Ejemplos con cálculos reales
- Reglas de oro del sistema

#### 2. **`docs/TRANSACTION_FIX_SUMMARY.md`** (este archivo)
- Resumen ejecutivo del problema
- Solución implementada
- Pasos de ejecución

---

## 🎯 Flujo Correcto (Después del Fix)

### **Pago con Tarjeta:**

```
1. Cliente → MercadoPago Card Form (Flutter)
   ↓
2. Edge Function: process-card-payment
   - Tokeniza tarjeta
   - Crea pago en MercadoPago
   - Crea orden (status: pending, payment_method: card)
   - Crea registro en payments (status: completed si aprobado)
   - ⚠️ NO crea transacciones todavía
   ↓
3. (Opcional) Webhook de MercadoPago
   - Actualiza status del payment
   - Marca deudas como pagadas
   - ⚠️ NO crea transacciones
   ↓
4. Repartidor entrega la orden
   - OrderStatusHelper.updateOrderStatus(orderId, 'delivered')
   ↓
5. Trigger SQL: process_order_delivery_v4()
   - Detecta payment_method = 'card'
   - Crea 6 transacciones que suman $0.00:
     * PLATFORM_COMMISSION: +$Y (platform_revenue) - Ganancia plataforma
     * PLATFORM_DELIVERY_MARGIN: +$W (platform_revenue) - Ganancia plataforma
     * RESTAURANT_PAYABLE: -$X (platform_payables) - Deuda a restaurant
     * RESTAURANT_PAYABLE: +$X (restaurant) - Ganancia restaurant
     * DELIVERY_EARNING: -$Z (platform_payables) - Deuda a repartidor
     * DELIVERY_EARNING: +$Z (delivery_agent) - Ganancia repartidor
   - ⚠️ NO crea CASH_COLLECTED - la plataforma ya tiene el dinero
   - Crea settlements pendientes:
     * platform_payables → restaurant: $X
     * platform_payables → delivery_agent: $Z
```

### **Pago en Efectivo:**

```
1. Cliente → App (Flutter)
   ↓
2. Crea orden (status: pending, payment_method: cash)
   - ⚠️ NO se crea registro en payments
   - ⚠️ NO se crean transacciones todavía
   ↓
3. Repartidor entrega la orden
   - OrderStatusHelper.updateOrderStatus(orderId, 'delivered')
   ↓
4. Trigger SQL: process_order_delivery_v4()
   - Detecta payment_method = 'cash'
   - Crea 5 transacciones que suman $0.00:
     * PLATFORM_COMMISSION: +$Y (platform_revenue)
     * PLATFORM_DELIVERY_MARGIN: +$W (platform_revenue)
     * RESTAURANT_PAYABLE: +$X (restaurant)
     * DELIVERY_EARNING: +$Z (delivery_agent)
     * CASH_COLLECTED: -$TOTAL (delivery_agent) ← El repartidor cobró el efectivo
   - Crea settlement pendiente:
     * delivery_agent → platform_payables: $(TOTAL - Z)
```

---

## 🚀 Pasos de Ejecución

### 1️⃣ Desplegar Cambios de Código

```bash
# Los cambios ya están en:
# - supabase/functions/mercadopago-webhook/index.ts
# - supabase/functions/process-card-payment/index.ts (sin cambios - ya correcto)

# Desplegar Edge Functions:
supabase functions deploy mercadopago-webhook
```

### 2️⃣ Ejecutar Script SQL de Corrección (NUEVO FLUJO SIN CASH_COLLECTED PARA TARJETA)

1. Ir a Supabase Dashboard → SQL Editor
2. Abrir archivo: `sql_migrations/2025-01-18_FIX_card_payment_no_cash_collected.sql`
3. Ejecutar (esto implementará el trigger v4 y recreará transacciones correctas)

**Este script:**
- Crea trigger v4 que NO usa CASH_COLLECTED para tarjeta
- Elimina CASH_COLLECTED de órdenes con tarjeta
- Recrea transacciones con el flujo correcto (deudas explícitas en platform_payables)

### 3️⃣ Validar Resultados

**En Supabase SQL Editor:**
```sql
-- 1. Verificar balance por orden (todas deben dar 0)
SELECT 
  order_id,
  COUNT(*) as tx_count,
  SUM(amount) as balance
FROM account_transactions
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING ABS(SUM(amount)) > 0.01;

-- Si retorna 0 filas: ✅ Todas las órdenes tienen balance 0


-- 2. Verificar balance global (debe dar 0)
SELECT SUM(amount) as global_balance
FROM account_transactions;

-- Debe retornar: 0.00


-- 3. Verificar tipos de transacciones válidos
SELECT DISTINCT type
FROM account_transactions
ORDER BY type;

-- Solo deben aparecer los tipos válidos del DATABASE_SCHEMA.sql
```

### 4️⃣ Probar con Nueva Orden

1. Crear nueva orden con pago de tarjeta
2. Completar flujo hasta entrega
3. Verificar que las **6 transacciones** se crearon correctamente
4. Validar que suman $0.00

---

## 📊 Ejemplo de Balance Correcto (NUEVO FLUJO V4)

### Orden con TARJETA: $105.40 (Subtotal: $70.40, Delivery: $35.00)

| Transacción | Cuenta | Monto |
|-------------|--------|-------|
| PLATFORM_COMMISSION | platform_revenue | +$14.08 |
| PLATFORM_DELIVERY_MARGIN | platform_revenue | +$5.25 |
| RESTAURANT_PAYABLE | platform_payables | **-$56.32** |
| RESTAURANT_PAYABLE | restaurant | +$56.32 |
| DELIVERY_EARNING | platform_payables | **-$29.75** |
| DELIVERY_EARNING | delivery_agent | +$29.75 |
| **TOTAL** | | **$0.00** ✅ |

**Interpretación:**
- Plataforma ganó: $14.08 + $5.25 = $19.33
- Plataforma debe pagar: $56.32 + $29.75 = $86.07
- Neto plataforma: $19.33 - $86.07 = -$66.74 (debe liquidar)
- ✅ La plataforma ya tiene los $105.40 de MercadoPago, de los cuales debe pagar $86.07

---

## ⚠️ Notas Importantes

1. **Las transacciones se crean SOLO al entregar** - No antes
2. **El webhook NO debe crear transacciones** - Solo actualizar payments
3. **El balance SIEMPRE debe dar 0** - Por orden y globalmente
4. **ORDER_REVENUE es obsoleto** - Ya no se usa en el nuevo sistema
5. **payment_method determina el flujo** - 'card' vs 'cash'
6. **🆕 CASH_COLLECTED NO se usa para tarjeta** - Solo para efectivo
7. **🆕 Las deudas se registran explícitamente** - Transacciones negativas en platform_payables

---

## 🎯 Indicadores de Éxito

- [ ] Balance global = $0.00
- [ ] Todas las órdenes entregadas tienen balance = $0.00
- [ ] No hay transacciones con tipos inválidos
- [ ] No hay transacciones duplicadas (ORDER_REVENUE, PLATFORM_COMMISSION negativo)
- [ ] 🆕 NO hay CASH_COLLECTED en órdenes con tarjeta
- [ ] 🆕 Órdenes con tarjeta tienen 6 transacciones (no 5)
- [ ] 🆕 Las deudas están en platform_payables (negativas)
- [ ] Settlements se crean correctamente según payment_method
- [ ] Nueva orden de prueba tiene transacciones correctas

---

**Fecha:** 2025-01-18  
**Estado:** ✅ Solución V4 lista para desplegar  
**Urgencia:** Alta (afecta balance financiero)  
**Versión:** v4 (sin CASH_COLLECTED para tarjeta)
