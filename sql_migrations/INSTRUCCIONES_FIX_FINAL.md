# 🎯 INSTRUCCIONES - FIX REGISTRO DE RESTAURANTES

## 📝 RESUMEN

Este fix resuelve **DOS problemas** en el registro de restaurantes:

1. ❌ **Error**: `record "old" has no field "status" (42703)`
2. ❌ **Error**: `permission denied for table restaurants (42501)`

**✅ Script mejorado**: Sintaxis PostgreSQL correcta, alineado al `DATABASE_SCHEMA.sql`, con manejo robusto de errores.

---

## 🚀 PASOS PARA EJECUTAR

### 1. Abrir Supabase SQL Editor

1. Ve a tu **Supabase Dashboard**
2. Navega a **SQL Editor** (barra lateral izquierda)
3. Click en **New Query**

### 2. Copiar y Pegar el Script

1. Abre el archivo: **`sql_migrations/FIX_COMPLETE_RESTAURANT_REGISTRATION.sql`**
2. **Copia TODO el contenido** del archivo
3. **Pega** en el SQL Editor de Supabase

### 3. Ejecutar el Script

1. Click en el botón **Run** (o presiona `Ctrl+Enter`)
2. Espera **5-10 segundos** a que termine
3. Verifica que veas el mensaje: **`✅ FIX COMPLETADO EXITOSAMENTE`**

### 4. Verificar Resultados

Deberías ver en la consola:

```
✅ ✅ ✅ FIX COMPLETADO EXITOSAMENTE ✅ ✅ ✅

🎯 Problemas resueltos:
   1. Error "OLD.status" eliminado
   2. RPC register_restaurant_atomic creada
   3. Permission denied resuelto

🚀 Próximos pasos:
   1. Actualizar código Flutter para usar RPC
   2. Probar registro de restaurante
   3. Verificar que no hay errores
```

---

## ✅ QUÉ HACE EL SCRIPT

### Parte 1: Elimina Triggers Problemáticos
- Elimina triggers que buscan columna `status` en `users` (que no existe)
- Elimina funciones legacy de sincronización de status

### Parte 2: Crea RPC para Registro
- Crea función `register_restaurant_atomic()` con permisos elevados
- Permite registro de restaurantes sin problemas de permisos RLS
- Es **idempotente** y **safe to run múltiples veces**

### Parte 3: Verificación Automática
- Cuenta triggers restantes
- Verifica que RPC fue creada correctamente
- Muestra resumen de resultados

---

## 🔄 YA ACTUALICÉ EL CÓDIGO FLUTTER

El código Flutter ya fue modificado para:
1. ✅ Usar `RpcNames.registerRestaurantAtomic` en lugar de inserción directa
2. ✅ Pasar todos los parámetros correctamente
3. ✅ Manejar errores apropiadamente

**No necesitas hacer cambios en el código Flutter.**

---

## 🧪 DESPUÉS DE EJECUTAR EL SCRIPT

1. **Reinicia el preview** de Dreamflow (Hot Restart)
2. **Intenta registrar un restaurante** nuevamente
3. **Verifica** que no aparezcan errores en consola
4. **El registro debería completarse exitosamente**

---

## ⚠️ NOTAS IMPORTANTES

- ✅ **Safe to run**: No modifica datos existentes
- ✅ **Idempotente**: Puedes ejecutarlo múltiples veces sin problemas
- ✅ **No afecta** registro de clientes (que ya funciona correctamente)
- ✅ **No modifica** tablas ni columnas existentes

---

## 📞 SI HAY PROBLEMAS

Si ves errores después de ejecutar el script:

1. **Copia el mensaje de error completo**
2. **Comparte** el error conmigo
3. Puedo crear un rollback script si es necesario

---

## 🎉 RESULTADO ESPERADO

Después del fix:
- ✅ No más error `OLD.status`
- ✅ No más error `permission denied`
- ✅ Registro de restaurantes funciona perfectamente
- ✅ Notificaciones admin se crean automáticamente
- ✅ Cuentas financieras se crean automáticamente
