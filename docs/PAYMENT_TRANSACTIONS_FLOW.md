# 💳 Sistema de Transacciones - Flujo Completo

## 📋 Resumen

El sistema de transacciones financieras está diseñado para mantener **BALANCE 0** en todo momento. Cada orden genera transacciones que suman exactamente $0.00, distribuyendo el dinero entre las partes involucradas.

---

## 🔄 Flujos de Pago

### 1️⃣ PAGO CON TARJETA (MercadoPago)

#### **Fase 1: Creación de la Orden**

**Edge Function:** `process-card-payment/index.ts`

```
Cliente → MercadoPago → Edge Function → Supabase
```

**Acciones:**
1. Tokeniza tarjeta con MercadoPago API
2. Crea pago en MercadoPago
3. **Crea orden en Supabase** (status: `pending`, payment_method: `card`)
4. Crea registro en tabla `payments` con:
   - `status`: `completed` (si aprobado) / `pending` / `failed`
   - `mp_payment_id`: ID del pago en MercadoPago
   - `order_id`: ID de la orden creada
5. Si hay deuda del cliente, marca como pagada

**⚠️ IMPORTANTE:** 
- **NO se crean transacciones en `account_transactions` en esta fase**
- El dinero está "en tránsito" en la cuenta de MercadoPago

---

#### **Fase 2: Webhook de MercadoPago** (Opcional)

**Edge Function:** `mercadopago-webhook/index.ts`

```
MercadoPago → Webhook → Supabase
```

**Acciones:**
1. Recibe notificación de cambio de status del pago
2. Actualiza tabla `payments` con status actualizado
3. Si hay deuda del cliente, marca como pagada
4. **NO crea transacciones** (se crean en Fase 3)

---

#### **Fase 3: Entrega de la Orden** 🚚

**Trigger SQL:** `process_order_delivery_v3()`

```
Order status: pending → preparing → on_the_way → delivered
                                                    ↓
                                           [TRIGGER SE EJECUTA AQUÍ]
```

**Acciones al cambiar status a `delivered`:**

El trigger crea **6 transacciones** que suman exactamente **$0.00**:

| # | Tipo | Cuenta | Monto | Descripción |
|---|------|--------|-------|-------------|
| 1 | `PLATFORM_COMMISSION` | platform_revenue | **+$Y** | Comisión de la plataforma (15-30% del subtotal) |
| 2 | `PLATFORM_DELIVERY_MARGIN` | platform_revenue | **+$W** | Margen de la plataforma por delivery (15% del delivery_fee) |
| 3 | `RESTAURANT_PAYABLE` | platform_payables | **-$X** | Deuda de la plataforma al restaurant |
| 4 | `RESTAURANT_PAYABLE` | restaurant | **+$X** | Ganancia neta del restaurante (subtotal - comisión) |
| 5 | `DELIVERY_EARNING` | platform_payables | **-$Z** | Deuda de la plataforma al repartidor |
| 6 | `DELIVERY_EARNING` | delivery_agent | **+$Z** | Ganancia del repartidor (85% del delivery_fee) |

**Ejemplo con orden de $105.40:**
```
Subtotal productos: $70.40
Delivery fee: $35.00
Total: $105.40

Transacciones:
1. PLATFORM_COMMISSION (platform_revenue):     +$14.08  (70.40 × 0.20)
2. PLATFORM_DELIVERY_MARGIN (platform_revenue): +$5.25   (35.00 × 0.15)
3. RESTAURANT_PAYABLE (platform_payables):     -$56.32  (deuda con restaurant)
4. RESTAURANT_PAYABLE (restaurant):            +$56.32  (ganancia restaurant)
5. DELIVERY_EARNING (platform_payables):       -$29.75  (deuda con repartidor)
6. DELIVERY_EARNING (delivery_agent):          +$29.75  (ganancia repartidor)

SUMA TOTAL: $0.00 ✅
```

**💡 LÓGICA:**
- La plataforma **YA recibió el dinero completo** de MercadoPago ($105.40)
- La plataforma **gana** las comisiones: $14.08 + $5.25 = $19.33
- La plataforma **debe pagar** al restaurant: $56.32
- La plataforma **debe pagar** al repartidor: $29.75
- **NO hay CASH_COLLECTED** porque no es efectivo - el dinero ya está en la plataforma

**⚠️ CRÍTICO:**
- Las transacciones se crean **SOLO cuando la orden es entregada**
- Antes de eso, el dinero está en la cuenta de MercadoPago
- Las deudas (negativas) se registran en `platform_payables` hasta que se liquiden

---

### 2️⃣ PAGO EN EFECTIVO

#### **Fase 1: Creación de la Orden**

```
Cliente → App → Supabase
```

**Acciones:**
1. Crea orden con `payment_method: 'cash'`, `status: 'pending'`
2. **NO se crea registro en tabla `payments`**
3. **NO se crean transacciones**

---

#### **Fase 2: Entrega de la Orden** 💵

**Trigger SQL:** `process_order_delivery_v3()`

**Acciones al cambiar status a `delivered`:**

El trigger crea **5 transacciones** que suman exactamente **$0.00**:

