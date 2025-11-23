# 📋 Guía: Registro de Repartidores desde Web

## 🎯 Objetivo
Esta guía explica **exactamente cómo funciona el formulario de registro de repartidores en la app de Flutter**, para que puedas replicarlo en tu sitio web oficial usando las mismas funciones RPC y triggers de Supabase.

---

## 📌 Resumen del Flujo de Registro

El registro de repartidores en la app Flutter sigue un flujo de **2 pasos atómicos**:

### **PASO 1:** Crear usuario en `auth.users` ✅
- Se utiliza `supabase.auth.signUp()`
- Se envía email de verificación automáticamente
- Se crea entrada en la tabla `auth.users` de Supabase Auth

### **PASO 2:** Ejecutar función RPC atómica ✅
- Se llama a `register_delivery_agent_atomic()`
- Crea registros en: `users`, `delivery_agent_profiles`, `accounts`, `user_preferences`
- Todo en una sola transacción (atómico)

---

## 🏗️ Estructura de Tablas (DATABASE_SCHEMA.sql)

### 1️⃣ **Tabla `users`** (perfil público)
```sql
CREATE TABLE public.users (
  id uuid PRIMARY KEY,           -- Mismo ID que auth.users
  email text NOT NULL UNIQUE,
  name text NOT NULL,
  phone text UNIQUE,
  address text,
  lat double precision,          -- Latitud de dirección
  lon double precision,          -- Longitud de dirección
  address_structured jsonb,      -- JSON con info completa de Google Places
  role text NOT NULL,            -- 'delivery_agent'
  email_confirm boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
```

### 2️⃣ **Tabla `delivery_agent_profiles`** (perfil del repartidor)
```sql
CREATE TABLE public.delivery_agent_profiles (
  user_id uuid PRIMARY KEY,                    -- FK a users(id)
  profile_image_url text,                      -- URL imagen perfil
  id_document_front_url text,                  -- URL frente INE
  id_document_back_url text,                   -- URL reverso INE
  vehicle_type text CHECK (vehicle_type IN ('bicicleta', 'motocicleta', 'auto', 'pie', 'otro')),
  vehicle_plate text,                          -- Placa del vehículo
  vehicle_model text,                          -- Modelo (opcional)
  vehicle_color text,                          -- Color (opcional)
  vehicle_registration_url text,               -- URL tarjeta circulación
  vehicle_insurance_url text,                  -- URL póliza seguro
  vehicle_photo_url text,                      -- URL foto del vehículo
  emergency_contact_name text,                 -- Nombre contacto emergencia
  emergency_contact_phone text,                -- Teléfono contacto emergencia
  status text DEFAULT 'pending',               -- 'pending' | 'approved' | 'rejected'
  account_state text DEFAULT 'pending',        -- Estado cuenta
  onboarding_completed boolean DEFAULT false,
  onboarding_completed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
```

### 3️⃣ **Tabla `accounts`** (cuenta financiera)
```sql
CREATE TABLE public.accounts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid UNIQUE,                         -- FK a users(id)
  account_type text NOT NULL,                  -- 'delivery_agent'
  balance numeric NOT NULL DEFAULT 0.00,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
```

### 4️⃣ **Tabla `user_preferences`** (preferencias usuario)
```sql
CREATE TABLE public.user_preferences (
  user_id uuid PRIMARY KEY,                    -- FK a users(id)
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);
```

---

## 🔐 PASO 1: Crear Usuario en `auth.users`

### Código Flutter (Referencia)
```dart
final authResponse = await SupabaseAuth.signUp(
  email: emailController.text.trim(),
  password: passwordController.text.trim(),
  userData: {
    'name': nameController.text.trim(),
    'phone': phoneController.text.trim(),
    'address': addressController.text.trim(),
    'role': 'repartidor',  // Se normaliza a 'delivery_agent' en backend
    'lat': selectedLat,
    'lon': selectedLon,
    'address_structured': addressStructured,
    'vehicle_type': selectedVehicleType,
    'vehicle_plate': vehiclePlateController.text.trim(),
    'vehicle_model': vehicleModelController.text.trim(),
    'vehicle_color': vehicleColorController.text.trim(),
    'emergency_contact_name': emergencyContactNameController.text.trim(),
    'emergency_contact_phone': emergencyContactPhoneController.text.trim(),
  },
);

if (authResponse.user == null) {
  throw Exception('No se pudo crear el usuario');
}

final userId = authResponse.user!.id;
```

