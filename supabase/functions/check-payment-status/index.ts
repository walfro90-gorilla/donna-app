// Edge Function: check-payment-status
// Consulta el estado de un pago en MercadoPago

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const MERCADOPAGO_ACCESS_TOKEN = 'TEST-370130263007340-111601-cd398dbc6540245e85a4c1f566bd30c9-479630144'
const MERCADOPAGO_API_URL = 'https://api.mercadopago.com'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CheckPaymentRequest {
  payment_id: string
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    console.log('🔍 [CHECK-PAYMENT-STATUS] Iniciando consulta...')
    
    // Parse request body
    const body: CheckPaymentRequest = await req.json()
    console.log('📦 [CHECK-PAYMENT-STATUS] Body recibido:', JSON.stringify(body, null, 2))
    
    const { payment_id } = body

    if (!payment_id) {
      throw new Error('Falta parámetro requerido: payment_id')
    }

    // Inicializar Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    console.log('🔍 [CHECK-PAYMENT-STATUS] Buscando pago en base de datos...')
    
    // Buscar el pago en la base de datos
    const { data: payment, error: paymentError } = await supabase
      .from('payments')
      .select('*')
      .eq('id', payment_id)
      .single()

    if (paymentError || !payment) {
      throw new Error(`Pago no encontrado: ${payment_id}`)
    }

    console.log('✅ [CHECK-PAYMENT-STATUS] Pago encontrado:', payment)

    // Si el pago ya está procesado (approved, rejected, refunded), retornar estado local
    if (['approved', 'rejected', 'refunded'].includes(payment.status)) {
      console.log('✅ [CHECK-PAYMENT-STATUS] Pago ya procesado, retornando estado local')
      return new Response(
        JSON.stringify({
          success: true,
          status: payment.status,
          mp_payment_id: payment.mp_payment_id,
          mp_status_detail: payment.mp_status_detail,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        }
      )
    }

    // Si está pending, consultar estado en MercadoPago
    if (payment.mp_payment_id) {
      console.log('🔍 [CHECK-PAYMENT-STATUS] Consultando estado en MercadoPago...')
      
      const mpResponse = await fetch(`${MERCADOPAGO_API_URL}/v1/payments/${payment.mp_payment_id}`, {
        method: 'GET',
        headers: {
          'Authorization': `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
          'Content-Type': 'application/json',
        },
      })

      const mpData = await mpResponse.json()
      console.log('📥 [CHECK-PAYMENT-STATUS] Respuesta de MercadoPago:', JSON.stringify(mpData, null, 2))

      if (!mpResponse.ok) {
        throw new Error(`Error de MercadoPago: ${JSON.stringify(mpData)}`)
      }

      // Actualizar estado en base de datos
      const newStatus = mpData.status === 'approved' ? 'approved' : mpData.status === 'rejected' ? 'rejected' : 'pending'
      
      console.log('💾 [CHECK-PAYMENT-STATUS] Actualizando estado en base de datos:', newStatus)
      
      await supabase
        .from('payments')
        .update({
          status: newStatus,
          mp_status: mpData.status,
          mp_status_detail: mpData.status_detail,
          updated_at: new Date().toISOString(),
        })
        .eq('id', payment_id)

      return new Response(
        JSON.stringify({
          success: true,
          status: newStatus,
          mp_payment_id: payment.mp_payment_id,
          mp_status: mpData.status,
          mp_status_detail: mpData.status_detail,
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 200,
        }
      )
    }

    // Si no tiene mp_payment_id, está aún en pending inicial
    return new Response(
      JSON.stringify({
        success: true,
        status: 'pending',
        message: 'Pago pendiente de procesamiento',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )

  } catch (error: any) {
    console.error('❌ [CHECK-PAYMENT-STATUS] Error:', error)
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
