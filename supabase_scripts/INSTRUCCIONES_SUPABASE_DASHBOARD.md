# 🔧 INSTRUCCIONES: Configurar Email Confirmation en Supabase Dashboard

## 🔍 **PROBLEMA IDENTIFICADO**

El error `otp_expired` / `Email link is invalid or has expired` ocurre porque:

1. ✅ El trigger de base de datos funciona correctamente
2. ✅ Las políticas RLS están bien configuradas
3. ❌ **El redirect URL de Supabase NO está configurado correctamente**
4. ❌ **Los tokens expiran muy rápido (por defecto 1 hora)**

---

## ✅ **SOLUCIÓN PASO A PASO**

### **1️⃣ Configurar Redirect URLs**

1. Ve a [Supabase Dashboard](https://supabase.com/dashboard)
2. Selecciona tu proyecto: **`DOA Repartos`**
3. Ve a: **Authentication** > **URL Configuration**

4. **Site URL**: Configura esta URL exacta:
   ```
   https://i20tpls7s2z0kjevuoyg.share.dreamflow.app
   ```

5. **Redirect URLs**: Agrega estas URLs (una por línea):
   ```
   https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/**
   http://localhost:3000/**
   ```

6. Click **Save**

---

### **2️⃣ Verificar/Configurar Email Template**

1. Ve a: **Authentication** > **Email Templates** > **Confirm signup**

2. **Verifica el template actual:**
   - Debe contener `{{ .ConfirmationURL }}` (este es el enlace de confirmación)
   - Si no existe, usa este template:

```html
<h2>Confirma tu correo electrónico</h2>

<p>Hola,</p>

<p>Gracias por registrarte en DOA Repartos. Para completar tu registro, por favor confirma tu correo electrónico haciendo clic en el siguiente enlace:</p>

<p><a href="{{ .ConfirmationURL }}">Confirmar mi correo electrónico</a></p>

<p>O copia y pega este enlace en tu navegador:</p>
<p>{{ .ConfirmationURL }}</p>

<p>Este enlace expirará en 24 horas.</p>

<p>Si no creaste esta cuenta, puedes ignorar este correo.</p>

<p>Saludos,<br>
El equipo de DOA Repartos</p>
```

3. **Configuración adicional del template:**
   - Subject: `Confirma tu correo electrónico - DOA Repartos`
   - Click **Save**

---

### **3️⃣ Aumentar Token Expiration**

1. En la misma página de **Email Templates** > **Confirm signup**
2. Busca **Token expiration** (usualmente en la parte inferior)
3. Cambia de `3600` (1 hora) a `86400` (24 horas)
4. Click **Save**

---

### **4️⃣ Verificar SMTP Configuration (Opcional pero recomendado)**

Si los emails NO están llegando o demoran mucho:

1. Ve a: **Project Settings** > **Auth** > **SMTP Settings**
2. Verifica que:
   - **Enable Custom SMTP** esté activado (opcional, solo si quieres usar tu propio servidor)
   - Si usas el SMTP de Supabase (default), NO hay nada que configurar aquí

---

## 🧪 **CÓMO PROBAR QUE FUNCIONA**

### **Test 1: Registrar nuevo usuario**

1. Abre tu app: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app
2. Ve a **Registro**
3. Llena el formulario con un email NUEVO (no usado antes)
4. Click **Registrar**
5. **Verifica:**
   - ✅ Debe aparecer diálogo "Verifica tu correo electrónico"
   - ✅ Debe llegar email en menos de 1 minuto

### **Test 2: Verificar el enlace del email**

1. Abre el email de confirmación
2. **ANTES de hacer clic**, pasa el mouse sobre el enlace "Confirmar mi correo electrónico"
3. **Verifica que la URL contenga:**
   ```
   https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/?token_hash=...&type=signup
   ```
   - ✅ El dominio debe coincidir con tu Site URL
   - ✅ Debe tener `token_hash=...` (NO `access_token`)
   - ✅ Debe tener `type=signup`

4. **Haz clic en el enlace**
5. **Resultado esperado:**
   - ✅ Te redirige a la app
   - ✅ Aparece en `/login` automáticamente
   - ✅ En console NO debe aparecer error
   - ✅ Puedes iniciar sesión normalmente

---

## 🐛 **SI SIGUE FALLANDO**

### **Verificar en Console Log:**

Abre DevTools (F12) y busca estos logs:

```
✅ CORRECTO:
🔎 [AUTH_REDIRECT] URL: https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/?token_hash=...&type=signup
✅ [AUTH_REDIRECT] access_token present (length=...)  type=signup
👤 [AUTH_REDIRECT] Current user after init: email@test.com  confirmedAt=2024-...

❌ INCORRECTO:
🔎 [AUTH_REDIRECT] URL: .../?error=otp_expired&error_code=access_denied
❗ [AUTH_REDIRECT] Error from Supabase: code=access_denied, description=Email link is invalid or has expired
⚠️ [AUTH_REDIRECT] No access_token in fragment. type=null
👤 [AUTH_REDIRECT] Current user after init: null  confirmedAt=null
```

### **Verificar en Base de Datos:**

Ejecuta este query en Supabase SQL Editor:

```sql
-- Ver usuarios y su estado de confirmación
SELECT 
  au.id,
  au.email,
  au.email_confirmed_at as auth_confirmed,
  pu.email_confirm as public_confirmed,
  au.created_at
FROM auth.users au
LEFT JOIN public.users pu ON pu.id = au.id
ORDER BY au.created_at DESC
LIMIT 10;
```

**Resultado esperado:**
- `auth_confirmed` y `public_confirmed` deben estar **sincronizados**
- Si `auth_confirmed IS NOT NULL` pero `public_confirmed = false`, ejecuta el script `FIX_EMAIL_CONFIRMATION_COMPLETE.sql`

### **Ver logs del trigger:**

```sql
SELECT * FROM public.function_logs
WHERE function_name = 'handle_email_confirmed'
ORDER BY created_at DESC
LIMIT 10;
```

---

## 📋 **CHECKLIST FINAL**

Antes de probar de nuevo, verifica que:

- [ ] Site URL configurado: `https://i20tpls7s2z0kjevuoyg.share.dreamflow.app`
- [ ] Redirect URL agregado: `https://i20tpls7s2z0kjevuoyg.share.dreamflow.app/**`
- [ ] Email template contiene `{{ .ConfirmationURL }}`
- [ ] Token expiration = `86400` (24 horas)
- [ ] Script `FIX_EMAIL_CONFIRMATION_COMPLETE.sql` ejecutado
- [ ] Usuarios desincronizados = 0

---

## 🎯 **CONTACTO DE SOPORTE**

Si después de seguir estos pasos el problema persiste:

1. Toma screenshot del:
   - Supabase Dashboard > Authentication > URL Configuration
   - Supabase Dashboard > Authentication > Email Templates > Confirm signup
   - Console log completo cuando haces clic en el enlace
   - Resultado del query de verificación de usuarios

2. Comparte los screenshots para diagnóstico adicional

---

**Última actualización:** 2025-01-XX
**Versión del script:** v1.0
