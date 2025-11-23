#!/bin/bash
# Script para desplegar la Edge Function maps-proxy a Supabase

echo "🚀 Desplegando Edge Function: maps-proxy"
echo "=========================================="

# Verificar que Supabase CLI esté instalado
if ! command -v supabase &> /dev/null; then
    echo "❌ ERROR: Supabase CLI no está instalado."
    echo "   Instala con: npm install -g supabase"
    exit 1
fi

# Verificar que estemos logueados
if ! supabase projects list &> /dev/null; then
    echo "❌ ERROR: No estás logueado en Supabase CLI."
    echo "   Ejecuta: supabase login"
    exit 1
fi

# Desplegar la función
echo ""
echo "📦 Desplegando función..."
cd "$(dirname "$0")/.." || exit
supabase functions deploy maps-proxy --project-ref YOUR_PROJECT_REF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Edge Function 'maps-proxy' desplegada exitosamente!"
    echo ""
    echo "⚠️  IMPORTANTE: Verifica que el secreto GOOGLE_MAPS_API_KEY esté configurado:"
    echo "   1. Ve a Supabase Console → Edge Functions → Secrets"
    echo "   2. Asegúrate de que existe: GOOGLE_MAPS_API_KEY = tu_api_key"
    echo ""
    echo "🧪 Prueba la función con:"
    echo "   curl -X POST https://YOUR_PROJECT_REF.supabase.co/functions/v1/maps-proxy \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -H 'Authorization: Bearer YOUR_ANON_KEY' \\"
    echo "     -d '{\"action\":\"autocomplete\",\"input\":\"Oaxaca\"}'"
else
    echo ""
    echo "❌ ERROR al desplegar la función."
    echo "   Verifica los logs arriba para más detalles."
    exit 1
fi
