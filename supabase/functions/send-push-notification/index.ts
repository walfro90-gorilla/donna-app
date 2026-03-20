// Edge Function: send-push-notification
// Disparada por Database Webhook cuando cambia el status de una orden.
// Envía notificaciones push via FCM y WhatsApp via Clawbot.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// ────────────────────────────────────────────
// Configuración de destinatarios por status
// ────────────────────────────────────────────
interface NotificationTarget {
  roles: ('kitchen' | 'delivery' | 'client')[]
  whatsapp: boolean
}

const STATUS_CONFIG: Record<string, NotificationTarget> = {
  pending:          { roles: ['kitchen'],            whatsapp: false },
  confirmed:        { roles: ['client'],              whatsapp: true  },
  preparing:        { roles: ['client'],              whatsapp: false },
  ready_for_pickup: { roles: ['delivery'],            whatsapp: false },
  on_the_way:       { roles: ['client'],              whatsapp: true  },
  delivered:        { roles: ['kitchen', 'client'],   whatsapp: true  },
  cancelled:        { roles: ['kitchen', 'delivery', 'client'], whatsapp: true },
  not_delivered:    { roles: ['kitchen', 'client'],   whatsapp: true  },
}

const NOTIFICATION_MESSAGES: Record<string, { title: string; body: string }> = {
  pending:          { title: '🔔 Nueva orden',        body: 'Tienes una nueva orden esperando confirmación.' },
  confirmed:        { title: '✅ Orden confirmada',    body: 'Tu pedido fue confirmado. ¡Ya lo están preparando!' },
  preparing:        { title: '👨‍🍳 En preparación',     body: 'Tu pedido está siendo preparado.' },
  ready_for_pickup: { title: '📦 Listo para recoger',  body: 'La orden está lista para ser recogida.' },
  on_the_way:       { title: '🛵 En camino',           body: 'Tu repartidor ya va en camino con tu pedido.' },
  delivered:        { title: '✅ Entregado',           body: '¡Tu pedido fue entregado! Buen provecho.' },
  cancelled:        { title: '❌ Orden cancelada',     body: 'La orden fue cancelada.' },
  not_delivered:    { title: '⚠️ No entregado',        body: 'Hubo un problema con la entrega de tu pedido.' },
}

const WHATSAPP_MESSAGES: Record<string, string> = {
  confirmed:     '✅ Tu pedido fue confirmado. Pronto lo estarán preparando.',
  on_the_way:    '🛵 Tu repartidor ya va en camino con tu pedido.',
  delivered:     '✅ ¡Tu pedido fue entregado! Buen provecho 🍽️',
  cancelled:     '❌ Tu pedido fue cancelado. Contáctanos si tienes dudas.',
  not_delivered: '⚠️ Hubo un problema con la entrega. Nos pondremos en contacto contigo.',
}

