# 🔧 Solución al Error 403: Unauthorized - Storage

## 🐛 **Problema Identificado**

El error que estás experimentando:
```
StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)
```

Ocurre porque **las políticas de Row-Level Security (RLS) en Supabase Storage no están configuradas correctamente** o no existen.

---

## ✅ **Solución Rápida (Recomendada)**

### **Paso 1: Verifica que los buckets existan**

Ve a tu proyecto de Supabase:
1. Abre **Supabase Dashboard** → **Storage**
2. Verifica que existan estos 4 buckets:
   - ✅ `profile-images` (público)
   - ✅ `restaurant-images` (público)
   - ✅ `documents` (privado)
   - ✅ `vehicle-images` (privado)

Si alguno no existe, créalo:
- Click en **"New bucket"**
- Nombre del bucket (ej: `restaurant-images`)
- Marca como **público** si corresponde
- Click en **"Create bucket"**

---

### **Paso 2: Ejecuta el script SQL**

Tienes **2 opciones** de scripts SQL:

#### **Opción A: Script Permisivo (Recomendado para desarrollo)**

Este script permite a cualquier usuario autenticado subir imágenes a `restaurant-images`:

1. Abre **Supabase Dashboard** → **SQL Editor**
2. Click en **"New query"**
3. Copia y pega el contenido del archivo:
   ```
   supabase_scripts/FIX_storage_policies_rls.sql
   ```
4. Click en **"Run"**
5. ✅ Deberías ver un mensaje de éxito

**Ventaja:** Funciona inmediatamente sin complicaciones.  
**Desventaja:** Cualquier usuario autenticado puede subir imágenes (se asume que la app valida la propiedad).

---

#### **Opción B: Script Estricto (Recomendado para producción)**

Este script valida que el usuario sea **dueño del restaurante** antes de permitir la subida:

1. Abre **Supabase Dashboard** → **SQL Editor**
2. Click en **"New query"**
3. Copia y pega el contenido del archivo:
   ```
   supabase_scripts/FIX_storage_policies_rls_STRICT.sql
   ```
4. Click en **"Run"**
5. ✅ Deberías ver un mensaje de éxito

**Ventaja:** Máxima seguridad - solo el dueño puede subir imágenes de su restaurante.  
**Desventaja:** Requiere que la relación `restaurants.user_id` esté correcta.

---

### **Paso 3: Verifica las políticas**

Después de ejecutar el script, verifica que las políticas se crearon:

1. En **SQL Editor**, ejecuta:
   ```sql
   SELECT
     policyname,
     cmd,
     roles
   FROM pg_policies
   WHERE tablename = 'objects'
     AND schemaname = 'storage'
     AND policyname LIKE 'restaurant_images%'
   ORDER BY policyname;
   ```

2. ✅ Deberías ver 4 políticas:
   - `restaurant_images_upload` (INSERT)
   - `restaurant_images_read` (SELECT)
   - `restaurant_images_update` (UPDATE)
   - `restaurant_images_delete` (DELETE)

---

### **Paso 4: Prueba la subida de imágenes**

1. Regresa a tu aplicación Dreamflow
2. Ve a **"Mi Restaurante"**
3. Intenta subir una imagen de logo
4. ✅ Debería funcionar sin errores

---

## 🔍 **Troubleshooting**

### **Si sigues teniendo el error 403:**

#### **1. Verifica que el usuario esté autenticado**
```sql
SELECT auth.uid();
```
✅ Debería retornar tu UUID de usuario (no NULL)

---

#### **2. Verifica que el restaurante existe**
```sql
SELECT id, user_id, name 
FROM public.restaurants 
WHERE user_id = auth.uid();
```
✅ Debería mostrar tu restaurante con el `user_id` correcto

---

#### **3. Verifica la estructura del path**

El path que se intenta subir debe ser:
```
<restaurant_id>/<filename>
```

Ejemplo correcto:
```
5afb0bac-e526-423e-b74e-695de7554abf/logo_1759886963129.jpg
```

La política extrae el `restaurant_id` del path usando:
```sql
(storage.foldername(name))[1]
```

---

#### **4. Verifica manualmente la política**

Reemplaza los UUIDs con tus valores reales:

```sql
SELECT EXISTS (
  SELECT 1 
  FROM public.restaurants r
  WHERE r.id::text = '5afb0bac-e526-423e-b74e-695de7554abf'
    AND r.user_id = '203b6855-db86-4764-a33d-380efda49436'
);
```

✅ Debería retornar **`TRUE`** si el usuario es dueño del restaurante.

Si retorna **`FALSE`**, el problema es que:
- El restaurante no existe
- El `user_id` del restaurante no coincide con el usuario autenticado

---

#### **5. Solución temporal: Deshabilita RLS (NO RECOMENDADO)**

**⚠️ SOLO PARA DEBUG - NO USAR EN PRODUCCIÓN**

Si necesitas debug temporalmente:

```sql
ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY;
```

**IMPORTANTE:** Esto deshabilita TODA la seguridad. Vuelve a habilitarlo después:
```sql
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
```

---

## 📚 **Recursos Adicionales**

- [Supabase Storage Documentation](https://supabase.com/docs/guides/storage)
- [Row Level Security Policies](https://supabase.com/docs/guides/auth/row-level-security)

---

## 🎯 **Resumen**

1. ✅ Verifica que los buckets existan
2. ✅ Ejecuta el script SQL (Opción A o B)
3. ✅ Verifica que las políticas se crearon
4. ✅ Prueba subir una imagen

**Si sigues teniendo problemas, ejecuta las queries de troubleshooting y comparte los resultados.**

---

**¡Buena suerte! 🚀**
