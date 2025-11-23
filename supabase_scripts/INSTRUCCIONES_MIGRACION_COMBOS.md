# 🚀 Instrucciones de Migración: Sistema de Combos con Cache Denormalizado

## 📋 Resumen de la Estrategia

Mantener `products.contains` como **cache denormalizado** sincronizado automáticamente desde `product_combo_items`:
- ✅ **Fuente de verdad**: `product_combo_items` (tabla normalizada)
- ✅ **Cache para lecturas rápidas**: `products.contains` (campo JSONB denormalizado)
- ✅ **Sincronización automática**: Trigger `fn_sync_combo_contains()` mantiene ambos en sync
- ✅ **Validaciones diferidas**: Trigger `fn_validate_combo_deferred()` valida al final de transacción
- ✅ **Upsert atómico**: RPC `upsert_combo_atomic()` maneja todo en una sola transacción

---

## ⚠️ IMPORTANTE: Antes de Empezar

1. **Haz un backup de tu base de datos**
   ```bash
   # Desde el dashboard de Supabase: Settings > Database > Backups
   ```

2. **Verifica que tienes permisos de administrador** en tu proyecto de Supabase

3. **Ejecuta estos scripts en el SQL Editor de Supabase**, NO en tu aplicación

4. **Ejecuta en ORDEN**, uno por uno, verificando que cada uno complete sin errores

---

## 📝 Orden de Ejecución

### **PASO 1: Eliminar trigger antiguo**
**Archivo**: `2025-11-12_10_DROP_old_trigger.sql`

**Qué hace**: Elimina el trigger antiguo `fn_validate_combo_items_and_bounds()` que causaba fallos en inserts batch.

**Cómo ejecutar**:
1. Abre el SQL Editor de Supabase
2. Copia y pega el contenido completo de `2025-11-12_10_DROP_old_trigger.sql`
3. Haz clic en "Run" o presiona `Ctrl+Enter` (Windows/Linux) / `Cmd+Enter` (Mac)
4. ✅ **Debe completar sin errores** (verás un NOTICE confirmando la eliminación)

**Riesgo**: 🟢 Bajo - Solo elimina trigger problemático

---

### **PASO 2: Crear trigger de sincronización automática**
**Archivo**: `2025-11-12_08_SYNC_contains_trigger.sql`

**Qué hace**: Crea el trigger `fn_sync_combo_contains()` que actualiza automáticamente `products.contains` cada vez que se modifica `product_combo_items`.

**Cómo ejecutar**:
1. Copia y pega el contenido completo de `2025-11-12_08_SYNC_contains_trigger.sql`
2. Haz clic en "Run"
3. ✅ **Debe completar sin errores**

**Riesgo**: 🟢 Bajo - Solo crea trigger, no modifica datos

---

### **PASO 3: Crear trigger de validación diferida**
**Archivo**: `2025-11-12_09_VALIDATE_combo_deferred.sql`

**Qué hace**: Crea el trigger `fn_validate_combo_deferred()` que valida las restricciones de combos **al final de la transacción** (no en cada INSERT individual).

**Validaciones que aplica**:
- ✅ Total de unidades entre 2 y 9
- ✅ No puede contener otros combos (recursión prohibida)
- ✅ `products.contains` sincronizado con `product_combo_items`

**Cómo ejecutar**:
1. Copia y pega el contenido completo de `2025-11-12_09_VALIDATE_combo_deferred.sql`
2. Haz clic en "Run"
3. ✅ **Debe completar sin errores**

**Riesgo**: 🟢 Bajo - Solo crea trigger de validación, no modifica datos

---

### **PASO 4: Actualizar RPC upsert_combo_atomic**
**Archivo**: `2025-11-12_11_RPC_upsert_combo_atomic_v2.sql`

**Qué hace**: Actualiza la función RPC `upsert_combo_atomic()` para que:
- Ya NO requiere que envíes `contains` (se maneja automáticamente)
- Upserta producto + combo + items en una sola transacción atómica
- Los triggers se encargan de sincronizar y validar

**Cómo ejecutar**:
1. Copia y pega el contenido completo de `2025-11-12_11_RPC_upsert_combo_atomic_v2.sql`
2. Haz clic en "Run"
3. ✅ **Debe completar sin errores**

**Riesgo**: 🟢 Bajo - Solo actualiza función, no modifica datos

---

### **PASO 5: Sincronizar combos existentes (BACKFILL)**
**Archivo**: `2025-11-12_12_BACKFILL_sync_contains_existing_combos.sql`

**Qué hace**: Reconstruye `products.contains` para todos los combos existentes desde `product_combo_items`.

**⚠️ IMPORTANTE**: 
- Este script **SÍ modifica datos** (actualiza `products.contains`)
- Es **IDEMPOTENTE** (puedes ejecutarlo múltiples veces sin problema)
- Muestra un log detallado de cada combo actualizado

**Cómo ejecutar**:
1. Copia y pega el contenido completo de `2025-11-12_12_BACKFILL_sync_contains_existing_combos.sql`
2. Haz clic en "Run"
3. ✅ **Revisa el log en la consola**:
   - Debe mostrar: `=== INICIO: Sincronización de products.contains para combos existentes ===`
   - Para cada combo: `✓ Combo "..." (...) sincronizado. Antes: ..., Ahora: ...`
   - Al final: `=== FIN: X combos sincronizados exitosamente ===`

**Riesgo**: 🟡 Medio - Modifica datos, pero es idempotente

---

## ✅ Verificación Post-Migración

