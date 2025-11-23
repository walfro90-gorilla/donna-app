// Edge Function: process-card-payment
// Procesa un pago con tarjeta directamente y crea la orden en tiempo real

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const MERCADOPAGO_ACCESS_TOKEN = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!
const MERCADOPAGO_API_URL = 'https://api.mercadopago.com'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ProcessCardPaymentRequest {
  card_data: {
    card_number: string
    cardholder_name: string
    expiration_month: string
    expiration_year: string
    security_code: string
    identification_type: string
    identification_number: string
  }
  installments: number
  payer: {
    email: string
    identification?: {
      type: string
      number: string
    }
  }
  amount: number
  description: string
  order_data: {
    user_id: string
    restaurant_id: string
    total_amount: number
    delivery_address: string
    delivery_lat: number
    delivery_lon: number
    delivery_place_id?: string
    delivery_address_structured?: any
    order_notes?: string
    items: Array<{
      product_id: string
      quantity: number
      unit_price: number
      price_at_time_of_order: number
    }>
  }
  client_debt?: number
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('💳 [PROCESS-CARD-PAYMENT] Iniciando procesamiento de pago con tarjeta (100% server-side)...')
    
    const body: ProcessCardPaymentRequest = await req.json()
    console.log('📦 [PROCESS-CARD-PAYMENT] Body recibido:', {
      has_card_data: !!body.card_data,
      installments: body.installments,
      amount: body.amount,
      payer_email: body.payer.email,
      has_order_data: !!body.order_data,
    })

    // Validar parámetros
    if (!body.card_data || !body.amount || !body.payer.email || !body.order_data) {
      throw new Error('Faltan parámetros requeridos')
    }

    // Inicializar Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Redondear amount a 2 decimales
    const roundedAmount = Math.round(body.amount * 100) / 100
    console.log('💰 [PROCESS-CARD-PAYMENT] Amount redondeado:', roundedAmount)

    // PASO 1: Crear token de tarjeta usando MercadoPago API
    console.log('🔐 [PROCESS-CARD-PAYMENT] Paso 1: Tokenizando tarjeta...')
    
    const tokenPayload = {
      card_number: body.card_data.card_number,
      security_code: body.card_data.security_code,
      expiration_month: parseInt(body.card_data.expiration_month),
      expiration_year: parseInt(body.card_data.expiration_year),
      cardholder: {
        name: body.card_data.cardholder_name,
        identification: {
          type: body.card_data.identification_type,
          number: body.card_data.identification_number,
        },
      },
    }

    console.log('📤 [PROCESS-CARD-PAYMENT] Tokenizando tarjeta en MercadoPago...')
    const tokenResponse = await fetch(`${MERCADOPAGO_API_URL}/v1/card_tokens`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(tokenPayload),
    })

    const tokenData = await tokenResponse.json()
    console.log('📥 [PROCESS-CARD-PAYMENT] Respuesta de tokenización:', JSON.stringify(tokenData))

    if (!tokenResponse.ok) {
      console.error('❌ [PROCESS-CARD-PAYMENT] Error al tokenizar tarjeta:', JSON.stringify(tokenData, null, 2))
      
      let errorMessage = 'Error al procesar datos de tarjeta'
      if (tokenData.message) {
        errorMessage = tokenData.message
      } else if (tokenData.cause && tokenData.cause.length > 0) {
        errorMessage = tokenData.cause[0].description || tokenData.cause[0].code || errorMessage
      } else if (tokenData.error) {
        errorMessage = tokenData.error
      }
      
      throw new Error(errorMessage)
    }

    const cardToken = tokenData.id
    const paymentMethodId = tokenData.payment_method_id
    const issuerId = tokenData.issuer_id
    console.log(`✅ [PROCESS-CARD-PAYMENT] Token creado: ${cardToken.substring(0, 10)}..., payment_method=${paymentMethodId}`)

    // PASO 2: Crear pago usando el token
    console.log('💳 [PROCESS-CARD-PAYMENT] Paso 2: Creando pago en MercadoPago...')
    
    const paymentPayload: any = {
      transaction_amount: roundedAmount,
      token: cardToken,
      description: body.description,
      installments: body.installments,
      payment_method_id: paymentMethodId,
      payer: {
        email: body.payer.email,
        identification: body.payer.identification,
      },
      statement_descriptor: 'DOA REPARTOS',
      metadata: {
        user_id: body.order_data.user_id,
        restaurant_id: body.order_data.restaurant_id,
        client_debt: body.client_debt || 0,
      },
    }

    // Solo agregar issuer_id si existe
    if (issuerId) {
      paymentPayload.issuer_id = issuerId
    }

    console.log('📤 [PROCESS-CARD-PAYMENT] Payload a MercadoPago (sin token):', {
      ...paymentPayload,
      token: '[HIDDEN]',
    })

    const mpResponse = await fetch(`${MERCADOPAGO_API_URL}/v1/payments`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
        'Content-Type': 'application/json',
        'X-Idempotency-Key': `${body.order_data.user_id}_${Date.now()}`,
      },
      body: JSON.stringify(paymentPayload),
    })

    const mpData = await mpResponse.json()
    console.log('📥 [PROCESS-CARD-PAYMENT] Respuesta completa de pago:', JSON.stringify(mpData))

    if (!mpResponse.ok) {
      console.error('❌ [PROCESS-CARD-PAYMENT] Error de MercadoPago:', JSON.stringify(mpData, null, 2))
      
      let errorMessage = 'Error al procesar el pago'
      if (mpData.message) {
        errorMessage = mpData.message
      } else if (mpData.cause && mpData.cause.length > 0) {
        errorMessage = mpData.cause[0].description || mpData.cause[0].code || errorMessage
      } else if (mpData.error) {
        errorMessage = mpData.error
      }
      
      throw new Error(errorMessage)
    }

    // Verificar estado del pago
    const paymentStatus = mpData.status
    const paymentId = mpData.id
    const statusDetail = mpData.status_detail

    console.log(`💳 [PROCESS-CARD-PAYMENT] Pago creado: ID=${paymentId}, Status=${paymentStatus}, Detail=${statusDetail}`)

    // Si el pago fue rechazado, retornar error inmediatamente
    if (paymentStatus === 'rejected') {
      return new Response(
        JSON.stringify({
          success: false,
          status: 'rejected',
          error: statusDetail || 'Pago rechazado',
          payment_id: paymentId,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200, // 200 porque es un rechazo esperado, no un error de servidor
        }
      )
    }

    // **CREAR LA ORDEN INMEDIATAMENTE** (independiente del status del pago)
    console.log('📝 [PROCESS-CARD-PAYMENT] Creando orden en Supabase...')
    
    const orderData = body.order_data
    const { data: newOrder, error: createOrderError } = await supabase
      .from('orders')
      .insert({
        user_id: orderData.user_id,
        restaurant_id: orderData.restaurant_id,
        total_amount: orderData.total_amount,
        delivery_address: orderData.delivery_address,
        delivery_lat: orderData.delivery_lat,
        delivery_lon: orderData.delivery_lon,
        delivery_place_id: orderData.delivery_place_id,
        delivery_address_structured: orderData.delivery_address_structured,
        order_notes: orderData.order_notes,
        payment_method: 'card',
        status: paymentStatus === 'approved' ? 'pending' : 'pending',
        created_at: new Date().toISOString(),
      })
      .select()
      .single()

    if (createOrderError) {
      console.error('❌ [PROCESS-CARD-PAYMENT] Error al crear orden:', createOrderError)
      throw new Error(`Error al crear orden: ${createOrderError.message}`)
    }

    const orderId = newOrder.id
    console.log('✅ [PROCESS-CARD-PAYMENT] Orden creada:', orderId)

    // Crear order_items
    const items = orderData.items.map((item) => ({
      order_id: orderId,
      product_id: item.product_id,
      quantity: item.quantity,
      unit_price: item.unit_price,
      price_at_time_of_order: item.price_at_time_of_order,
      created_at: new Date().toISOString(),
    }))

    const { error: itemsError } = await supabase
      .from('order_items')
      .insert(items)

    if (itemsError) {
      console.error('❌ [PROCESS-CARD-PAYMENT] Error al crear order_items:', itemsError)
      // No lanzar error - la orden ya existe
    } else {
      console.log('✅ [PROCESS-CARD-PAYMENT] Order items creados')
    }

    // Crear registro de pago en Supabase
    console.log('💾 [PROCESS-CARD-PAYMENT] Guardando pago en base de datos...')
    
    const paymentInsert = {
      order_id: orderId,
      amount: roundedAmount,
      payment_method: 'card',
      status: paymentStatus === 'approved' ? 'completed' : paymentStatus === 'pending' ? 'pending' : 'failed',
      mp_payment_id: paymentId.toString(),
      payment_provider_id: paymentId.toString(),
      provider: 'mercadopago',
      client_debt_amount: body.client_debt || 0,
      paid_at: paymentStatus === 'approved' ? new Date().toISOString() : null,
      payment_details: {
        payment_method_id: body.payment_method_id,
        installments: body.installments,
        status_detail: statusDetail,
      },
      created_at: new Date().toISOString(),
    }

    const { data: payment, error: paymentError } = await supabase
      .from('payments')
      .insert(paymentInsert)
      .select()
      .single()

    if (paymentError) {
      console.error('❌ [PROCESS-CARD-PAYMENT] Error al guardar pago:', paymentError)
      // No lanzar error - la orden ya existe
    } else {
      console.log('✅ [PROCESS-CARD-PAYMENT] Pago guardado:', payment.id)
    }

    // Si el pago fue aprobado, procesar deuda del cliente
    if (paymentStatus === 'approved' && body.client_debt && body.client_debt > 0) {
      console.log(`💰 [PROCESS-CARD-PAYMENT] Procesando deuda del cliente: ${body.client_debt}`)
      
      const { error: debtError } = await supabase
        .from('client_debts')
        .update({
          status: 'paid',
          paid_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('client_id', orderData.user_id)
        .eq('status', 'pending')

      if (debtError) {
        console.error('❌ [PROCESS-CARD-PAYMENT] Error al actualizar deuda:', debtError)
      } else {
        console.log('✅ [PROCESS-CARD-PAYMENT] Deuda marcada como pagada')
      }
    }

    // NOTA: Las transacciones de account_transactions se crean automáticamente 
    // mediante el trigger SQL 'trigger_process_order_financial_transactions'
    // cuando la orden cambia a status 'delivered'.
    // Para pago con tarjeta (payment_method='card'), se crean 3 transacciones:
    // 1. ORDER_REVENUE (credit a restaurant_account) = product_total
    // 2. PLATFORM_COMMISSION (debit a restaurant_account) = product_total * 0.20
    // 3. DELIVERY_EARNING (credit a delivery_account) = delivery_fee * 0.85
    
    // Calcular montos anticipados (el trigger SQL hará los cálculos reales)
    const deliveryFee = 35.00 // Default según schema
    const productTotal = orderData.total_amount - deliveryFee
    const platformCommission = productTotal * 0.20
    const restaurantNet = productTotal - platformCommission
    const deliveryEarning = deliveryFee * 0.85
    const platformDeliveryMargin = deliveryFee - deliveryEarning
    
    console.log('ℹ️  [PROCESS-CARD-PAYMENT] Las transacciones de account_transactions se crearán cuando la orden sea entregada')
    console.log(`ℹ️  [PROCESS-CARD-PAYMENT] Distribución estimada (se confirma al entregar):`)
    console.log(`   - Total orden: $${orderData.total_amount.toFixed(2)}`)
    console.log(`   - Subtotal productos: $${productTotal.toFixed(2)}`)
    console.log(`   - Ganancia neta restaurant: $${restaurantNet.toFixed(2)}`)
    console.log(`   - Comisión plataforma (20%): $${platformCommission.toFixed(2)}`)
    console.log(`   - Ganancia delivery (85% de $${deliveryFee}): $${deliveryEarning.toFixed(2)}`)
    console.log(`   - Margen plataforma delivery (15%): $${platformDeliveryMargin.toFixed(2)}`)

    // Retornar resultado
    return new Response(
      JSON.stringify({
        success: true,
        status: paymentStatus,
        status_detail: statusDetail,
        order_id: orderId,
        payment_id: paymentId,
        message: paymentStatus === 'approved' 
          ? 'Pago procesado exitosamente' 
          : 'Pago en proceso de validación',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error: any) {
    console.error('❌ [PROCESS-CARD-PAYMENT] Error:', error)
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
