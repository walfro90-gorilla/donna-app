// Edge Function: analyze-menu-image
// Recibe una imagen de menú en base64 y usa GPT-4o para extraer los platillos con sus precios.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface AnalyzeMenuRequest {
  image_base64: string
  media_type?: string // 'image/jpeg' | 'image/png' | 'image/webp'
}

interface DetectedProduct {
  name: string
  description: string
  price: number
  type: 'principal' | 'bebida' | 'postre' | 'entrada'
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { image_base64, media_type = 'image/jpeg' }: AnalyzeMenuRequest = await req.json()

    if (!image_base64) {
      return new Response(
        JSON.stringify({ success: false, error: 'image_base64 es requerido' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const openaiApiKey = Deno.env.get('OPENAI_API_KEY')
    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({ success: false, error: 'OPENAI_API_KEY no configurada' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const prompt = `Analiza esta imagen de menú de restaurante. Extrae TODOS los platillos y productos que encuentres.
Para cada uno retorna un objeto JSON con estos campos exactos:
- name: nombre del platillo (string)
- description: descripción breve si aparece en el menú, si no deja "" (string)
- price: precio como número decimal sin símbolo de moneda, 0 si no aparece (number)
- type: clasifica como uno de estos valores exactos: "principal" (comida principal), "bebida" (bebidas/jugos/refrescos), "postre" (dulces/pasteles/helados), "entrada" (aperitivos/sopas/ensaladas)

Responde ÚNICAMENTE con un JSON array válido. Sin texto adicional, sin markdown, sin bloques de código.
Ejemplo de formato esperado: [{"name":"Tacos de Carne","description":"3 tacos con carne asada y cebolla","price":85.0,"type":"principal"},{"name":"Agua de Jamaica","description":"","price":25.0,"type":"bebida"}]`

    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'user',
            content: [
              { type: 'text', text: prompt },
              {
                type: 'image_url',
                image_url: {
                  url: `data:${media_type};base64,${image_base64}`,
                  detail: 'high',
                },
              },
            ],
          },
        ],
        max_tokens: 2000,
      }),
    })

    if (!openaiResponse.ok) {
      const errorBody = await openaiResponse.text()
      return new Response(
        JSON.stringify({ success: false, error: `OpenAI error: ${openaiResponse.status} - ${errorBody}` }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const openaiData = await openaiResponse.json()
    const rawContent: string = openaiData.choices?.[0]?.message?.content ?? '[]'

    // Limpiar la respuesta por si GPT incluye markdown o texto extra
    const jsonStart = rawContent.indexOf('[')
    const jsonEnd = rawContent.lastIndexOf(']')
    if (jsonStart === -1 || jsonEnd === -1) {
      return new Response(
        JSON.stringify({ success: false, error: 'La IA no pudo detectar platillos en esta imagen' }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const cleanJson = rawContent.slice(jsonStart, jsonEnd + 1)
    const products: DetectedProduct[] = JSON.parse(cleanJson)

    return new Response(
      JSON.stringify({ success: true, products }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: `Error interno: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