Después de ejecutar TODOS los scripts, verifica que todo funcione:

### **1. Verifica que los triggers existen**
```sql
SELECT 
  trigger_name, 
  event_object_table, 
  action_timing, 
  event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table = 'product_combo_items'
ORDER BY trigger_name;
```

**Debes ver**:
- `trg_sync_combo_contains_after` (AFTER INSERT OR UPDATE OR DELETE)
- `trg_validate_combo_deferred` (AFTER INSERT OR UPDATE OR DELETE, DEFERRABLE)

### **2. Verifica que la RPC existe**
```sql
SELECT 
  routine_name, 
  routine_type,
  data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'upsert_combo_atomic';
```

**Debes ver**: `upsert_combo_atomic` con tipo `FUNCTION` y return type `jsonb`

### **3. Verifica un combo existente**
```sql
SELECT 
  p.id,
  p.name,
  p.type,
  p.contains,
  jsonb_agg(
    jsonb_build_object(
      'product_id', pci.product_id::TEXT,
      'quantity', pci.quantity
    )
  ) AS contains_from_items
FROM public.products p
INNER JOIN public.product_combos pc ON pc.product_id = p.id
INNER JOIN public.product_combo_items pci ON pci.combo_id = pc.id
WHERE p.type = 'combo'::product_type_enum
GROUP BY p.id
LIMIT 1;
```

**Verifica que**: `contains` sea igual a `contains_from_items`

---

## 🧪 Prueba de Funcionalidad

### **Crear un nuevo combo desde tu app**

Desde tu Flutter app, intenta crear un nuevo combo:
1. Abre el formulario de creación de combos
2. Agrega 2-3 productos con cantidades
3. Guarda el combo
4. ✅ **Debe guardar sin errores**

### **Verificar en la base de datos**
```sql
SELECT 
  p.name,
  p.type,
  p.contains,
  p.is_available
FROM public.products p
WHERE p.type = 'combo'::product_type_enum
ORDER BY p.created_at DESC
LIMIT 1;
```

**Verifica que**:
- `type` = `combo`
- `contains` tiene un array JSON con los productos agregados
- `is_available` = `true`

---

## 🚨 Troubleshooting

### **Error: "cannot use subquery in check constraint"**
- ✅ **Solucionado**: Ya no usamos CHECK constraints con subqueries. Ahora usamos triggers.

### **Error: "column reference 'combo_id' is ambiguous"**
- ✅ **Solucionado**: Todas las referencias están cualificadas con alias de tabla.

### **Error: "permission denied: RI_ConstraintTrigger_c_XXXXXX is a system trigger"**
- ✅ **Solucionado**: Ya no intentamos deshabilitar triggers del sistema.

### **Error: "Un combo debe tener entre 2 y 9 unidades en total (actual=1)"**
- ✅ **Solucionado**: El trigger de validación ahora es DEFERRED, se ejecuta al final de la transacción.

### **Error: "products.contains no puede ser NULL/vacío"**
- ✅ **Solucionado**: El trigger `fn_sync_combo_contains()` sincroniza automáticamente `contains` desde `product_combo_items`.

### **Si algo sale mal**:
1. **NO entres en pánico**
2. **Restaura el backup** de tu base de datos
3. **Revisa el log de errores** en el SQL Editor
4. **Contacta con soporte** compartiendo el error exacto

---

## 📊 Diagrama de Flujo

```
Usuario crea combo en Flutter App
          ↓
Llama a RPC: upsert_combo_atomic()
          ↓
┌─────────────────────────────────────┐
│ TRANSACCIÓN ATÓMICA:                │
│                                     │
│ 1. Upsert products (type='combo')  │
│ 2. Upsert product_combos           │
│ 3. DELETE old items                │
│ 4. INSERT new items                │
│    → Trigger: fn_sync_combo_contains() │
│      actualiza products.contains   │
│    → Trigger: fn_validate_combo_deferred() │
│      valida restricciones (DEFERRED) │
│                                     │
│ Si todo OK: COMMIT                  │
│ Si error: ROLLBACK                  │
└─────────────────────────────────────┘
          ↓
Combo guardado ✅
```

---

## 📚 Referencias

- **Triggers en PostgreSQL**: https://www.postgresql.org/docs/current/trigger-definition.html
- **Constraint Triggers**: https://www.postgresql.org/docs/current/sql-createtrigger.html
- **JSONB en PostgreSQL**: https://www.postgresql.org/docs/current/datatype-json.html
- **RPC en Supabase**: https://supabase.com/docs/guides/database/functions

---

## ✅ Checklist Final

Antes de marcar como completado:

- [ ] **PASO 1**: Script `2025-11-12_10_DROP_old_trigger.sql` ejecutado ✅
- [ ] **PASO 2**: Script `2025-11-12_08_SYNC_contains_trigger.sql` ejecutado ✅
- [ ] **PASO 3**: Script `2025-11-12_09_VALIDATE_combo_deferred.sql` ejecutado ✅
- [ ] **PASO 4**: Script `2025-11-12_11_RPC_upsert_combo_atomic_v2.sql` ejecutado ✅
- [ ] **PASO 5**: Script `2025-11-12_12_BACKFILL_sync_contains_existing_combos.sql` ejecutado ✅
- [ ] Verificación post-migración completada ✅
- [ ] Prueba de funcionalidad desde Flutter app ✅
- [ ] Combo creado exitosamente sin errores ✅

---

**🎉 ¡Migración completada! Ahora tu sistema de combos funciona con cache denormalizado sincronizado automáticamente.**
