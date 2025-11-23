# 🎯 PLAN: Fix total_reviews Error - Opción Calculado Dinámicamente

## 📋 **PROBLEMA IDENTIFICADO:**

**Error:**
```
❌ PostgrestException: column "total_reviews" of relation "users" does not exist (code: 42703)
```

**CAUSA RAÍZ:**
- El trigger `update_average_ratings()` intenta actualizar `users.total_reviews`
- Esa columna **YA NO EXISTE** después del refactor 2025
- Ahora `total_reviews` está en cada tabla de profiles:
  - ✅ `client_profiles.total_reviews` 
  - ✅ `restaurants.total_reviews`
  - ❌ `delivery_agent_profiles` **NO tiene** `total_reviews`

---

## 🎯 **ESTRATEGIA ELEGIDA: Opción A - Calcular Dinámicamente**

### **¿POR QUÉ ESTA OPCIÓN?**

✅ **SIMPLICIDAD**
- Solo eliminar trigger roto
- No necesitas agregar columnas a `delivery_agent_profiles`
- Una sola fuente de verdad: tabla `reviews`

✅ **SIEMPRE EXACTO**
- Los datos son en tiempo real desde `reviews`
- No puede haber inconsistencia entre triggers

✅ **APEGADO AL SCHEMA**
- No modifica `DATABASE_SCHEMA.sql`
- No rompe lógica existente de restaurantes/repartidores

✅ **RENDIMIENTO ACEPTABLE**
- Ya usas JOINs para mostrar reviews
- El cálculo `COUNT(*)` es rápido con índices

---

## 🔧 **CAMBIOS A REALIZAR:**

### **1. SQL: Eliminar Trigger Roto**

**Archivo:** `supabase_scripts/FIX_DROP_UPDATE_AVERAGE_RATINGS_TRIGGER.sql`

**Acciones:**
1. ✅ DROP TRIGGER `update_reviews_on_insert` (si existe)
2. ✅ DROP TRIGGER `update_reviews_on_update` (si existe)  
3. ✅ DROP FUNCTION `update_average_ratings()` (si existe)
4. ✅ Dejar intacto `average_rating` y `total_reviews` en profiles (se calculará dinámicamente)

---

### **2. FLUTTER: Actualizar lógica de display**

**Archivos afectados:**
- `lib/screens/restaurant/restaurant_profile_screen.dart`
- `lib/widgets/restaurant_card.dart`
- `lib/screens/delivery/delivery_main_dashboard.dart`
- Cualquier widget que muestre `total_reviews` o `average_rating`

**Lógica Nueva:**
```dart
// ANTES (leer de restaurant.total_reviews):
final totalReviews = restaurant.totalReviews ?? 0;

// DESPUÉS (calcular desde reviews):
Future<Map<String, dynamic>> _getReviewStats(String subjectId, {bool isRestaurant = false}) async {
  final query = SupabaseConfig.client
    .from('reviews')
    .select('rating');
    
  if (isRestaurant) {
    query.eq('subject_restaurant_id', subjectId);
  } else {
    query.eq('subject_user_id', subjectId);
  }
  
  final data = await query;
  final ratings = data.map((e) => e['rating'] as int).toList();
  
  return {
    'total_reviews': ratings.length,
    'average_rating': ratings.isEmpty ? 0.0 : ratings.reduce((a, b) => a + b) / ratings.length,
  };
}
```

**ALTERNATIVA (si prefieres mantener valores en profiles):**
- Crea un **cron job** o **edge function** que actualice `total_reviews` y `average_rating` cada X minutos
- Mantiene la lectura rápida pero sin triggers en tiempo real

---

## 📦 **OPCIÓN B (NO ELEGIDA): Almacenar con Trigger**

### **¿Por qué NO?**

❌ **Complejidad Innecesaria:**
- Necesitarías agregar `total_reviews` a `delivery_agent_profiles`
- Trigger debe hacer 3 UPDATEs diferentes según el `subject`
- Más código que mantener

❌ **Riesgo de Inconsistencia:**
- Si el trigger falla, los contadores quedan desincronizados
- Difícil de debuggear

**CÓDIGO DEL TRIGGER (si decides usarlo después):**
```sql
CREATE OR REPLACE FUNCTION update_average_ratings_v2()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Actualizar cliente
  IF NEW.subject_user_id IS NOT NULL THEN
    UPDATE public.client_profiles
    SET 
      total_reviews = (SELECT COUNT(*) FROM reviews WHERE subject_user_id = NEW.subject_user_id),
      average_rating = (SELECT AVG(rating) FROM reviews WHERE subject_user_id = NEW.subject_user_id)
    WHERE user_id = NEW.subject_user_id;
  END IF;

  -- Actualizar restaurante  
  IF NEW.subject_restaurant_id IS NOT NULL THEN
    UPDATE public.restaurants
    SET 
      total_reviews = (SELECT COUNT(*) FROM reviews WHERE subject_restaurant_id = NEW.subject_restaurant_id),
      average_rating = (SELECT AVG(rating) FROM reviews WHERE subject_restaurant_id = NEW.subject_restaurant_id)
    WHERE id = NEW.subject_restaurant_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Crear trigger
DROP TRIGGER IF EXISTS update_reviews_on_insert ON public.reviews;
CREATE TRIGGER update_reviews_on_insert
AFTER INSERT ON public.reviews
FOR EACH ROW EXECUTE FUNCTION update_average_ratings_v2();
```

---

## 🚀 **SIGUIENTE PASO:**

1. ✅ Corre el script `FIX_DROP_UPDATE_AVERAGE_RATINGS_TRIGGER.sql`
2. ✅ Prueba crear un review (no debe fallar)
3. ⚠️ **IMPORTANTE:** Los valores actuales de `total_reviews` y `average_rating` en las tablas **NO se actualizarán automáticamente**
   - Opciones:
     - **A)** Ignóralos y calcula siempre dinámicamente
     - **B)** Corre un script de migración para poblarlos una vez
     - **C)** Crea un cron job para actualizarlos periódicamente

---

## 📝 **NOTAS ADICIONALES:**

- ✅ **No rompe nada:** Solo elimina trigger que ya está roto
- ✅ **Sin cambios en schema:** Mantiene columnas `total_reviews` y `average_rating` por si después decides usarlas
- ✅ **Compatible con restaurantes/repartidores:** Su lógica de registro no se toca
