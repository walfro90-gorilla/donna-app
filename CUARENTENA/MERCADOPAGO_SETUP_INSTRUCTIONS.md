# 🚀 INSTRUCCIONES FINALES PARA COMPLETAR MERCADOPAGO

## ✅ **ESTADO ACTUAL:**
- ✅ Edge Functions creadas y desplegadas en Supabase
- ✅ Servicio Flutter configurado
- ✅ Pantalla de checkout implementada
- ✅ WebView instalado

---

## 📋 **PASOS FINALES:**

### **1️⃣ CONFIGURAR SECRETS EN SUPABASE**

Ve a tu proyecto de Supabase → **Edge Functions** → **Settings** → **Secrets** y agrega:

```bash
MERCADOPAGO_ACCESS_TOKEN=TEST-370130263007340-111601-cd398dbc6540245e85a4c1f566bd30c9-479630144
MERCADOPAGO_PUBLIC_KEY=TEST-0a2bcd27-5f9b-40c9-ab05-d7bfe539bb1b
SUPABASE_URL=https://tu-proyecto.supabase.co
SUPABASE_SERVICE_ROLE_KEY=tu-service-role-key
```

**IMPORTANTE**: Reemplaza `SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` con tus valores reales.

Para encontrar tu Service Role Key:
- Ve a **Project Settings** → **API** → **Project API keys**
- Copia el valor de **service_role** (secret)

---

### **2️⃣ CONFIGURAR WEBHOOKS EN MERCADOPAGO**

Para que MercadoPago notifique automáticamente cuando un pago se procesa:

1. Ve a tu cuenta de MercadoPago: https://www.mercadopago.com.mx/developers/panel
2. Ve a **Tu integración** → **Configuración** → **Webhooks**
3. Agrega una nueva URL de webhook:
   ```
   https://tu-proyecto.supabase.co/functions/v1/mercadopago-webhook
   ```
4. Selecciona los eventos a notificar:
   - ✅ **payment** (pagos)
   - ✅ **merchant_order** (órdenes)

**Nota**: Por ahora estás en modo TEST, así que usa la URL de staging de Supabase. Cuando pases a producción, actualiza el webhook.

---

### **3️⃣ CONFIGURAR URLS DE CALLBACK**

Las Edge Functions ya están configuradas para usar estas URLs de callback (definidas en el código):

- **Success**: `https://tu-app.com/payment/success`
- **Failure**: `https://tu-app.com/payment/failure`
- **Pending**: `https://tu-app.com/payment/pending`

**IMPORTANTE**: Estas URLs son detectadas por el WebView para cerrar el checkout y regresar a la app. No necesitas crearlas, el WebView las intercepta automáticamente.

---

### **4️⃣ PROBAR EL FLUJO COMPLETO**

1. Crea una orden con método de pago **"Card"**
2. Se abrirá el checkout de MercadoPago
3. Usa estas tarjetas de prueba:

**TARJETAS DE PRUEBA APROBADAS:**
- **Visa**: 4509 9535 6623 3704
- **Mastercard**: 5031 7557 3453 0604
- **CVV**: cualquier 3 dígitos (123)
- **Fecha**: cualquier fecha futura (12/25)
- **Nombre**: cualquier nombre (APRO)

**TARJETAS DE PRUEBA RECHAZADAS:**
- **Visa**: 4000 0000 0000 0002 (fondos insuficientes)
- **Nombre**: OXXO (pago rechazado)

4. Completa el pago
5. El WebView detectará el callback de success/failure/pending
6. La orden se actualizará automáticamente en Supabase

---

### **5️⃣ VERIFICAR QUE TODO FUNCIONA**

1. **Ver logs de Edge Functions**:
   - Ve a Supabase → **Edge Functions** → **Logs**
   - Busca logs de `create-payment`, `check-payment-status`, `mercadopago-webhook`

2. **Ver pagos en MercadoPago**:
   - https://www.mercadopago.com.mx/developers/panel/testing/test-payments

3. **Ver transacciones en Supabase**:
   - Tabla `payments`: Verifica que se creó el pago
   - Tabla `account_transactions`: Verifica que se registraron las transacciones financieras
   - Tabla `client_debts`: Verifica que se liquidó el adeudo (si había)

---

## 🎯 **SIGUIENTES PASOS (PRODUCCIÓN)**

Cuando estés listo para producción:

1. **Cambiar a credenciales de producción**:
   - Access Token: `APP-XXX` (sin el prefijo TEST-)
   - Public Key: sin el prefijo TEST-
   - Actualizar en Supabase Secrets

2. **Configurar webhook de producción**

3. **Habilitar 3D Secure** para mayor seguridad

4. **Configurar notificaciones** para clientes cuando su pago sea procesado

---

## ❓ **PROBLEMAS COMUNES**

### **Error: "Access Token inválido"**
- Verifica que agregaste el secret correctamente en Supabase
- Asegúrate de que NO tenga espacios al inicio/final

### **Error: "CORS"**
- Los Edge Functions de Supabase ya tienen CORS habilitado por defecto
- Si tienes problemas, verifica que las URLs sean correctas

### **Webhook no se ejecuta**
- Verifica que configuraste el webhook en MercadoPago
- Revisa los logs de la Edge Function `mercadopago-webhook`

### **Pago aprobado pero orden no se actualiza**
- Revisa los logs del webhook
- Verifica que el Service Role Key tenga permisos de escritura

---

## 🎉 **¡LISTO!**

Tu sistema de pagos con MercadoPago está configurado. Solo necesitas:
1. Agregar los secrets en Supabase
2. Probar con tarjetas de prueba
3. Verificar que las transacciones se registren correctamente

¿Necesitas ayuda con algún paso específico?
