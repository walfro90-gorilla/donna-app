// Edge Function: analyze-menu-image
// Recibe una imagen de menú en base64 y usa GPT-4o para extraer platillos,
// clasificarlos por tipo y detectar grupos de modificadores (extras, término, tamaño, etc.)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface AnalyzeMenuRequest {
  image_base64: string
  media_type?: string
}

interface DetectedModifier {
  name: string
  price_delta: number
}

interface DetectedModifierGroup {
  name: string
  selection_type: 'single' | 'multiple'
  min_selections: number
  max_selections: number
  is_required: boolean
  modifiers: DetectedModifier[]
}

interface DetectedProduct {
  name: string
  description: string
  price: number
  type: 'principal' | 'bebida' | 'postre' | 'entrada' | 'combo'
  has_modifiers: boolean
  modifier_groups: DetectedModifierGroup[]
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

    const prompt = `Analiza esta imagen de menú de restaurante. Extrae TODOS los platillos, bebidas, postres y combos que veas.

Para cada producto retorna un objeto JSON con estos campos exactos:
- name: nombre del platillo (string)
- description: descripción breve si aparece en el menú, si no "" (string)
- price: precio como número decimal sin símbolo de moneda, 0 si no aparece (number)
- type: clasifica con uno de estos valores exactos:
    "principal" → tacos, tortas, burritos, pizza, hamburguesas, quesadillas, enchiladas, platillos de carne/pollo/pescado
    "bebida"    → agua, refresco, cerveza, café, té, jugo, licuado, smoothie, atole
    "postre"    → pastel, flan, helado, brownie, gelatina, churro, nieve, pan dulce
    "entrada"   → sopa, ensalada, ceviche, tostada independiente, guarnición, botana
    "combo"     → menciona explícitamente 2+ ítems incluidos (ej: hamburguesa + papas + refresco)
- has_modifiers: true si el platillo típicamente lleva opciones/extras que el cliente puede elegir (boolean)
- modifier_groups: array de grupos de opciones. Siempre [] si has_modifiers es false.

Reglas para detectar modifier_groups:
1. Proteínas variables (pollo/res/cerdo/camarón en el mismo platillo) → grupo "Proteína" (selection_type:"single", is_required:true, min_selections:1, max_selections:1)
2. Ingredientes extra opcionales → grupo "Extras" (selection_type:"multiple", is_required:false, min_selections:0, max_selections:5). Incluye extras típicos del platillo (tocino, queso extra, aguacate, jalapeño, champiñones, etc.)
3. Término de cocción (para carnes rojas/hamburguesas) → grupo "Término" (selection_type:"single", is_required:true, min_selections:1, max_selections:1). Modifiers: "Bien cocida"(0), "Tres cuartos"(0), "Medio"(0), "Poco cocida"(0)
4. Tamaños disponibles → grupo "Tamaño" (selection_type:"single", is_required:true, min_selections:1, max_selections:1)
5. Salsas opcionales → grupo "Salsa" (selection_type:"multiple", is_required:false, min_selections:0, max_selections:3)

Reglas para price_delta de modifiers:
- Proteínas y tamaños base: 0. Premium: +20 a +40
- Ingredientes extra: entre 10 y 30 según ingrediente
- Término, salsa base: 0

Casos que NO llevan modifier_groups (has_modifiers:false):
- Bebidas simples sin opción de tamaño ni temperatura
- Postres simples
- Guarniciones o entradas simples

Responde ÚNICAMENTE con JSON válido con esta estructura (sin texto adicional, sin markdown):
{"success":true,"products":[{"name":"Hamburguesa Clásica","description":"Carne de res, lechuga, tomate","price":120.0,"type":"principal","has_modifiers":true,"modifier_groups":[{"name":"Extras","selection_type":"multiple","min_selections":0,"max_selections":5,"is_required":false,"modifiers":[{"name":"Extra tocino","price_delta":25},{"name":"Extra queso","price_delta":15},{"name":"Aguacate","price_delta":20}]},{"name":"Término","selection_type":"single","min_selections":1,"max_selections":1,"is_required":true,"modifiers":[{"name":"Bien cocida","price_delta":0},{"name":"Tres cuartos","price_delta":0},{"name":"Medio","price_delta":0}]}]},{"name":"Agua de Jamaica","description":"","price":25.0,"type":"bebida","has_modifiers":false,"modifier_groups":[]}]}`

    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${openaiApiKey}`,
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
        max_tokens: 4000,
        response_format: { type: 'json_object' },
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
    const rawContent: string = openaiData.choices?.[0]?.message?.content ?? '{}'

    let parsed: { success?: boolean; products?: DetectedProduct[] }
    try {
      parsed = JSON.parse(rawContent)
    } catch {
      return new Response(
        JSON.stringify({ success: false, error: 'La IA no pudo detectar platillos en esta imagen' }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const products = (parsed.products ?? []).filter((p: DetectedProduct) => p.name?.trim())
    if (products.length === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'No se detectaron platillos. Intenta con una foto más clara.' }),
        { status: 422, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

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