### Equivalente JavaScript para Web
```javascript
const { data: authData, error: authError } = await supabase.auth.signUp({
  email: email.trim(),
  password: password.trim(),
  options: {
    data: {
      name: name.trim(),
      phone: phone.trim(),
      address: address.trim(),
      role: 'repartidor',  // Se normaliza a 'delivery_agent' en backend
      lat: selectedLat,
      lon: selectedLon,
      address_structured: addressStructured,
      vehicle_type: selectedVehicleType,
      vehicle_plate: vehiclePlate.trim(),
      vehicle_model: vehicleModel.trim() || null,
      vehicle_color: vehicleColor.trim() || null,
      emergency_contact_name: emergencyContactName.trim() || null,
      emergency_contact_phone: emergencyContactPhone.trim() || null,
    },
    emailRedirectTo: `${window.location.origin}/verify-email`
  }
});

if (authError) throw authError;
if (!authData.user) throw new Error('No se pudo crear el usuario');

const userId = authData.user.id;
```

### ⚠️ Importante:
- `supabase.auth.signUp()` crea el usuario en `auth.users` automáticamente
- Envía un **email de verificación** a la dirección proporcionada
- El usuario debe verificar su email antes de poder iniciar sesión
- El `userData` se guarda en `auth.users.raw_user_meta_data` pero **NO crea registros en tablas públicas**

---

## ⚡ PASO 2: Ejecutar Función RPC Atómica

### Función RPC: `register_delivery_agent_atomic`

Esta función RPC hace **TODO** en una sola transacción:
1. Elimina perfiles `client_profiles` auto-creados por triggers (previene conflictos de rol)
2. Crea/actualiza registro en `users` con role='delivery_agent'
3. Crea registro en `delivery_agent_profiles`
4. Crea cuenta financiera en `accounts` (account_type='delivery_agent')
5. Crea preferencias en `user_preferences`

### Código Flutter (Referencia)
```dart
// 1. Subir imágenes a Supabase Storage (opcional)
String? profileImageUrl;
String? idFrontUrl;
String? idBackUrl;
String? vehiclePhotoUrl;
String? vehicleRegistrationUrl;
String? vehicleInsuranceUrl;

if (profileImage != null) {
  profileImageUrl = await StorageService.uploadProfileImage(userId, profileImage);
}
if (idDocumentFront != null) {
  idFrontUrl = await StorageService.uploadIdDocumentFront(userId, idDocumentFront);
}
if (idDocumentBack != null) {
  idBackUrl = await StorageService.uploadIdDocumentBack(userId, idDocumentBack);
}
// ... repetir para otros documentos

// 2. Llamar a función RPC
final rpc = await SupabaseRpc.call(
  'register_delivery_agent_atomic',
  params: {
    'p_user_id': userId,
    'p_email': emailController.text.trim(),
    'p_name': nameController.text.trim(),
    'p_phone': phoneController.text.trim(),
    'p_address': addressController.text.trim(),
    'p_lat': selectedLat,
    'p_lon': selectedLon,
    'p_address_structured': addressStructured,
    'p_vehicle_type': selectedVehicleType,
    'p_vehicle_plate': vehiclePlateController.text.trim(),
    'p_vehicle_model': vehicleModelController.text.trim().isEmpty ? null : vehicleModelController.text.trim(),
    'p_vehicle_color': vehicleColorController.text.trim().isEmpty ? null : vehicleColorController.text.trim(),
    'p_emergency_contact_name': emergencyContactNameController.text.trim().isEmpty ? null : emergencyContactNameController.text.trim(),
    'p_emergency_contact_phone': emergencyContactPhoneController.text.trim().isEmpty ? null : emergencyContactPhoneController.text.trim(),
    'p_place_id': selectedPlaceId,
    'p_profile_image_url': profileImageUrl,
    'p_id_document_front_url': idFrontUrl,
    'p_id_document_back_url': idBackUrl,
    'p_vehicle_photo_url': vehiclePhotoUrl,
    'p_vehicle_registration_url': vehicleRegistrationUrl,
    'p_vehicle_insurance_url': vehicleInsuranceUrl,
  },
);

if (!rpc.success) {
  throw Exception('register_delivery_agent_atomic failed: ${rpc.error}');
}
```

