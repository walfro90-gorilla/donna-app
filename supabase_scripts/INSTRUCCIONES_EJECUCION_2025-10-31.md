# 🎯 INSTRUCCIONES PARA EJECUTAR EL FIX DEFINITIVO

## Problema Diagnosticado
La comisión sigue siendo 20% fijo porque hay **múltiples funciones conflictivas** coexistiendo:
- `process_order_payment()` - usa 15% fijo
- `process_order_payment_on_delivery()` - intenta usar `commission_bps` pero con columnas incorrectas
- `process_order_payment_v2()` - usa 20% fijo hardcodeado

Además, ninguna está escribiendo `description` ni `metadata` correctamente.

## Solución Implementada
Script: `2025-10-31_ULTIMATE_fix_commission_dynamic_atomic.sql`

Este script:
1. ✅ Elimina TODAS las funciones y triggers legacy de forma exhaustiva
2. ✅ Verifica y asegura que `restaurants.commission_bps` existe con default 1500 (15%)
3. ✅ Crea UNA SOLA función: `process_order_payment_final()`
4. ✅ Crea UN SOLO trigger: `trigger_process_order_payment_final`
5. ✅ Lee `commission_bps` dinámicamente de la tabla restaurants
6. ✅ Escribe `description` Y `metadata` en TODAS las transacciones
7. ✅ Usa tipos correctos según DATABASE_SCHEMA.sql
8. ✅ Mantiene Balance Cero para flujos cash y card
9. ✅ Es idempotente (no duplica transacciones)
10. ✅ Incluye verificación post-instalación automática

## 📋 Pasos para Ejecutar

### 1. Abrir Supabase SQL Editor
Ve a tu proyecto en Supabase Console:
```
https://supabase.com/dashboard/project/[tu-project-id]/sql/new
```

### 2. Copiar el Contenido del Script
Copia TODO el contenido del archivo:
```
supabase_scripts/2025-10-31_ULTIMATE_fix_commission_dynamic_atomic.sql
```

### 3. Ejecutar el Script
1. Pega el contenido completo en el SQL Editor
2. Haz clic en el botón "Run" (▶️)
3. Espera a que termine la ejecución

### 4. Verificar la Salida
Al final del script deberías ver mensajes similares a:
```
✓ Todos los triggers legacy eliminados
✓ Columna commission_bps ya existe, default actualizado
✓ Constraint de validación ya existe
=================================================================
✓ INSTALACIÓN COMPLETADA
=================================================================
Triggers activos en orders (payment): 1
Funciones de payment activas: 1
✓✓ ÉXITO: Solo hay 1 trigger y 1 función (configuración correcta)
=================================================================
Función activa: process_order_payment_final()
Trigger activo: trigger_process_order_payment_final
Comportamiento:
  - Lee restaurants.commission_bps dinámicamente
  - Default: 1500 bps (15%)
  - Rango válido: 0..3000 bps (0%..30%)
  - Escribe description y metadata en TODAS las transacciones
  - Mantiene Balance Cero para cash y card
  - Idempotente: no duplica si se re-entrega una orden
=================================================================
```

### 5. Verificar que el Trigger Está Activo
El script también mostrará una tabla con el trigger activo:
```
trigger_name                          | event_manipulation | action_timing | action_statement
--------------------------------------+--------------------+---------------+------------------
trigger_process_order_payment_final   | UPDATE             | AFTER         | EXECUTE FUNCTION...
```

## 🧪 Prueba Posterior

### 1. Verificar el commission_bps de tu Restaurante
```sql
SELECT id, name, commission_bps 
FROM public.restaurants 
WHERE id = '[tu-restaurant-id]';
```

Si quieres cambiar el porcentaje de comisión (por ejemplo, a 15% = 1500 bps):
```sql
UPDATE public.restaurants 
SET commission_bps = 1500 
WHERE id = '[tu-restaurant-id]';
```

### 2. Hacer una Orden de Prueba
1. Crea una orden nueva desde tu app
2. Asígnala a un repartidor
3. Marca la orden como "delivered"
4. Verifica las transacciones creadas:

