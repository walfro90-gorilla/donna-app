# 🔧 Plan: Fix Delivery Agent Registration

## 📋 DIAGNÓSTICO

### Problema Actual:
El sistema **SÍ crea** `auth.users` y `public.users`, pero **NO crea**:
1. ❌ `delivery_agent_profiles` (perfil del repartidor)
2. ❌ `accounts` (cuenta financiera)

### Causa Raíz:
El RPC `register_delivery_agent_atomic()` existe PERO:
- ✅ Está obsoleto y no acepta todos los parámetros que envía el Flutter
- ✅ El Flutter envía 18 parámetros, pero el RPC solo acepta 8
- ✅ Falta crear el registro en `user_preferences`

### Logs del Error:
```
❌ ensureFinancialAccount error: PostgrestException(
  message: function public.ensure_delivery_agent_role_and_profile(uuid) does not exist
)
```

Este error aparece porque el código Flutter está intentando llamar una función que **fue eliminada**.

---

## 🎯 SOLUCIÓN

### Estrategia Quirúrgica:

1. **Actualizar el RPC `register_delivery_agent_atomic()`** para:
   - Aceptar TODOS los parámetros que envía Flutter
   - Crear registro en `delivery_agent_profiles` con TODOS los campos
   - Crear registro en `accounts` con `account_type = 'delivery_agent'`
   - Crear registro en `user_preferences`
   - Usar sintaxis PostgreSQL correcta según `DATABASE_SCHEMA.sql`

2. **Alinear con el schema existente**:
   - Usar `delivery_agent_status` enum para `status` field
   - Usar `delivery_agent_account_state` enum para `account_state` field
   - Respetar constraints y foreign keys

---

## 📁 Archivos a Modificar

### SQL:
1. **`FIX_DELIVERY_AGENT_REGISTRATION_COMPLETE.sql`** (NUEVO)
   - Actualiza `register_delivery_agent_atomic()` con firma completa
   - Crea registros en: `delivery_agent_profiles`, `accounts`, `user_preferences`
   - Manejo atómico de transacciones

### Flutter:
✅ **NO modificar nada** - El código Flutter ya está enviando los parámetros correctos

---

## 🔍 Tabla de Comparación

| Campo                        | Flutter envía ✅ | RPC actual acepta | RPC nuevo acepta ✅ |
|------------------------------|-----------------|-------------------|---------------------|
| user_id                      | ✅              | ✅                | ✅                  |
| email                        | ✅              | ✅                | ✅                  |
| name                         | ✅              | ✅                | ✅                  |
| phone                        | ✅              | ✅                | ✅                  |
| address                      | ✅              | ❌                | ✅                  |
| lat/lon                      | ✅              | ❌                | ✅                  |
| address_structured           | ✅              | ❌                | ✅                  |
| place_id                     | ✅              | ❌                | ✅                  |
| vehicle_type                 | ✅              | ✅                | ✅                  |
| vehicle_plate                | ✅              | ✅                | ✅                  |
| vehicle_model                | ✅              | ✅                | ✅                  |
| vehicle_color                | ✅              | ✅                | ✅                  |
| emergency_contact_name       | ✅              | ❌                | ✅                  |
| emergency_contact_phone      | ✅              | ❌                | ✅                  |
| profile_image_url            | ✅              | ❌                | ✅                  |
| id_document_front_url        | ✅              | ❌                | ✅                  |
| id_document_back_url         | ✅              | ❌                | ✅                  |
| vehicle_photo_url            | ✅              | ❌                | ✅                  |
| vehicle_registration_url     | ✅              | ❌                | ✅                  |
| vehicle_insurance_url        | ✅              | ❌                | ✅                  |

---

## ✅ Resultado Esperado

Después de ejecutar el script SQL, el flujo de registro creará:

1. ✅ `auth.users` (ya funciona)
2. ✅ `public.users` (ya funciona)  
3. ✅ `user_preferences` (**NUEVO**)
4. ✅ `delivery_agent_profiles` (**ARREGLADO** - con TODOS los campos)
5. ✅ `accounts` (**ARREGLADO** - con `account_type = 'delivery_agent'`)

---

## 🚀 Pasos de Ejecución

1. **Copiar** el contenido de `FIX_DELIVERY_AGENT_REGISTRATION_COMPLETE.sql`
2. **Pegar** en Supabase SQL Editor
3. **Ejecutar** el script
4. **Hot Restart** de la app en Dreamflow
5. **Probar** el registro de un nuevo delivery agent
6. **Verificar** en Supabase que se crearon todos los registros

---

## 📌 Notas Importantes

- ✅ Este fix NO rompe nada que ya funciona
- ✅ Solo actualiza el RPC `register_delivery_agent_atomic()`
- ✅ El resto del sistema (restaurant, client) sigue funcionando igual
- ✅ Usa sintaxis PostgreSQL correcta
- ✅ Alineado 100% con `DATABASE_SCHEMA.sql`
