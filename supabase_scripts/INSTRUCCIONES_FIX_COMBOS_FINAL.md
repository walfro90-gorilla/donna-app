# ✅ FIX DEFINITIVO: Combos - products.contains automático

## 🔍 Análisis del Problema

**Raíz del error:**
El cliente Flutter enviaba `product['contains'] = []` (vacío o null) dentro del parámetro `product`, y la RPC lo validaba **antes** de poder rellenarlo desde `items`, causando el rechazo:
```
❌ products.contains no puede ser NULL/vacío y debe ser un arreglo JSON cuando type = combo
```

**Conflicto:**
1. Cliente calculaba `contains` desde `_selectedItems` y lo incluía en `productPayload`
2. Servicio `upsertCombo` lo volvía a limpiar/filtrar (línea 1108)
3. Si el filtro resultaba vacío, `product['contains'] = []`
4. RPC recibía `contains` vacío y rechazaba en validación línea 42

---

## ✅ Solución Implementada

### Estrategia:
- **La RPC es la única fuente de verdad** para calcular `contains`
- El cliente **NO debe enviar** `contains` dentro de `product`
- La RPC calcula `contains` automáticamente desde el parámetro `items`
- Los triggers AFTER sincronizan `contains` con `product_combo_items`

---

## 📋 Instrucciones Paso a Paso

### ✅ **PASO 1: Ejecutar script SQL en Supabase**

**Archivo:** `2025-11-12_15_FIX_remove_contains_from_product_param.sql`

**Qué hace:**
- Reemplaza la RPC `upsert_combo_atomic` con versión que **calcula contains desde items**
- Ignora cualquier valor de `product.contains` que venga del cliente
- Valida bounds (2-9 unidades) sobre el `contains` calculado
- Previene recursión de combos

**Instrucciones:**
1. Abre el **SQL Editor** en Supabase
2. Copia y pega el contenido completo del archivo
3. Click en **Run**
4. ✅ Debe completar sin errores

---

### ✅ **PASO 2: Verificar cambios en Flutter (YA APLICADOS)**

Los siguientes cambios ya están aplicados en el código Flutter:

#### **2.1. Servicio Supabase** (`lib/supabase/supabase_config.dart`)
```dart
// ANTES (❌ enviaba contains duplicado):
product['contains'] = cleaned;

// DESPUÉS (✅ NO envía contains):
product.remove('contains'); // RPC lo calcula automáticamente
```

#### **2.2. Pantalla Combo Edit** (`lib/screens/restaurant/combo_edit_screen.dart`)
```dart
// ANTES (❌ incluía contains en productPayload):
final productPayload = {
  ...
  'contains': _selectedItems.entries.map(...).toList(),
};

// DESPUÉS (✅ NO incluye contains):
final productPayload = {
  'restaurant_id': widget.restaurant.id,
  'name': _nameCtrl.text.trim(),
  'price': double.parse(_priceCtrl.text.trim()),
  'type': 'combo',
  // NO incluir 'contains' - la RPC lo calcula
};

final items = _selectedItems.entries
    .map((e) => {'product_id': e.key, 'quantity': e.value})
    .toList();
```

---

## 🧪 Validación

### **Prueba 1: Crear combo nuevo**
1. En la app, navega a **Productos** del restaurante
2. Click en **Crear Combo**
3. Agrega nombre, precio e imagen
4. Selecciona 2-9 productos con cantidades
5. Click en **Crear combo**
6. ✅ Debe guardarse sin error
7. ✅ En Supabase SQL Editor, valida:
   ```sql
   SELECT id, name, type, contains 
   FROM products 
   WHERE type = 'combo' 
   ORDER BY created_at DESC 
   LIMIT 1;
   ```
   - `contains` debe ser un array JSON con `[{product_id, quantity}, ...]`