| # | Tipo | Cuenta | Monto | Descripción |
|---|------|--------|-------|-------------|
| 1 | `RESTAURANT_PAYABLE` | restaurant | **+$X** | Ganancia neta del restaurante |
| 2 | `PLATFORM_COMMISSION` | platform_revenue | **+$Y** | Comisión de la plataforma |
| 3 | `DELIVERY_EARNING` | delivery_agent | **+$Z** | Ganancia del repartidor |
| 4 | `PLATFORM_DELIVERY_MARGIN` | platform_revenue | **+$W** | Margen de la plataforma por delivery |
| 5 | `CASH_COLLECTED` | delivery_agent | **-$TOTAL** | Efectivo recolectado por el repartidor |

**Ejemplo con orden de $105.40:**
```
Transacciones:
1. RESTAURANT_PAYABLE (restaurant):      +$56.32
2. PLATFORM_COMMISSION (platform):       +$14.08
3. DELIVERY_EARNING (delivery_agent):    +$29.75
4. PLATFORM_DELIVERY_MARGIN (platform):  +$5.25
5. CASH_COLLECTED (delivery_agent):      -$105.40

SUMA TOTAL: $0.00 ✅
```

**Diferencia clave con tarjeta:**
- Con efectivo: `CASH_COLLECTED` es **negativo en la cuenta del repartidor** (él cobra el efectivo)
- Con tarjeta: **NO hay CASH_COLLECTED** - la plataforma ya recibió el dinero de MercadoPago

---

## 🏦 Liquidaciones (Settlements)

Después de crear las transacciones, el trigger también crea **settlements pendientes**:

### Para TARJETA:
1. `platform_payables` → `restaurant`: $56.32 (pago neto)
2. `platform_payables` → `delivery_agent`: $29.75 (ganancia delivery)

### Para EFECTIVO:
1. `delivery_agent` → `platform_payables`: $75.65 (total - ganancia delivery)

**Estado:** `pending` hasta que se complete el settlement

---

## ⚖️ Validación de Balance 0

### Por Orden:
```sql
SELECT 
  order_id,
  SUM(amount) as balance
FROM account_transactions
WHERE order_id = 'xxx'
GROUP BY order_id;

-- Debe dar: balance = 0.00
```

### Por Cuenta:
```sql
SELECT 
  a.account_type,
  SUM(at.amount) as balance
FROM accounts a
LEFT JOIN account_transactions at ON at.account_id = a.id
GROUP BY a.account_type;
```

### Balance Global:
```sql
SELECT SUM(amount) as global_balance
FROM account_transactions;

-- Debe dar: 0.00
```

---

## 📊 Tipos de Transacciones Válidos

Según `DATABASE_SCHEMA.sql`:

| Tipo | Descripción | Cuándo se crea |
|------|-------------|----------------|
| `ORDER_REVENUE` | **⚠️ OBSOLETO** - Ya no se usa | N/A |
| `PLATFORM_COMMISSION` | Comisión de plataforma sobre productos | Al entregar |
| `DELIVERY_EARNING` | Ganancia del repartidor | Al entregar |
| `CASH_COLLECTED` | Cobro total (negativo para balance 0) | Al entregar |
| `SETTLEMENT_PAYMENT` | Pago de liquidación | Al liquidar |
| `SETTLEMENT_RECEPTION` | Recepción de liquidación | Al liquidar |
| `RESTAURANT_PAYABLE` | Monto a pagar al restaurante | Al entregar |
| `DELIVERY_PAYABLE` | Monto a pagar al repartidor | Al entregar |
| `PLATFORM_DELIVERY_MARGIN` | Margen de plataforma por delivery | Al entregar |
| `PLATFORM_NOT_DELIVERED_REFUND` | Reembolso por no entregado | Al marcar como no entregado |
| `CLIENT_DEBT` | Deuda del cliente | Al crear deuda |

---

## 🚨 Errores Comunes

### ❌ Balance no da 0

**Causa:** Transacciones creadas manualmente o por webhook antiguo

**Solución:** Ejecutar migración `2025-01-18_FIX_card_payment_transactions_balance_zero.sql`

### ❌ Transacciones duplicadas

**Causa:** Trigger se ejecutó múltiples veces

**Solución:** El constraint `uq_account_txn_order_account_type` previene duplicados

### ❌ Tipos de transacción inválidos (ORDER_PAYMENT, PAYMENT_DEBT)

**Causa:** Webhook antiguo creando transacciones incorrectas

**Solución:** La migración elimina estos tipos

---

## 🎯 Reglas de Oro

1. **NUNCA crear transacciones manualmente** - Solo el trigger `process_order_delivery_v3()`
2. **NUNCA crear transacciones en el webhook** - Solo actualizar status de payment
3. **SIEMPRE validar balance = 0** por orden antes de deployment
4. **NUNCA usar ORDER_REVENUE** - Es redundante con el nuevo sistema
5. **Las transacciones se crean SOLO al entregar**, no al pagar

---

## 📝 Checklist de Testing

- [ ] Orden con tarjeta aprobada → balance = 0 al entregar
- [ ] Orden con efectivo → balance = 0 al entregar
- [ ] Balance global = 0 después de múltiples órdenes
- [ ] No hay transacciones con tipos inválidos
- [ ] No hay duplicados (mismo order_id + account_id + type)
- [ ] Settlements se crean correctamente según payment_method

---

**Última actualización:** 2025-01-18  
**Versión del trigger:** `process_order_delivery_v4()` (sin CASH_COLLECTED para tarjeta)
