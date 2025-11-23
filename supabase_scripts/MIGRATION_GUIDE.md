# 🚀 GUÍA DE MIGRACIÓN: UUID + RLS + STORAGE

## 📋 Resumen

Esta migración corrige los errores de RLS (`text = uuid`) y configura correctamente el sistema de almacenamiento de imágenes.

**Tiempo estimado:** 10-15 minutos  
**Requiere:** Acceso a Supabase Dashboard (SQL Editor + Storage)  
**Impacto:** ✅ Elimina datos de prueba (safe)

---

## 🎯 Paso 1: LIMPIAR DATOS DE PRUEBA

**Archivo:** `54_cleanup_test_data.sql`

1. Ve a **Supabase Dashboard** → **SQL Editor**
2. Haz clic en **"New Query"**
3. Copia y pega el contenido de `54_cleanup_test_data.sql`
4. Haz clic en **"Run"**

**Resultado esperado:**
```
✅ 11 tablas con 0 registros cada una
✅ Base de datos limpia
```

**⚠️ IMPORTANTE:** Este paso elimina TODOS los datos de prueba. Si tienes datos importantes, haz backup primero.

---

## 🔒 Paso 2: APLICAR POLÍTICAS RLS CORREGIDAS

**Archivo:** `55_fix_rls_policies.sql`

1. En **SQL Editor**, crea otra **"New Query"**
2. Copia y pega el contenido de `55_fix_rls_policies.sql`
3. Haz clic en **"Run"**

**Resultado esperado:**
```
✅ Políticas antiguas eliminadas
✅ RLS habilitado en todas las tablas
✅ Políticas nuevas creadas (sin errores de tipo)
```

**Qué hace:**
- Elimina políticas antiguas que causaban `text = uuid`
- Recrea todas las políticas con tipos correctos
- Asegura que `auth.uid()` se compare solo con columnas `uuid`

---

## ✅ Paso 3: VALIDAR MIGRACIÓN

**Archivo:** `56_validate_schema.sql`

1. En **SQL Editor**, crea otra **"New Query"**
2. Copia y pega el contenido de `56_validate_schema.sql`
3. Haz clic en **"Run"**

**Resultado esperado:**
```sql
-- Verificación 1: Todas las columnas *_id son UUID ✅
-- Verificación 2: Foreign keys correctas ✅
-- Verificación 3: Políticas RLS activas ✅
-- Verificación 4: RLS habilitado en todas las tablas ✅
-- Verificación 5: Constraints de CHECK correctos ✅
-- Verificación 6-8: Triggers y funciones activos ✅
```

**Si todo está ✅:** Continúa al Paso 4  
**Si algo falla:** Revisa el error y vuelve al paso correspondiente

---

## 📦 Paso 4: CREAR BUCKETS DE STORAGE

**Manual** (no hay script SQL para esto)

1. Ve a **Supabase Dashboard** → **Storage**
2. Haz clic en **"Create a new bucket"** (4 veces)

### Bucket 1: profile-images
- **Name:** `profile-images`
- **Public:** ✅ **SÍ** (marcar checkbox)
- **File size limit:** 5 MB
- **Allowed MIME types:** `image/jpeg, image/png, image/webp`

### Bucket 2: restaurant-images
- **Name:** `restaurant-images`
- **Public:** ✅ **SÍ**
- **File size limit:** 10 MB
- **Allowed MIME types:** `image/jpeg, image/png, image/webp`

### Bucket 3: documents
- **Name:** `documents`
- **Public:** ❌ **NO**
- **File size limit:** 10 MB
- **Allowed MIME types:** `image/jpeg, image/png, application/pdf`

### Bucket 4: vehicle-images
- **Name:** `vehicle-images`
- **Public:** ❌ **NO**
- **File size limit:** 5 MB
- **Allowed MIME types:** `image/jpeg, image/png, image/webp`

**Resultado esperado:**  
✅ 4 buckets creados en Storage

---

## 🔐 Paso 5: APLICAR POLÍTICAS DE STORAGE

**Archivo:** `57_storage_policies_fixed.sql`

1. Ve a **SQL Editor**, crea **"New Query"**
2. Copia y pega el contenido de `57_storage_policies_fixed.sql`
3. Haz clic en **"Run"**

**Resultado esperado:**
```
✅ 20 políticas creadas (4 por bucket)
✅ Profile images: público ✅
✅ Restaurant images: público ✅
✅ Documents: privado (solo dueño + admin) ✅
✅ Vehicle images: privado (solo dueño + admin) ✅
```

