# 🚀 Configuración de MercadoPago

Esta guía te ayudará a configurar MercadoPago en tu proyecto desde cero.

---

## 📋 **REQUISITOS PREVIOS**

1. ✅ Cuenta de MercadoPago activa (https://www.mercadopago.com.mx)
2. ✅ Proyecto de Supabase configurado
3. ✅ Scripts SQL ejecutados (ver `/sql_migrations/2025-01-16_mercadopago_integration.sql`)

---

## 🔑 **PASO 1: OBTENER CREDENCIALES DE MERCADOPAGO**

### 1️⃣ **Acceder al Panel de Desarrolladores:**
- Ir a: https://www.mercadopago.com/developers/panel/app
- Iniciar sesión con tu cuenta de MercadoPago

### 2️⃣ **Crear o Seleccionar una Aplicación:**
- Si no tienes ninguna, haz clic en **"Crear aplicación"**
- Nombre sugerido: "DoA Repartos"
- Tipo: **"Pagos online"**

### 3️⃣ **Obtener las Credenciales:**

#### **Para Testing (Sandbox):**
- Access Token: `TEST-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`
- Public Key: `TEST-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`

#### **Para Producción:**
- Access Token: `APP_USR-XXXXXXXX-XXXXXXXX-XXXXXXXX-XXXXXXXX`
- Public Key: `APP_USR-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`

> ⚠️ **IMPORTANTE:** Nunca compartas tu Access Token. Es como tu contraseña.

---

## 🔐 **PASO 2: CONFIGURAR SECRETS EN SUPABASE**

### 1️⃣ **Acceder a Supabase Dashboard:**
- Ir a: https://app.supabase.com
- Seleccionar tu proyecto
- Ir a **"Project Settings"** → **"Edge Functions"** → **"Secrets"**

### 2️⃣ **Agregar el Secret:**

Ejecutar en terminal (con Supabase CLI):

```bash
# Instalar Supabase CLI si no lo tienes
npm install -g supabase

# Login
supabase login

# Link a tu proyecto
supabase link --project-ref TU_PROJECT_REF

# Agregar el secret
supabase secrets set MERCADOPAGO_ACCESS_TOKEN=TU_ACCESS_TOKEN
```

O manualmente desde el Dashboard:
- **Name:** `MERCADOPAGO_ACCESS_TOKEN`
- **Value:** Tu Access Token de MercadoPago (con o sin `TEST-` según ambiente)

---

## 📦 **PASO 3: DESPLEGAR EDGE FUNCTIONS**

### 1️⃣ **Verificar Archivos Creados:**

```
supabase/functions/
├── mercadopago-handler/
│   └── index.ts
└── mercadopago-webhook/
    └── index.ts
```

### 2️⃣ **Desplegar Functions:**

```bash
# Desde la raíz del proyecto
supabase functions deploy mercadopago-handler
supabase functions deploy mercadopago-webhook
```

### 3️⃣ **Verificar Despliegue:**

```bash
supabase functions list
```

Deberías ver:
- ✅ `mercadopago-handler` (ACTIVE)
- ✅ `mercadopago-webhook` (ACTIVE)

---

## 🔔 **PASO 4: CONFIGURAR WEBHOOK EN MERCADOPAGO**

### 1️⃣ **Obtener URL del Webhook:**

Tu URL será algo como:
```
https://TU_PROJECT_REF.supabase.co/functions/v1/mercadopago-webhook
```

### 2️⃣ **Configurar en MercadoPago:**

1. Ir a: https://www.mercadopago.com/developers/panel/app
2. Seleccionar tu aplicación
3. Ir a **"Webhooks"** o **"Notificaciones IPN"**
4. Agregar nuevo webhook:
   - **URL:** Tu URL del webhook de Supabase
   - **Eventos:** Seleccionar `payment` (Pagos)
   - **Versión:** v1

### 3️⃣ **Probar el Webhook:**

MercadoPago tiene una herramienta de testing en el panel. Envía un pago de prueba y verifica que tu función lo reciba.

---

## ✅ **PASO 5: HABILITAR PAGOS EN LA APP**

### 1️⃣ **Verificar que el Feature Flag esté Activo:**

Por defecto, el pago con tarjeta ya está habilitado en `checkout_screen.dart`:

```dart
ListTile(
  contentPadding: EdgeInsets.zero,
  leading: Radio<PaymentMethod>(
    value: PaymentMethod.card,
    groupValue: _selectedPaymentMethod,
    onChanged: (value) => setState(() => _selectedPaymentMethod = value!),
  ),
  title: const Text('Credit/Debit Card'),
  subtitle: const Text('Pay with credit or debit card (via Mercado Pago)'),
  trailing: const Icon(Icons.credit_card),
),
```

### 2️⃣ **Probar el Flujo Completo:**

1. ✅ Crear una orden con pago en efectivo (sin MercadoPago)
2. ✅ Crear una orden con tarjeta (debe abrir MercadoPago Checkout)
3. ✅ Completar el pago en MercadoPago
4. ✅ Verificar que la orden se marque como "paid" en Supabase
5. ✅ Verificar que se creen las transacciones correctamente

---

## 🧪 **PASO 6: TESTING CON TARJETAS DE PRUEBA**

MercadoPago proporciona tarjetas de prueba para el ambiente sandbox:

### **Tarjetas Aprobadas:**

| Tarjeta          | Número           | CVV  | Fecha de Expiración |
|------------------|------------------|------|---------------------|
| Visa             | 4509 9535 6623 3704 | 123  | 11/25              |
| Mastercard       | 5031 7557 3453 0604 | 123  | 11/25              |
| American Express | 3711 803032 57522   | 1234 | 11/25              |

### **Tarjetas Rechazadas:**

| Tarjeta    | Número           | Motivo                  |
|------------|------------------|-------------------------|
| Visa       | 4000 0000 0000 0002 | Fondos insuficientes    |
| Mastercard | 5000 0000 0000 0003 | Tarjeta rechazada       |

Más info: https://www.mercadopago.com.mx/developers/es/docs/checkout-api/testing

---

## 🔍 **MONITOREO Y LOGS**

### 1️⃣ **Ver Logs de Edge Functions:**

```bash
supabase functions logs mercadopago-handler
supabase functions logs mercadopago-webhook
```

O desde el Dashboard:
- Ir a **"Edge Functions"** → Seleccionar la función → **"Logs"**

### 2️⃣ **Verificar Pagos en MercadoPago:**

- Ir a: https://www.mercadopago.com/activities
- Ver todos los pagos procesados con su estado

### 3️⃣ **Verificar en Supabase:**

```sql
-- Ver pagos recientes
SELECT * FROM payments 
ORDER BY created_at DESC 
LIMIT 10;

-- Ver órdenes pagadas
SELECT * FROM orders 
WHERE payment_status = 'paid' 
ORDER BY created_at DESC;

-- Ver transacciones de cuenta
SELECT * FROM account_transactions 
WHERE type IN ('ORDER_PAYMENT', 'PAYMENT_DEBT')
ORDER BY created_at DESC;
```

---

## 🚨 **TROUBLESHOOTING**

### ❌ **Error: "MERCADOPAGO_ACCESS_TOKEN is not defined"**
- Verificar que el secret esté configurado en Supabase
- Redesplegar la Edge Function después de agregar el secret

### ❌ **Error: "Webhook not receiving notifications"**
- Verificar que la URL del webhook sea correcta
- Verificar que el webhook esté activo en el panel de MercadoPago
- Revisar los logs de la Edge Function

### ❌ **Error: "Payment status not updating in app"**
- Verificar que el webhook esté funcionando (revisar logs)
- Verificar que el `external_reference` (order_id) sea correcto
- Verificar que las transacciones se estén creando en `account_transactions`

### ❌ **Error: "Checkout not loading"**
- Verificar que la preferencia se esté creando correctamente (logs)
- Verificar que el Access Token sea válido
- Verificar la conexión a internet del dispositivo

---

## 📚 **RECURSOS ADICIONALES**

- **Documentación de MercadoPago:** https://www.mercadopago.com.mx/developers
- **Checkout Pro:** https://www.mercadopago.com.mx/developers/es/docs/checkout-pro/landing
- **Supabase Edge Functions:** https://supabase.com/docs/guides/functions
- **Testing:** https://www.mercadopago.com.mx/developers/es/docs/checkout-api/testing

---

## ✅ **CHECKLIST FINAL**

Antes de ir a producción:

- [ ] Access Token de PRODUCCIÓN configurado en Supabase
- [ ] Edge Functions desplegadas correctamente
- [ ] Webhook configurado y funcionando
- [ ] Flujo completo probado con tarjetas de prueba
- [ ] Logs monitoreados sin errores
- [ ] Transacciones de cuenta creándose correctamente
- [ ] Deudas de clientes liquidándose correctamente
- [ ] Email de notificaciones de MercadoPago configurado
- [ ] Backups de base de datos configurados

---

¡Listo! 🎉 Tu integración con MercadoPago está completa.
