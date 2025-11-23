// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3';

const MERCADOPAGO_ACCESS_TOKEN = Deno.env.get('MERCADOPAGO_ACCESS_TOKEN')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

interface CreatePreferenceRequest {
  action: 'create_preference';
  order_id: string;
  total_amount: number;
  client_debt?: number;
  description: string;
  client_email: string;
}

interface ProcessPaymentRequest {
  action: 'process_payment';
  order_id: string;
  token: string;
  payment_method_id: string;
  amount: number;
  description: string;
  email: string;
}

interface GetPaymentStatusRequest {
  action: 'get_payment_status';
  payment_id: number;
}

interface RetryPaymentRequest {
  action: 'retry_payment';
  order_id: string;
  mp_payment_id: number;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const action = body.action;

    console.log(`🔄 [MP_HANDLER] Action: ${action}`);

    switch (action) {
      case 'create_preference':
        return await handleCreatePreference(body as CreatePreferenceRequest);
      case 'process_payment':
        return await handleProcessPayment(body as ProcessPaymentRequest);
      case 'get_payment_status':
        return await handleGetPaymentStatus(body as GetPaymentStatusRequest);
      case 'retry_payment':
        return await handleRetryPayment(body as RetryPaymentRequest);
      default:
        return new Response(
          JSON.stringify({ success: false, error: 'Invalid action' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
  } catch (error: any) {
    console.error('❌ [MP_HANDLER] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});

async function handleCreatePreference(body: CreatePreferenceRequest) {
  const { order_id, total_amount, client_debt, description, client_email } = body;

  console.log('💳 [CREATE_PREFERENCE] Creating preference...');
  console.log('   - order_id:', order_id);
  console.log('   - total_amount:', total_amount);
  console.log('   - client_debt:', client_debt);

  try {
    // Crear preferencia en MercadoPago
    const preferenceData = {
      items: [
        {
          title: description,
          quantity: 1,
          unit_price: total_amount,
          currency_id: 'MXN',
        },
      ],
      payer: {
        email: client_email,
      },
      back_urls: {
        success: `${SUPABASE_URL}/functions/v1/mercadopago-handler/payment/success`,
        failure: `${SUPABASE_URL}/functions/v1/mercadopago-handler/payment/failure`,
        pending: `${SUPABASE_URL}/functions/v1/mercadopago-handler/payment/pending`,
      },
      auto_return: 'approved',
      external_reference: order_id,
      metadata: {
        order_id,
        client_debt: client_debt || 0,
      },
      notification_url: `${SUPABASE_URL}/functions/v1/mercadopago-handler/webhook`,
    };

    const response = await fetch('https://api.mercadopago.com/checkout/preferences', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
      },
      body: JSON.stringify(preferenceData),
    });

    if (!response.ok) {
      const errorData = await response.json();
      console.error('❌ [CREATE_PREFERENCE] MercadoPago error:', errorData);
      throw new Error(`MercadoPago error: ${JSON.stringify(errorData)}`);
    }

    const preference = await response.json();
    console.log('✅ [CREATE_PREFERENCE] Preference created:', preference.id);

    // Actualizar orden en Supabase con preference_id
    await supabase
      .from('payments')
      .update({ mp_preference_id: preference.id })
      .eq('order_id', order_id);

    return new Response(
      JSON.stringify({
        success: true,
        preference_id: preference.id,
        init_point: preference.init_point,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('❌ [CREATE_PREFERENCE] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

async function handleProcessPayment(body: ProcessPaymentRequest) {
  const { order_id, token, payment_method_id, amount, description, email } = body;

  console.log('💳 [PROCESS_PAYMENT] Processing payment...');
  console.log('   - order_id:', order_id);
  console.log('   - payment_method_id:', payment_method_id);
  console.log('   - amount:', amount);

  try {
    const paymentData = {
      token,
      payment_method_id,
      transaction_amount: amount,
      description,
      installments: 1,
      payer: {
        email,
      },
      external_reference: order_id,
      metadata: {
        order_id,
      },
    };

    const response = await fetch('https://api.mercadopago.com/v1/payments', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
      },
      body: JSON.stringify(paymentData),
    });

    if (!response.ok) {
      const errorData = await response.json();
      console.error('❌ [PROCESS_PAYMENT] MercadoPago error:', errorData);
      throw new Error(`MercadoPago error: ${JSON.stringify(errorData)}`);
    }

    const payment = await response.json();
    console.log('✅ [PROCESS_PAYMENT] Payment processed:', payment.id, '- Status:', payment.status);

    // Actualizar payment en Supabase
    await supabase
      .from('payments')
      .update({
        mp_payment_id: payment.id,
        status: payment.status === 'approved' ? 'completed' : payment.status === 'rejected' ? 'failed' : 'pending',
      })
      .eq('order_id', order_id);

    // Si el pago fue aprobado, actualizar orden
    if (payment.status === 'approved') {
      await supabase
        .from('orders')
        .update({ payment_status: 'paid' })
        .eq('id', order_id);
    }

    return new Response(
      JSON.stringify({
        success: true,
        payment_id: payment.id,
        status: payment.status,
        status_detail: payment.status_detail,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('❌ [PROCESS_PAYMENT] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

async function handleGetPaymentStatus(body: GetPaymentStatusRequest) {
  const { payment_id } = body;

  console.log('💳 [GET_PAYMENT_STATUS] Getting payment status:', payment_id);

  try {
    const response = await fetch(`https://api.mercadopago.com/v1/payments/${payment_id}`, {
      headers: {
        Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
      },
    });

    if (!response.ok) {
      const errorData = await response.json();
      console.error('❌ [GET_PAYMENT_STATUS] MercadoPago error:', errorData);
      throw new Error(`MercadoPago error: ${JSON.stringify(errorData)}`);
    }

    const payment = await response.json();
    console.log('✅ [GET_PAYMENT_STATUS] Payment status:', payment.status);

    return new Response(
      JSON.stringify({
        success: true,
        status: payment.status,
        status_detail: payment.status_detail,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('❌ [GET_PAYMENT_STATUS] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}

async function handleRetryPayment(body: RetryPaymentRequest) {
  const { order_id, mp_payment_id } = body;

  console.log('💳 [RETRY_PAYMENT] Retrying payment...');
  console.log('   - order_id:', order_id);
  console.log('   - mp_payment_id:', mp_payment_id);

  try {
    // Obtener detalles del pago original
    const response = await fetch(`https://api.mercadopago.com/v1/payments/${mp_payment_id}`, {
      headers: {
        Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
      },
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(`MercadoPago error: ${JSON.stringify(errorData)}`);
    }

    const originalPayment = await response.json();

    // Reintentar con los mismos datos
    const retryData = {
      token: originalPayment.card?.id,
      payment_method_id: originalPayment.payment_method_id,
      transaction_amount: originalPayment.transaction_amount,
      description: originalPayment.description,
      installments: 1,
      payer: {
        email: originalPayment.payer.email,
      },
      external_reference: order_id,
    };

    const retryResponse = await fetch('https://api.mercadopago.com/v1/payments', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
      },
      body: JSON.stringify(retryData),
    });

    if (!retryResponse.ok) {
      const errorData = await retryResponse.json();
      throw new Error(`MercadoPago error: ${JSON.stringify(errorData)}`);
    }

    const newPayment = await retryResponse.json();
    console.log('✅ [RETRY_PAYMENT] Payment retried:', newPayment.id);

    // Actualizar payment en Supabase
    await supabase
      .from('payments')
      .update({
        mp_payment_id: newPayment.id,
        status: newPayment.status === 'approved' ? 'completed' : newPayment.status === 'rejected' ? 'failed' : 'pending',
      })
      .eq('order_id', order_id);

    return new Response(
      JSON.stringify({
        success: true,
        new_payment_id: newPayment.id,
        status: newPayment.status,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('❌ [RETRY_PAYMENT] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
}
