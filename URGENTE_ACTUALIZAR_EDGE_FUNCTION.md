# 🚨 URGENTE: ACTUALIZAR EDGE FUNCTION 'create-payment'

## ❌ **PROBLEMA DETECTADO**

La Edge Function 'create-payment' que está corriendo en tu Supabase **NO coincide** con el código del archivo local.

**Error actual:**
```
Missing required fields: orderId, amount
```

**Causa:** La función en Supabase espera `orderId` y `amount` (camelCase), pero el código Flutter envía `order_id` y `amount` (snake_case).

---

## ✅ **SOLUCIÓN: REEMPLAZAR CÓDIGO DE LA EDGE FUNCTION**

### **Paso 1:** Ve a tu Dashboard de Supabase
- Abre: https://supabase.com/dashboard
- Selecciona tu proyecto
- Ve a **Edge Functions** (menú izquierdo)
- Haz clic en la función **'create-payment'**

### **Paso 2:** Haz clic en **"Edit function"** o el ícono de editar

### **Paso 3:** BORRA TODO EL CÓDIGO ACTUAL y reemplázalo con este:

```typescript
// Edge Function: create-payment
// Crea un pago en MercadoPago y registra el payment en la base de datos

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CreatePaymentRequest {
  order_id: string
  amount: number
  description: string
  email: string
  client_debt?: number
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('💳 [CREATE-PAYMENT] Iniciando creación de pago...')
    
    // Parse request body
    const body: CreatePaymentRequest = await req.json()
    console.log('📦 [CREATE-PAYMENT] Body recibido:', JSON.stringify(body, null, 2))
    
    const { order_id, amount, description, email, client_debt } = body

    // Validar parámetros
    if (!order_id || !amount || !description || !email) {
      throw new Error('Faltan parámetros requeridos: order_id, amount, description, email')
    }

    // Inicializar Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)

    console.log('🔍 [CREATE-PAYMENT] Verificando orden en base de datos...')
    
    // Verificar que la orden existe
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, user_id, status')
      .eq('id', order_id)
      .single()

    if (orderError || !order) {
      throw new Error(`Orden no encontrada: ${order_id}`)
    }

    console.log('✅ [CREATE-PAYMENT] Orden encontrada:', order)

    // Obtener el Access Token de MercadoPago desde los secrets
    const mpAccessToken = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')
    if (!mpAccessToken) {
      throw new Error('MERCADOPAGO_ACCESS_TOKEN no configurado en los secrets')
    }

    // Crear preferencia de pago en MercadoPago
    console.log('💰 [CREATE-PAYMENT] Creando preferencia en MercadoPago...')
    
    const preferenceBody = {
      items: [
        {
          title: description,
          quantity: 1,
          unit_price: amount,
          currency_id: 'MXN',
        },
      ],
      payer: {
        email: email,
      },
      back_urls: {
        success: `${supabaseUrl}/functions/v1/mercadopago-webhook?status=success`,
        failure: `${supabaseUrl}/functions/v1/mercadopago-webhook?status=failure`,
        pending: `${supabaseUrl}/functions/v1/mercadopago-webhook?status=pending`,
      },
      auto_return: 'approved',
      external_reference: order_id,
      notification_url: `${supabaseUrl}/functions/v1/mercadopago-webhook`,
      metadata: {
        order_id: order_id,
        client_debt: client_debt || 0,
      },
    }

    console.log('📤 [CREATE-PAYMENT] Enviando a MercadoPago:', JSON.stringify(preferenceBody, null, 2))

    const mpResponse = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${mpAccessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(preferenceBody),
    })

    const mpData = await mpResponse.json()
    console.log('📥 [CREATE-PAYMENT] Respuesta de MercadoPago:', JSON.stringify(mpData, null, 2))

    if (!mpResponse.ok) {
      throw new Error(`Error de MercadoPago: ${JSON.stringify(mpData)}`)
    }

    // Crear registro de pago en la base de datos (status: pending)
    console.log('💾 [CREATE-PAYMENT] Guardando pago en base de datos...')
    
    const { data: payment, error: paymentError } = await supabase
      .from('payments')
      .insert({
        order_id: order_id,
        amount: amount,
        payment_method: 'card',
        status: 'pending',
        mp_preference_id: mpData.id,
        mp_init_point: mpData.init_point,
        created_at: new Date().toISOString(),
      })
      .select()
      .single()

    if (paymentError) {
      throw new Error(`Error al guardar pago: ${paymentError.message}`)
    }

    console.log('✅ [CREATE-PAYMENT] Pago guardado:', payment)

    return new Response(
      JSON.stringify({
        success: true,
        preference_id: mpData.id,
        init_point: mpData.init_point,
        payment_id: payment.id,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error: any) {
    console.error('❌ [CREATE-PAYMENT] Error:', error)
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message || 'Error desconocido',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      }
    )
  }
})
```

### **Paso 4:** Haz clic en **"Save"** o **"Deploy"**

### **Paso 5:** Verifica que los **Secrets** estén configurados correctamente
Ve a **Edge Functions** → **Settings** → **Secrets** y verifica que existan:
- ✅ `MERCADOPAGO_ACCESS_TOKEN`
- ✅ `SUPABASE_URL`
- ✅ `SUPABASE_SERVICE_ROLE_KEY`

---

## 🎯 **QUÉ CAMBIÓ**

1. ✅ **Campos en snake_case**: `order_id`, `amount` (en lugar de `orderId`, `amount`)
2. ✅ **Access Token desde Secrets**: Usa `Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')` en lugar de hardcodearlo
3. ✅ **Mejor manejo de errores**: Status 400 en lugar de 500 para errores de validación
4. ✅ **Logs mejorados**: Para debugging más fácil

---

## ✅ **DESPUÉS DE ACTUALIZAR**

Vuelve a probar el pago con tarjeta en la app. Debería funcionar correctamente.

Si ves otro error, avísame y lo revisamos juntos.