### Equivalente JavaScript para Web
```javascript
// 1. Subir imágenes a Supabase Storage (opcional)
let profileImageUrl = null;
let idFrontUrl = null;
let idBackUrl = null;
let vehiclePhotoUrl = null;
let vehicleRegistrationUrl = null;
let vehicleInsuranceUrl = null;

if (profileImageFile) {
  const { data: uploadData, error: uploadError } = await supabase.storage
    .from('delivery_agents')
    .upload(`${userId}/profile_image.jpg`, profileImageFile);
  if (!uploadError) {
    profileImageUrl = supabase.storage.from('delivery_agents').getPublicUrl(uploadData.path).data.publicUrl;
  }
}

// Repetir para cada imagen/documento...

// 2. Llamar a función RPC
const { data: rpcData, error: rpcError } = await supabase.rpc('register_delivery_agent_atomic', {
  p_user_id: userId,
  p_email: email.trim(),
  p_name: name.trim(),
  p_phone: phone.trim(),
  p_address: address.trim(),
  p_lat: selectedLat,
  p_lon: selectedLon,
  p_address_structured: addressStructured,
  p_vehicle_type: selectedVehicleType,
  p_vehicle_plate: vehiclePlate.trim(),
  p_vehicle_model: vehicleModel.trim() || null,
  p_vehicle_color: vehicleColor.trim() || null,
  p_emergency_contact_name: emergencyContactName.trim() || null,
  p_emergency_contact_phone: emergencyContactPhone.trim() || null,
  p_place_id: selectedPlaceId,
  p_profile_image_url: profileImageUrl,
  p_id_document_front_url: idFrontUrl,
  p_id_document_back_url: idBackUrl,
  p_vehicle_photo_url: vehiclePhotoUrl,
  p_vehicle_registration_url: vehicleRegistrationUrl,
  p_vehicle_insurance_url: vehicleInsuranceUrl,
});

if (rpcError) throw rpcError;
if (!rpcData?.success) throw new Error(rpcData?.error || 'Error desconocido');
```

---

## 🔍 Validación en Tiempo Real (Opcional pero Recomendado)

La app Flutter valida email y teléfono en tiempo real usando funciones RPC:

### RPC: `check_email_availability`
```sql
CREATE OR REPLACE FUNCTION public.check_email_availability(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM public.users WHERE LOWER(email) = LOWER(p_email)
  );
END;
$$;
```

### RPC: `check_phone_availability`
```sql
CREATE OR REPLACE FUNCTION public.check_phone_availability(p_phone text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN NOT EXISTS (
    SELECT 1 FROM public.users WHERE phone = p_phone
  );
END;
$$;
```

### Uso en JavaScript
```javascript
// Validar email
const { data: emailAvailable, error: emailError } = await supabase
  .rpc('check_email_availability', { p_email: email.trim().toLowerCase() });

if (!emailAvailable) {
  alert('Este correo ya está registrado');
  return;
}

// Validar teléfono
const { data: phoneAvailable, error: phoneError } = await supabase
  .rpc('check_phone_availability', { p_phone: phone.trim() });

if (!phoneAvailable) {
  alert('Este teléfono ya está registrado');
  return;
}
```

---

## 📋 Campos Obligatorios vs Opcionales

### ✅ **Campos OBLIGATORIOS:**
- `p_user_id` (uuid de auth.users)
- `p_email`
- `p_name`
- `p_phone`
- `p_address`
- `p_lat` (latitud de dirección)
- `p_lon` (longitud de dirección)
- `p_vehicle_type` (default: 'motocicleta')
- `p_vehicle_plate`
- `p_id_document_front_url` (URL imagen frente INE)
- `p_id_document_back_url` (URL imagen reverso INE)

