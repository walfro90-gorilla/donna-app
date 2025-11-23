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

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    console.log('🔔 [MP_WEBHOOK] Received webhook:', JSON.stringify(body));

    const { type, data } = body;

    // MercadoPago envía diferentes tipos de notificaciones
    if (type === 'payment') {
      const paymentId = data.id;
      console.log(`💳 [MP_WEBHOOK] Payment notification: ${paymentId}`);

      // Obtener detalles del pago desde MercadoPago
      const paymentResponse = await fetch(`https://api.mercadopago.com/v1/payments/${paymentId}`, {
        headers: {
          Authorization: `Bearer ${MERCADOPAGO_ACCESS_TOKEN}`,
        },
      });

      if (!paymentResponse.ok) {
        throw new Error('Failed to fetch payment details from MercadoPago');
      }

      const payment = await paymentResponse.json();
      console.log(`💳 [MP_WEBHOOK] Payment details:`, JSON.stringify(payment));

      const externalReference = payment.external_reference;
      const status = payment.status;
      const statusDetail = payment.status_detail;

      console.log(`📦 [MP_WEBHOOK] External Reference: ${externalReference}, Status: ${status}, Detail: ${statusDetail}`);

      // Buscar el payment por mp_preference_id (más confiable que external_reference)
      const preferenceId = payment.preference_id;
      
      const { data: paymentRecord, error: fetchPaymentError } = await supabase
        .from('payments')
        .select('*')
        .eq('mp_preference_id', preferenceId)
        .single();
      
      if (fetchPaymentError || !paymentRecord) {
        console.error('❌ [MP_WEBHOOK] Payment record no encontrado:', fetchPaymentError);
        throw new Error('Payment record no encontrado');
      }
      
      console.log('✅ [MP_WEBHOOK] Payment record encontrado:', paymentRecord);
      
      let orderId = paymentRecord.order_id;

      // **SI HAY order_data Y NO HAY order_id**: CREAR LA ORDEN INMEDIATAMENTE
      // (sin importar el status - la orden se crea en cuanto llega la primera notificación)
      if (!orderId && paymentRecord.order_data) {
        console.log(`📝 [MP_WEBHOOK] order_data presente con status '${status}' - CREANDO ORDEN...`);
        
        const orderData = paymentRecord.order_data;
        
        try {
          // Crear orden en Supabase (sin payment_status por ahora)
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
              status: 'pending',
              created_at: new Date().toISOString(),
            })
            .select()
            .single();
          
          if (createOrderError) {
            console.error('❌ [MP_WEBHOOK] Error al crear orden:', createOrderError);
            throw createOrderError;
          }
          
          orderId = newOrder.id;
          console.log('✅ [MP_WEBHOOK] Orden creada exitosamente:', orderId);
          
          // Crear order_items
          const items = orderData.items.map((item: any) => ({
            order_id: orderId,
            product_id: item.product_id,
            quantity: item.quantity,
            unit_price: item.unit_price,
            price_at_time_of_order: item.price_at_time_of_order,
            created_at: new Date().toISOString(),
          }));
          
          const { error: itemsError } = await supabase
            .from('order_items')
            .insert(items);
          
          if (itemsError) {
            console.error('❌ [MP_WEBHOOK] Error al crear order_items:', itemsError);
          } else {
            console.log('✅ [MP_WEBHOOK] Order items creados');
          }
          
        } catch (orderCreationError: any) {
          console.error('❌ [MP_WEBHOOK] Error fatal al crear orden:', orderCreationError);
          // Actualizar payment con error
          await supabase
            .from('payments')
            .update({
              mp_payment_id: payment.id,
              status: 'failed',
              updated_at: new Date().toISOString(),
            })
            .eq('id', paymentRecord.id);
          throw orderCreationError;
        }
      }
      
      // Actualizar payment en Supabase
      const { error: paymentUpdateError } = await supabase
        .from('payments')
        .update({
          order_id: orderId, // Ahora puede ser el recién creado
          mp_payment_id: payment.id,
          status: status === 'approved' ? 'completed' : status === 'rejected' ? 'failed' : 'pending',
          updated_at: new Date().toISOString(),
        })
        .eq('id', paymentRecord.id);

      if (paymentUpdateError) {
        console.error('❌ [MP_WEBHOOK] Error updating payment:', paymentUpdateError);
      } else {
        console.log('✅ [MP_WEBHOOK] Payment updated in Supabase');
      }

      // Si el pago fue aprobado, procesar deuda del cliente
      if (status === 'approved') {
        console.log('✅ [MP_WEBHOOK] Payment APPROVED - Processing debt if exists...');

        // IMPORTANTE: NO crear account_transactions aquí.
        // Las transacciones financieras (RESTAURANT_PAYABLE, DELIVERY_EARNING, etc.) 
        // se crean automáticamente cuando la orden cambia a status 'delivered' 
        // mediante el trigger SQL 'process_order_delivery_v3()'

        // Solo procesar deuda del cliente si existe
        const clientDebt = typeof payment.metadata?.client_debt === 'number' ? payment.metadata.client_debt : 0;
        
        if (clientDebt > 0 && orderId) {
          console.log(`💰 [MP_WEBHOOK] Client had debt: ${clientDebt} - Marking as paid...`);

          const { data: orderData, error: orderFetchError } = await supabase
            .from('orders')
            .select('user_id')
            .eq('id', orderId)
            .single();

          if (!orderFetchError && orderData) {
            const clientId = orderData.user_id;

            // Marcar deuda como pagada
            const { error: debtError } = await supabase
              .from('client_debts')
              .update({
                status: 'paid',
                paid_at: new Date().toISOString(),
                updated_at: new Date().toISOString(),
              })
              .eq('client_id', clientId)
              .eq('status', 'pending');

            if (debtError) {
              console.error('❌ [MP_WEBHOOK] Error updating debt:', debtError);
            } else {
              console.log('✅ [MP_WEBHOOK] Client debt marked as paid');
            }
          }
        } else {
          console.log('ℹ️  [MP_WEBHOOK] No client debt to process');
        }
      } else if (status === 'rejected') {
        console.log('❌ [MP_WEBHOOK] Payment REJECTED');
        
        // NOTA: payment_status='failed' se actualizará cuando se ejecute la migración
        // Por ahora, el payment record ya tiene status='failed'
      } else {
        console.log(`⏳ [MP_WEBHOOK] Payment status: ${status} - Orden creada, esperando confirmación de pago...`);
        if (orderId) {
          console.log(`📦 [MP_WEBHOOK] Order ID: ${orderId}`);
        }
      }

      return new Response(
        JSON.stringify({ success: true, message: 'Webhook processed' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Otros tipos de notificaciones (merchant_order, etc.)
    console.log(`ℹ️ [MP_WEBHOOK] Unhandled webhook type: ${type}`);

    return new Response(
      JSON.stringify({ success: true, message: 'Webhook received but not processed' }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error: any) {
    console.error('❌ [MP_WEBHOOK] Error:', error);
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