---

## 🧪 Paso 6: PROBAR EL SISTEMA

### Test 1: Crear Usuario Restaurante
1. Ve a tu app en Dreamflow
2. Haz clic en **"Registrar Restaurante"**
3. Llena todos los campos:
   - Nombre, email, contraseña
   - Nombre del restaurante
   - Dirección, teléfono
   - **Sube logo del restaurante** 📷
   - **Sube imagen del menú** 📷
   - **Sube permisos comerciales** 📄
4. Haz clic en **"Registrar"**

**Resultado esperado:**
```
✅ Usuario creado en auth.users
✅ Perfil creado en public.users
✅ Restaurante creado en public.restaurants
✅ Account creado en public.accounts
✅ Imágenes subidas a Storage
✅ URLs guardadas en la BD
✅ Sin errores de RLS ✅
```

### Test 2: Crear Usuario Repartidor
1. Ve a **"Registrar Repartidor"**
2. Llena todos los campos:
   - Nombre, email, contraseña
   - Teléfono, dirección
   - **Sube foto de perfil** 📷
   - **Sube documento de identidad (frente)** 📄
   - **Sube documento de identidad (reverso)** 📄
   - **Sube foto del vehículo** 📷
   - Tipo de vehículo, placa, modelo, color
3. Haz clic en **"Registrar"**

**Resultado esperado:**
```
✅ Usuario creado
✅ Perfil de repartidor completo
✅ Account creado
✅ Imágenes privadas subidas
✅ Sin errores ✅
```

### Test 3: Verificar Storage
1. Ve a **Supabase Dashboard** → **Storage**
2. Abre cada bucket y verifica:
   - `profile-images`: carpetas con UUIDs, imágenes de perfil
   - `restaurant-images`: logos y menús
   - `documents`: permisos comerciales
   - `vehicle-images`: fotos de vehículos

**Resultado esperado:**
```
✅ Archivos organizados por UUID
✅ Acceso público/privado correcto
✅ URLs accesibles desde la app
```

---

## 🎉 ¡Migración Completa!

### ✅ Checklist Final

- [x] Datos de prueba eliminados
- [x] Políticas RLS corregidas (sin `text = uuid`)
- [x] Schema validado
- [x] Buckets de Storage creados
- [x] Políticas de Storage aplicadas
- [x] Tests de registro funcionando
- [x] Imágenes subiéndose correctamente

### 🚀 Próximos Pasos

Tu sistema ahora tiene:
- ✅ **Tipos de datos consistentes** (UUID en todas partes)
- ✅ **Seguridad RLS funcional** (sin errores de casting)
- ✅ **Storage configurado** (público/privado)
- ✅ **Captura completa de datos** (perfil + documentos + imágenes)

Puedes continuar con:
1. **Mejorar UI/UX** del proceso de registro
2. **Agregar validaciones** de documentos
3. **Implementar aprobación** de restaurantes/repartidores
4. **Dashboard de administración** para revisar documentos

---

## 🆘 Troubleshooting

### Error: "text = uuid"
- **Causa:** No ejecutaste el paso 2 (`55_fix_rls_policies.sql`)
- **Solución:** Ejecuta el script completo del paso 2

### Error: "bucket does not exist"
- **Causa:** No creaste los buckets en el paso 4
- **Solución:** Ve a Storage y crea los 4 buckets manualmente

### Error: "permission denied for relation users"
- **Causa:** RLS bloqueando acceso
- **Solución:** Verifica que las políticas se aplicaron correctamente (paso 3)

### Imágenes no se suben
- **Causa:** Políticas de Storage no aplicadas
- **Solución:** Ejecuta el paso 5 (`57_storage_policies_fixed.sql`)

### No puedo ver imágenes en la app
- **Causa:** Bucket privado o URLs incorrectas
- **Solución:** 
  - Verifica que `profile-images` y `restaurant-images` sean **públicos**
  - Revisa `StorageService.getPublicUrl()` en el código

---

## 📞 Soporte

Si encuentras errores no listados aquí:
1. Copia el mensaje de error completo
2. Anota en qué paso ocurrió
3. Revisa los logs en **Supabase Dashboard** → **Logs**
4. Pide ayuda con el contexto completo

---

**Versión:** 1.0  
**Fecha:** 2025  
**Autor:** Hologram AI Assistant