### 🔹 **Campos OPCIONALES:**
- `p_address_structured` (JSON de Google Places)
- `p_place_id` (ID de Google Places)
- `p_vehicle_model`
- `p_vehicle_color`
- `p_vehicle_photo_url`
- `p_vehicle_registration_url`
- `p_vehicle_insurance_url`
- `p_emergency_contact_name`
- `p_emergency_contact_phone`
- `p_profile_image_url`

---

## 🚀 Flujo Completo Paso a Paso

### 1. **Usuario llena el formulario web** 📝
- Nombre completo
- Email
- Teléfono (con lada)
- Dirección (usando Google Places Autocomplete)
- Contraseña
- Tipo de vehículo
- Placa del vehículo
- Sube fotos: INE frente y reverso (obligatorias)
- Opcionalmente: foto perfil, foto vehículo, documentos vehículo, contacto emergencia

### 2. **Validar campos en tiempo real** ✅
```javascript
// Validar email disponible
const { data: emailOk } = await supabase.rpc('check_email_availability', { p_email: email });
if (!emailOk) { /* mostrar error */ }

// Validar teléfono disponible
const { data: phoneOk } = await supabase.rpc('check_phone_availability', { p_phone: phone });
if (!phoneOk) { /* mostrar error */ }
```

### 3. **Crear usuario en auth.users** 🔐
```javascript
const { data: authData, error: authError } = await supabase.auth.signUp({
  email: email.trim(),
  password: password.trim(),
  options: {
    data: { name, phone, role: 'repartidor' },
    emailRedirectTo: `${window.location.origin}/verify-email`
  }
});

if (authError) throw authError;
const userId = authData.user.id;
```

### 4. **Subir imágenes a Supabase Storage** 📤
```javascript
// Subir frente INE (obligatorio)
const { data: frontData } = await supabase.storage
  .from('delivery_agents')
  .upload(`${userId}/id_front.jpg`, idFrontFile);
const idFrontUrl = supabase.storage.from('delivery_agents').getPublicUrl(frontData.path).data.publicUrl;

// Subir reverso INE (obligatorio)
const { data: backData } = await supabase.storage
  .from('delivery_agents')
  .upload(`${userId}/id_back.jpg`, idBackFile);
const idBackUrl = supabase.storage.from('delivery_agents').getPublicUrl(backData.path).data.publicUrl;

// Repetir para imágenes opcionales...
```

### 5. **Ejecutar RPC atómica** ⚡
```javascript
const { data: rpcData, error: rpcError } = await supabase.rpc('register_delivery_agent_atomic', {
  p_user_id: userId,
  p_email: email.trim(),
  p_name: name.trim(),
  p_phone: phone.trim(),
  p_address: address.trim(),
  p_lat: lat,
  p_lon: lon,
  p_address_structured: addressStructured,
  p_vehicle_type: vehicleType,
  p_vehicle_plate: vehiclePlate.trim(),
  p_vehicle_model: vehicleModel.trim() || null,
  p_vehicle_color: vehicleColor.trim() || null,
  p_emergency_contact_name: emergencyName.trim() || null,
  p_emergency_contact_phone: emergencyPhone.trim() || null,
  p_place_id: placeId,
  p_profile_image_url: profileImageUrl,
  p_id_document_front_url: idFrontUrl,
  p_id_document_back_url: idBackUrl,
  p_vehicle_photo_url: vehiclePhotoUrl,
  p_vehicle_registration_url: vehicleRegistrationUrl,
  p_vehicle_insurance_url: vehicleInsuranceUrl,
});

if (rpcError || !rpcData?.success) {
  throw new Error(rpcData?.error || 'Error al registrar repartidor');
}
```

### 6. **Mostrar mensaje de éxito** ✅
```javascript
alert('✅ Registro exitoso! Revisa tu email para verificar tu cuenta. Nuestro equipo revisará tu solicitud en 24-48 horas.');
window.location.href = '/login';
```

---

## 🛡️ Permisos y Seguridad

