# 🎯 Fix Quirúrgico - user_preferences en Registro de Restaurantes

## ✅ Problema Identificado

El registro de restaurantes funciona correctamente y crea:
- ✅ Usuario en `auth.users`
- ✅ Perfil en `public.users`
- ✅ Restaurante en `public.restaurants`
- ✅ Cuenta financiera en `public.accounts`
- ❌ **FALTA**: Registro en `public.user_preferences`

---

## 🔧 Solución

Hemos actualizado el RPC `register_restaurant_atomic()` para que ahora también cree el registro en `user_preferences` de forma atómica.

---

## 📋 Pasos para Aplicar el Fix

### **1. Ejecutar el Script SQL**

1. Abre **Supabase Dashboard** → **SQL Editor**
2. Copia y pega el contenido completo de:
   ```
   sql_migrations/ADD_USER_PREFERENCES_TO_RESTAURANT_REGISTRATION.sql
   ```
3. Click en **RUN** ▶️
4. Deberías ver el mensaje: **"✅ FIX APLICADO EXITOSAMENTE"**

**Tiempo estimado:** < 5 segundos

---

### **2. Verificar que Funcionó**

#### Opción A: Verificación Automática (Recomendado)
1. Copia y pega el contenido de:
   ```
   sql_migrations/VERIFICAR_USER_PREFERENCES_CREADO.sql
   ```
2. Click en **RUN** ▶️
3. Verifica que las consultas muestren datos correctos

#### Opción B: Verificación Manual
```sql
-- Ver último restaurante con user_preferences
SELECT 
  u.email,
  r.name as restaurant_name,
  up.user_id as preferences_created,
  up.restaurant_id
FROM public.users u
LEFT JOIN public.restaurants r ON r.user_id = u.id
LEFT JOIN public.user_preferences up ON up.user_id = u.id
WHERE u.role = 'restaurant'
ORDER BY r.created_at DESC
LIMIT 1;
```

Si `preferences_created` tiene un UUID, **está funcionando correctamente** ✅

---

### **3. Probar en la App**

1. En Dreamflow, haz **Hot Restart** 🔄 de la app
2. Navega a la pantalla de registro de restaurante
3. Completa el formulario y envía
4. Debería aparecer: **"¡Registro Exitoso!"**

---

### **4. Confirmar en Base de Datos**

Ejecuta de nuevo el script de verificación para confirmar que el nuevo registro tiene `user_preferences`:

```sql
SELECT * FROM public.user_preferences
WHERE user_id IN (
  SELECT id FROM public.users 
  WHERE role = 'restaurant'
  ORDER BY created_at DESC
  LIMIT 1
);
```

**Resultado esperado:** 1 fila con todos los campos llenos ✅

---

## 🔍 Qué Cambia Exactamente

### **Antes:**
```sql
register_restaurant_atomic() creaba:
├── restaurants ✅
├── accounts ✅
└── user_preferences ❌ (faltaba)
```

### **Ahora:**
```sql
register_restaurant_atomic() crea:
├── restaurants ✅
├── accounts ✅
└── user_preferences ✅ (NUEVO)
```

### **Campos creados en user_preferences:**
- `user_id` → ID del usuario
- `restaurant_id` → ID del restaurante recién creado
- `has_seen_onboarding` → false (por defecto)
- `has_seen_restaurant_welcome` → false (por defecto)
- `email_verified_congrats_shown` → false (por defecto)
- `first_login_at` → NULL (se llena en primer login)
- `login_count` → 0
- `created_at` → timestamp actual
- `updated_at` → timestamp actual

---

## ⚠️ Importante

- ✅ **Safe to run**: No modifica datos existentes
- ✅ **Idempotente**: Usa `ON CONFLICT` para evitar duplicados
- ✅ **No rompe nada**: Todo lo demás sigue funcionando igual
- ✅ **PostgreSQL syntax**: Alineado al `DATABASE_SCHEMA.sql`

---

## 🚀 Resultado Final

Después de aplicar este fix, el registro de restaurantes creará **5 registros de forma atómica**:

1. ✅ `auth.users` (Supabase Auth)
2. ✅ `public.users` (Perfil público)
3. ✅ `public.restaurants` (Datos del restaurante)
4. ✅ `public.accounts` (Cuenta financiera)
5. ✅ `public.user_preferences` (Preferencias del usuario) **← NUEVO**

---

## 📞 ¿Problemas?

Si algo sale mal:

1. Revisa los logs de Supabase SQL Editor
2. Ejecuta el script de verificación
3. Confirma que el RPC existe:
   ```sql
   SELECT proname FROM pg_proc 
   WHERE proname = 'register_restaurant_atomic';
   ```

---

**Creado:** 2025-01-10  
**Versión:** 1.0  
**Última actualización:** 2025-01-10
