// Edge Function: create-payment
// Crea un pago en MercadoPago y registra el payment en la base de datos

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const MERCADOPAGO_ACCESS_TOKEN = 'TEST-370130263007340-111601-cd398dbc6540245e85a4c1f566bd30c9-479630144'
const MERCADOPAGO_API_URL = 'https://api.mercadopago.com'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CreatePaymentRequest {
  order_id: string // Puede estar vacío si se crea tras pago
  amount: number
  description: string
  email: string
  client_debt?: number
  order_data?: any // Datos para crear orden tras pago exitoso
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
    
    const { order_id, amount, description, email, client_debt, order_data } = body

    // Validar parámetros
    if (!amount || !description || !email) {
      throw new Error('Faltan parámetros requeridos: amount, description, email')
    }
    
    // Validar que amount sea un número válido y positivo
    if (typeof amount !== 'number' || isNaN(amount) || amount <= 0) {
      throw new Error(`El monto debe ser un número positivo. Recibido: ${amount}`)
    }

    // Inicializar Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // **FLUJO BIFURCADO**: 
    // 1. Si order_id existe y NO es temporal -> verificar orden
    // 2. Si order_data existe o order_id es temporal -> crear orden después del pago (webhook lo hará)
    
    const isTemporaryOrderId = order_id && order_id.startsWith('temp_')
    
    if (order_id && order_id.trim() !== '' && !isTemporaryOrderId) {
      console.log('🔍 [CREATE-PAYMENT] Verificando orden existente en base de datos...')
      
      const { data: order, error: orderError } = await supabase
        .from('orders')
        .select('id, user_id, status')
        .eq('id', order_id)
        .single()

      if (orderError || !order) {
        throw new Error(`Orden no encontrada: ${order_id}`)
      }

      console.log('✅ [CREATE-PAYMENT] Orden encontrada:', order)
    } else if (order_data || isTemporaryOrderId) {
      console.log('📝 [CREATE-PAYMENT] Orden se creará después del pago exitoso')
      if (isTemporaryOrderId) {
        console.log('🆔 [CREATE-PAYMENT] OrderId temporal detectado: ' + order_id)
      }
      if (order_data) {
        console.log('📝 [CREATE-PAYMENT] Cliente: ' + order_data.user_id)
        console.log('📝 [CREATE-PAYMENT] Restaurante: ' + order_data.restaurant_id)
      }
    } else {
      throw new Error('Debe proporcionar order_id o order_data')
    }

    // Crear preferencia de pago en MercadoPago
    console.log('💰 [CREATE-PAYMENT] Creando preferencia en MercadoPago...')
    console.log('   - amount original: ' + amount)
    
    // Redondear amount a 2 decimales (MercadoPago no acepta más)
    const roundedAmount = Math.round(amount * 100) / 100
    console.log('   - amount redondeado: ' + roundedAmount)
    
    const preferenceBody = {
      items: [
        {
          title: description,
          quantity: 1,
          unit_price: roundedAmount,
          currency_id: 'MXN',
        },
      ],
      payer: {
        email: email,
      },
      // MercadoPago requiere back_urls, pero para un flujo completamente automatizado
      // las manejamos en el webhook. Las URLs deben ser válidas.
      back_urls: {
        success: `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopago-webhook`,
        failure: `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopago-webhook`,
        pending: `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopago-webhook`,
      },
      auto_return: 'approved',
      external_reference: (order_id && !order_id.startsWith('temp_')) ? order_id : 'pending_creation',
      // notification_url es donde MercadoPago envía el IPN (Instant Payment Notification)
      notification_url: `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopago-webhook`,
      metadata: {
        order_id: (order_id && !order_id.startsWith('temp_')) ? order_id : null,
        client_debt: typeof client_debt === 'number' ? client_debt : 0,
        has_order_data: order_data ? true : false,
      },
    }

    console.log('📤 [CREATE-PAYMENT] Enviando a MercadoPago:', JSON.stringify(preferenceBody, null, 2))

    const mpResponse = await fetch(`${MERCADOPAGO_API_URL}/checkout/preferences`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
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
    
    const paymentInsert: any = {
      amount: amount,
      payment_method: 'card',
      status: 'pending',
      mp_preference_id: mpData.id,
      mp_init_point: mpData.init_point,
      created_at: new Date().toISOString(),
    }
    
    // Si order_id existe y NO es temporal, referenciarlo. Si no, el webhook lo creará
    if (order_id && order_id.trim() !== '' && !order_id.startsWith('temp_')) {
      paymentInsert.order_id = order_id
    }
    
    // Si hay order_data, guardarlo para el webhook
    if (order_data) {
      paymentInsert.order_data = order_data
      console.log('💾 [CREATE-PAYMENT] Guardando order_data en payment para webhook')
    }
    
    const { data: payment, error: paymentError } = await supabase
      .from('payments')
      .insert(paymentInsert)
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
        status: 500,
      }
    )
  }
})