```sql
SELECT 
  at.type,
  at.amount,
  at.description,
  at.metadata->>'commission_bps' as commission_bps,
  at.metadata->>'commission_rate' as commission_rate
FROM public.account_transactions at
WHERE at.order_id = '[order-id-de-prueba]'
ORDER BY at.created_at;
```

**Resultados esperados:**
- `description` debe contener el porcentaje dinámico (ej: "Comisión 15% pedido #...")
- `metadata` debe tener campos como `commission_bps`, `commission_rate`, `subtotal`
- El monto de `PLATFORM_COMMISSION` debe ser exactamente `subtotal × (commission_bps/10000)`
- Para commission_bps=1500 y subtotal=175, debe ser: 175 × 0.15 = 26.25 (NO 35.00)

### 3. Verificar Balance Cero
```sql
SELECT SUM(balance) as total_balance 
FROM public.accounts;
```
**Resultado esperado:** `0.00` (o muy cercano a cero, considerando redondeos)

## ⚠️ Notas Importantes

1. **Idempotencia**: Si ya tienes órdenes marcadas como "delivered", el script NO las reprocesará. Solo afectará nuevas órdenes que se marquen como "delivered" después de ejecutar el script.

2. **Transacciones Legacy**: Las transacciones antiguas con 20% fijo seguirán en la base de datos. Si quieres limpiarlas, tendrías que:
   - Identificarlas manualmente
   - Eliminarlas
   - Recalcular balances
   **NO RECOMENDADO** a menos que sea absolutamente necesario.

3. **Cambio de commission_bps**: Puedes actualizar `commission_bps` en cualquier momento para cualquier restaurante. Los cambios se aplicarán a partir de la siguiente orden que se marque como "delivered".

4. **Rango válido**: El script fuerza el rango 0..3000 bps (0%..30%). Si intentas poner un valor fuera de ese rango, Supabase rechazará el UPDATE.

## 🔧 Troubleshooting

### Si el script falla con "function does not exist"
No hay problema, significa que ya limpiamos las funciones legacy. Continúa con el resto del script.

### Si ves "trigger already exists"
El script maneja esto automáticamente con `DROP TRIGGER IF EXISTS`. Simplemente vuelve a ejecutar el script completo.

### Si después de ejecutar sigues viendo comisión al 20%
1. Verifica que el trigger está activo:
   ```sql
   SELECT trigger_name, event_manipulation, action_statement
   FROM information_schema.triggers
   WHERE event_object_table = 'orders' AND trigger_name ILIKE '%payment%';
   ```
   Debes ver SOLO `trigger_process_order_payment_final`.

2. Verifica que la función existe:
   ```sql
   SELECT proname FROM pg_proc p
   JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public' AND proname ILIKE '%process%order%payment%';
   ```
   Debes ver SOLO `process_order_payment_final` y opcionalmente `_format_percentage`.

3. Si ves múltiples triggers o funciones, ejecútalos manualmente:
   ```sql
   DROP TRIGGER IF EXISTS trigger_process_payment_on_delivery ON public.orders CASCADE;
   DROP TRIGGER IF EXISTS trigger_order_financial_completion ON public.orders CASCADE;
   DROP TRIGGER IF EXISTS trigger_process_order_payment ON public.orders CASCADE;
   DROP FUNCTION IF EXISTS public.process_order_payment() CASCADE;
   DROP FUNCTION IF EXISTS public.process_order_payment_on_delivery() CASCADE;
   DROP FUNCTION IF EXISTS public.process_order_payment_v2() CASCADE;
   ```
   Y luego vuelve a ejecutar el script completo.

## 📞 Soporte
Si después de seguir todos los pasos el problema persiste, proporciona:
1. El output completo del script al ejecutar
2. El resultado de la query de verificación de triggers/funciones
3. Un pantallazo de las transacciones de una orden de prueba nueva

---

**¡El script está listo para ejecutar!** 🚀