### **Prueba 2: Editar combo existente**
1. Click en un combo existente
2. Modifica cantidades o productos
3. Click en **Guardar cambios**
4. ✅ Debe actualizarse sin error
5. ✅ Valida que `contains` refleje los cambios

### **Prueba 3: Validaciones de negocio**
1. **Mínimo 2 unidades:**
   - Intenta crear combo con 1 solo producto qty=1
   - ❌ Debe rechazar con mensaje "entre 2 y 9 unidades"
2. **Máximo 9 unidades:**
   - Intenta agregar 10+ unidades
   - ❌ UI debe bloquear en 9 máximo
3. **Sin recursión:**
   - Intenta agregar un combo dentro de otro combo
   - ❌ Debe rechazar con "recursión prohibida"

---

## 📊 Esquema de Flujo Final

```
┌─────────────────────┐
│ Flutter UI          │
│ combo_edit_screen   │
└──────────┬──────────┘
           │
           │ {product: {...}, items: [{product_id, quantity}]}
           │ (SIN 'contains' en product)
           ▼
┌─────────────────────┐
│ supabase_config.dart│
│ upsertCombo()       │
│ • product.remove('contains')
└──────────┬──────────┘
           │
           │ RPC: upsert_combo_atomic(product, items, product_id)
           ▼
┌─────────────────────────────────────────┐
│ Supabase RPC upsert_combo_atomic        │
│                                          │
│ 1. Valida items no vacío                │
│ 2. Calcula v_computed_contains desde    │
│    items (ignora product.contains)      │
│ 3. Valida 2-9 unidades                  │
│ 4. Valida sin recursión                 │
│ 5. INSERT/UPDATE products con:          │
│    type='combo', contains=v_computed    │
│ 6. INSERT product_combo_items           │
└──────────┬──────────────────────────────┘
           │
           │ AFTER INSERT/UPDATE
           ▼
┌─────────────────────────────────────────┐
│ Trigger: fn_sync_combo_contains         │
│                                          │
│ • Mantiene products.contains sincro con │
│   product_combo_items (caché redundante)│
└─────────────────────────────────────────┘
```

---

## 📝 Resumen de Cambios

### **SQL (Supabase):**
- ✅ RPC `upsert_combo_atomic` calcula `contains` internamente desde `items`
- ✅ Ignora `product.contains` del cliente
- ✅ Valida sobre el `contains` calculado (no sobre lo que viene del cliente)

### **Flutter:**
- ✅ `supabase_config.dart`: Elimina `product['contains']` antes de enviar
- ✅ `combo_edit_screen.dart`: No incluye `contains` en `productPayload`

### **Beneficios:**
- ✅ Fuente única de verdad para `contains` (RPC)
- ✅ Elimina ambigüedades y conflictos de sincronización
- ✅ Validaciones consistentes en un solo punto
- ✅ Cliente más simple (no gestiona `contains`)

---

## ⚠️ Notas Importantes

1. **Orden de ejecución:** Solo necesitas ejecutar el PASO 1 (script SQL). Los cambios de Flutter ya están aplicados.

2. **Triggers existentes:** El script NO elimina los triggers de sincronización (`fn_sync_combo_contains`) porque siguen siendo útiles como backup/validación.

3. **Migraciones previas:** Este script reemplaza cualquier versión anterior de `upsert_combo_atomic`, por lo que es idempotente.

4. **Rollback:** Si necesitas revertir, simplemente ejecuta la versión anterior del RPC desde el historial de SQL Editor.

---

## 🎯 Próximos Pasos

Después de ejecutar el PASO 1:

1. ✅ Hot restart de la app Flutter
2. 🧪 Ejecuta las pruebas de validación descritas arriba
3. 📊 Monitorea logs de Supabase para confirmar que no hay errores
4. 🎉 Combos funcionando correctamente

---

**¿Dudas o errores?** Revisa los logs de Supabase y los mensajes de la app. Todos los errores ahora deben ser descriptivos y claros.