// ────────────────────────────────────────────
// Handler principal
// ────────────────────────────────────────────
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const body = await req.json()
    console.log('📨 [PUSH] Webhook received:', JSON.stringify(body))

    // El webhook de Supabase envía { type, table, record, old_record }
    const record = body.record ?? body
    const oldRecord = body.old_record ?? {}

    const orderId: string = record.id?.toString()
    const newStatus: string = record.status
    const oldStatus: string = oldRecord.status

    // Solo procesar si el status cambió
    if (!newStatus || newStatus === oldStatus) {
      return new Response(JSON.stringify({ skipped: true, reason: 'status unchanged' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const config = STATUS_CONFIG[newStatus]
    if (!config) {
      return new Response(JSON.stringify({ skipped: true, reason: 'no config for status' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Inicializar cliente Supabase con service role
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Obtener datos de la orden con joins necesarios
    const { data: order, error: orderError } = await supabase
      .from('orders')
      .select('id, user_id, restaurant_id, delivery_agent_id, users!orders_user_id_fkey(phone)')
      .eq('id', orderId)
      .single()

    if (orderError || !order) {
      console.error('❌ [PUSH] Error fetching order:', orderError)
      return new Response(JSON.stringify({ error: 'order not found' }), { status: 404 })
    }

    // Obtener restaurante para encontrar el user de kitchen
    const { data: restaurant } = await supabase
      .from('restaurants')
      .select('user_id')
      .eq('id', order.restaurant_id)
      .single()

    // Construir lista de user_ids destino
    const targetUserIds: string[] = []

    if (config.roles.includes('kitchen') && restaurant?.user_id) {
      targetUserIds.push(restaurant.user_id)
    }
    if (config.roles.includes('client') && order.user_id) {
      targetUserIds.push(order.user_id)
    }
    if (config.roles.includes('delivery') && order.delivery_agent_id) {
      targetUserIds.push(order.delivery_agent_id)
    }

    console.log(`📋 [PUSH] Targets for status "${newStatus}":`, targetUserIds)

    if (targetUserIds.length === 0) {
      return new Response(JSON.stringify({ skipped: true, reason: 'no targets' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Obtener tokens de dispositivos
    const { data: tokens } = await supabase
      .from('device_tokens')
      .select('token, platform')
      .in('user_id', targetUserIds)

    const pushResults: unknown[] = []
    const msgConfig = NOTIFICATION_MESSAGES[newStatus]

    console.log(`📊 [PUSH] Tokens encontrados: ${tokens?.length ?? 0}`)

    if (!msgConfig) {
      console.warn(`⚠️ [PUSH] No hay mensaje configurado para status: ${newStatus}`)
    }

    // Verificar FCM_SERVICE_ACCOUNT_JSON
    const hasFcmConfig = !!Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
    console.log(`🔑 [PUSH] FCM_SERVICE_ACCOUNT_JSON presente: ${hasFcmConfig}`)

    if (tokens && tokens.length > 0 && msgConfig) {
      // Enviar FCM para cada token
      for (const { token, platform } of tokens) {
        console.log(`📤 [PUSH] Enviando a plataforma: ${platform}, token: ${token.substring(0, 20)}...`)
        try {
          const result = await sendFcmNotification(token, platform, msgConfig.title, msgConfig.body, orderId)
          console.log(`📬 [PUSH] Resultado FCM:`, JSON.stringify(result))
          pushResults.push(result)
        } catch (e) {
          console.warn('⚠️ [PUSH] FCM error for token:', e)
        }
      }
    } else {
      console.log(`⏭️ [PUSH] Saltando FCM — tokens: ${tokens?.length ?? 0}, msgConfig: ${!!msgConfig}`)
    }

    // WhatsApp via Clawbot
    let waResult = null
    if (config.whatsapp && WHATSAPP_MESSAGES[newStatus]) {
      const clientPhone = (order as { users?: { phone?: string } }).users?.phone
      if (clientPhone) {
        waResult = await sendWhatsAppNotification(clientPhone, WHATSAPP_MESSAGES[newStatus])
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        status: newStatus,
        tokens_notified: tokens?.length ?? 0,
        push_results: pushResults,
        whatsapp: waResult,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )

  } catch (error) {
    console.error('❌ [PUSH] Unhandled error:', error)
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

// ────────────────────────────────────────────
// FCM HTTP v1 — usando OAuth2 service account
// ────────────────────────────────────────────
async function sendFcmNotification(
  token: string,
  platform: string,
  title: string,
  body: string,
  orderId: string,
) {
  const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON')
  if (!serviceAccountJson) {
    console.warn('⚠️ [PUSH] FCM_SERVICE_ACCOUNT_JSON not set — skipping FCM')
    return { skipped: true }
  }

  const serviceAccount = JSON.parse(serviceAccountJson)
  const accessToken = await getGoogleAccessToken(serviceAccount)
  const projectId = serviceAccount.project_id

  const message: Record<string, unknown> = {
    token,
    notification: { title, body },
    data: { order_id: orderId, status: 'push' },
  }

  if (platform === 'android') {
    message.android = {
      priority: 'high',
      notification: { channel_id: 'doa_orders', sound: 'default' },
    }
  } else if (platform === 'web') {
    message.webpush = {
      headers: { Urgency: 'high' },
      notification: { icon: '/icons/Icon-192.png' },
    }
  }

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ message }),
    },
  )

  if (!response.ok) {
    const errText = await response.text()
    console.error('❌ [FCM] Send error:', errText)
    return { error: errText }
  }

  const result = await response.json()
  console.log('✅ [FCM] Sent:', result.name)
  return { sent: true, name: result.name }
}

// Genera access token OAuth2 para FCM HTTP v1
async function getGoogleAccessToken(serviceAccount: {
  client_email: string
  private_key: string
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  // Encode JWT header + payload
  const header = { alg: 'RS256', typ: 'JWT' }
  const encodedHeader = btoa(JSON.stringify(header)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const encodedPayload = btoa(JSON.stringify(payload)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')
  const unsignedToken = `${encodedHeader}.${encodedPayload}`

  // Sign with RS256
  const privateKeyPem = serviceAccount.private_key
  const pemContents = privateKeyPem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\n/g, '')

  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0))
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedToken),
  )

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')

  const jwt = `${unsignedToken}.${encodedSignature}`

  // Exchange JWT for access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const tokenData = await tokenResponse.json()
  return tokenData.access_token
}

// ────────────────────────────────────────────
// Clawbot — WhatsApp via UpCloud server
// ────────────────────────────────────────────
async function sendWhatsAppNotification(phone: string, message: string) {
  const webhookUrl = Deno.env.get('CLAWBOT_WEBHOOK_URL')
  const secret = Deno.env.get('CLAWBOT_SECRET')

  if (!webhookUrl) {
    console.warn('⚠️ [WA] CLAWBOT_WEBHOOK_URL not set — skipping WhatsApp')
    return { skipped: true }
  }

  try {
    const response = await fetch(webhookUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(secret ? { 'x-clawbot-secret': secret } : {}),
      },
      body: JSON.stringify({ phone, message }),
    })

    if (!response.ok) {
      const errText = await response.text()
      console.error('❌ [WA] Clawbot error:', errText)
      return { error: errText }
    }

    console.log('✅ [WA] WhatsApp sent to', phone)
    return { sent: true, phone }
  } catch (e) {
    console.error('❌ [WA] Fetch error:', e)
    return { error: String(e) }
  }
}