### Row Level Security (RLS)
- Las funciones RPC están marcadas como `SECURITY DEFINER`
- Esto significa que **bypassean RLS** y se ejecutan con permisos de propietario
- No necesitas políticas RLS especiales para registro

### Permisos de Ejecución
```sql
GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(...) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.check_email_availability(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_phone_availability(text) TO anon, authenticated;
```

---

## 📦 Estructura de Respuesta de la RPC

### Respuesta exitosa:
```json
{
  "success": true,
  "data": {
    "user_id": "123e4567-e89b-12d3-a456-426614174000",
    "delivery_agent_id": "123e4567-e89b-12d3-a456-426614174000",
    "account_id": "789e4567-e89b-12d3-a456-426614174999"
  },
  "error": null
}
```

### Respuesta con error:
```json
{
  "success": false,
  "data": null,
  "error": "duplicate key value violates unique constraint \"users_email_key\""
}
```

---

## 🎨 Tipos de Vehículo Permitidos

```javascript
const VEHICLE_TYPES = [
  { value: 'bicicleta', label: 'Bicicleta' },
  { value: 'motocicleta', label: 'Motocicleta' },
  { value: 'auto', label: 'Automóvil' },
  { value: 'pie', label: 'A pie' },
  { value: 'otro', label: 'Otro' }
];
```

---

## 📂 Buckets de Supabase Storage

Para subir imágenes, usa el bucket: `delivery_agents`

### Estructura de carpetas sugerida:
```
delivery_agents/
  ├── {userId}/
  │   ├── profile_image.jpg
  │   ├── id_front.jpg
  │   ├── id_back.jpg
  │   ├── vehicle_photo.jpg
  │   ├── vehicle_registration.jpg
  │   └── vehicle_insurance.jpg
```

---

## ✅ Checklist de Implementación Web

- [ ] Crear formulario con campos obligatorios y opcionales
- [ ] Integrar Google Places Autocomplete para dirección
- [ ] Implementar validación en tiempo real de email y teléfono
- [ ] Configurar Supabase Storage bucket `delivery_agents`
- [ ] Implementar función de subida de imágenes
- [ ] Validar formato de imágenes (JPG, PNG, max 5MB)
- [ ] Validar que campos obligatorios tengan valores
- [ ] Llamar a `supabase.auth.signUp()` con userData
- [ ] Capturar `userId` de respuesta de signUp
- [ ] Subir imágenes obligatorias (INE frente y reverso)
- [ ] Subir imágenes opcionales si el usuario las proporciona
- [ ] Llamar a `register_delivery_agent_atomic` con todos los parámetros
- [ ] Manejar errores y mostrar mensajes claros al usuario
- [ ] Redirigir a página de confirmación/login
- [ ] Enviar notificación al admin sobre nuevo registro

---

## 🐛 Troubleshooting Común

### Error: "User already registered"
- El email ya existe en `auth.users`
- Usar validación en tiempo real para prevenirlo

### Error: "duplicate key value violates unique constraint"
- El email o teléfono ya existe en `public.users`
- Verificar con RPCs de validación antes de submit

### Error: "permission denied for function register_delivery_agent_atomic"
- Verificar que la función tenga permisos: `GRANT EXECUTE ... TO anon`

### Error: "Failed to upload image"
- Verificar que el bucket `delivery_agents` existe
- Verificar permisos del bucket (debe permitir uploads de usuarios autenticados)
- Verificar tamaño y formato de imagen

### Error: "Email verification required"
- Esto es normal, el usuario debe verificar su email antes de poder iniciar sesión
- Asegurarse de configurar `emailRedirectTo` correctamente

---

## 🎯 Resumen Final

1. **Crear usuario**: `supabase.auth.signUp()` con email, password y userData
2. **Subir imágenes**: Usar Supabase Storage bucket `delivery_agents`
3. **Ejecutar RPC**: `register_delivery_agent_atomic()` con todos los parámetros
4. **Email verificación**: Usuario recibe email automáticamente
5. **Aprobación admin**: El admin revisa la solicitud y aprueba/rechaza

¡Listo! Con esta guía puedes replicar exactamente el flujo de registro de repartidores en tu sitio web.
