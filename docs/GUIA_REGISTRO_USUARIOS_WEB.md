# 📚 Guía: Registro de Usuarios desde Website (Supabase Auth + RPC Functions)

## 🎯 Propósito

Este documento explica **exactamente cómo la app de Flutter** crea usuarios en `auth.users` de Supabase y ejecuta funciones RPC atómicas para crear los registros relacionados en las tablas `public.*`. 

**Úsalo como referencia para implementar el mismo flujo en tu website.**

---

## 📋 Tabla de Contenidos

1. [Visión General del Flujo](#-visión-general-del-flujo)
2. [Paso 1: Crear Usuario en auth.users](#-paso-1-crear-usuario-en-authusers)
3. [Paso 2: Funciones RPC Atómicas](#-paso-2-funciones-rpc-atómicas)
4. [Ejemplo: Registro de Restaurante](#-ejemplo-registro-de-restaurante)
5. [Ejemplo: Registro de Repartidor](#-ejemplo-registro-de-repartidor)
6. [Ejemplo: Registro de Cliente](#-ejemplo-registro-de-cliente)
7. [Estructura de Respuestas](#-estructura-de-respuestas)
8. [Manejo de Errores](#-manejo-de-errores)
9. [Notas Importantes](#-notas-importantes)

---

## 🔄 Visión General del Flujo

El proceso de registro sigue **DOS PASOS ATÓMICOS**:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  PASO 1: Crear auth.user                                   │
│  ────────────────────────────────────────────────────       │
│  • Supabase.auth.signUp(email, password, data)             │
│  • Envía email de verificación automáticamente             │
│  • Retorna user_id (UUID)                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  PASO 2: Ejecutar RPC Function Atómica                     │
│  ─────────────────────────────────────────────────          │
│  • register_restaurant_atomic(user_id, ...)                │
│  • register_delivery_agent_atomic(user_id, ...)            │
│  • ensure_user_profile_public(user_id, ...)                │
│                                                             │
│  Crea ATÓMICAMENTE:                                         │
│  ✓ public.users (perfil)                                   │
│  ✓ public.restaurants o delivery_agent_profiles            │
│  ✓ public.accounts (cuenta financiera)                     │
│  ✓ public.user_preferences (preferencias)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**⚠️ IMPORTANTE:** 
- El PASO 1 crea el usuario en `auth.users` (sistema de autenticación)
- El PASO 2 crea TODOS los registros relacionados de forma ATÓMICA (en una sola transacción)
- Si el PASO 2 falla, el usuario quedará en auth.users pero sin perfil completo

---

## 🔐 Paso 1: Crear Usuario en auth.users

### Código de la App (Flutter/Dart)

```dart
// lib/supabase/supabase_config.dart - líneas 162-275

static Future<AuthResponse> signUp({
  required String email,
  required String password,
  Map<String, dynamic>? userData,
}) async {
  // 1. Configurar URL de redirect (para verificación de email)
  String redirectUrl = 'https://tu-dominio.com';
  
  // 2. Crear usuario en auth.users
  final response = await SupabaseConfig.auth.signUp(
    email: email,
    password: password,
    data: userData,  // Metadata adicional (nombre, teléfono, etc.)
    emailRedirectTo: redirectUrl,
  );

  if (response.user == null) {
    throw Exception('No se pudo crear el usuario en auth.users');
  }

  return response;
}
```

### Equivalente para Web (JavaScript/TypeScript)

```javascript
// Tu website
const { data, error } = await supabase.auth.signUp({
  email: 'restaurant@example.com',
  password: 'Password123!',
  options: {
    data: {
      name: 'Gorditas LAura',
      phone: '+526565731023',
      address: 'Calle Principal 123',
      role: 'restaurant',
      lat: 31.7764,
      lon: -106.4245,
      address_structured: {
        street: 'Calle Principal',
        number: '123',
        city: 'Juárez',
        state: 'Chihuahua',
        country: 'México'
      }
    },
    emailRedirectTo: 'https://tu-website.com/confirm'
  }
});

if (error) throw error;

const userId = data.user.id; // ← Este ID lo usarás en el PASO 2
console.log('✅ Usuario creado en auth.users:', userId);
```

### ¿Qué hace este paso?

1. ✅ Crea el registro en `auth.users` de Supabase
2. ✅ Hashea la contraseña automáticamente (bcrypt)
3. ✅ Envía email de verificación al usuario
4. ✅ Guarda el `metadata` en `auth.users.raw_user_meta_data`
5. ✅ Retorna el `user_id` (UUID) necesario para el PASO 2

---

## 🔧 Paso 2: Funciones RPC Atómicas

Las **RPC Functions** (Remote Procedure Calls) son funciones SQL que se ejecutan con privilegios elevados (`SECURITY DEFINER`) y permiten crear múltiples registros en una sola transacción.

### ¿Por qué usar RPCs?

- ✅ **Atómicas**: Todo o nada (si falla algo, se revierte todo)
- ✅ **Seguras**: Bypassean RLS (Row Level Security) de forma controlada
- ✅ **Simples**: Una sola llamada desde el cliente
- ✅ **Mantenibles**: Lógica compleja en el backend, no en el cliente

---

## 🍔 Ejemplo: Registro de Restaurante

### Código de la App (Flutter/Dart)

```dart
// lib/screens/public/restaurant_registration_screen.dart - líneas 146-265

Future<void> _submitRegistration() async {
  // PASO 1: Crear usuario en auth.users
  final authResponse = await SupabaseAuth.signUp(
    email: _emailController.text.trim(),
    password: _passwordController.text.trim(),
    userData: {
      'name': _ownerNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'role': 'restaurant',
      'lat': _selectedLat,
      'lon': _selectedLon,
      'address_structured': _addressStructured,
    },
  );

  if (authResponse.user == null) {
    throw Exception('No se pudo crear el usuario');
  }

  final userId = authResponse.user!.id;
  print('✅ Usuario creado: $userId');

  // PASO 2: Llamar RPC atómica
  final result = await SupabaseConfig.client.rpc(
    'register_restaurant_atomic',  // ← Nombre de la función SQL
    params: {
      'p_user_id': userId,
      'p_restaurant_name': _restaurantNameController.text.trim(),
      'p_phone': _phoneController.text.trim(),
      'p_address': _addressController.text.trim(),
      'p_location_lat': _selectedLat,
      'p_location_lon': _selectedLon,
      'p_location_place_id': _selectedPlaceId,
      'p_address_structured': _addressStructured,
    },
  );

  if (result == null || result['success'] != true) {
    throw Exception(result?['error'] ?? 'Unknown error');
  }

  print('✅ Restaurant created: ${result['restaurant_id']}');
  print('✅ Account created: ${result['account_id']}');
}
```

### Equivalente para Web (JavaScript/TypeScript)

```javascript
// 1. PASO 1: Crear usuario en auth.users
const { data: authData, error: authError } = await supabase.auth.signUp({
  email: formData.email,
  password: formData.password,
  options: {
    data: {
      name: formData.ownerName,
      phone: formData.phone,
      address: formData.address,
      role: 'restaurant',
      lat: formData.lat,
      lon: formData.lon,
      address_structured: formData.addressStructured
    },
    emailRedirectTo: 'https://tu-website.com/confirm'
  }
});

if (authError) throw authError;

const userId = authData.user.id;
console.log('✅ Usuario creado:', userId);

// 2. PASO 2: Llamar RPC atómica
const { data: rpcData, error: rpcError } = await supabase.rpc(
  'register_restaurant_atomic',  // ← Nombre de la función SQL
  {
    p_user_id: userId,
    p_restaurant_name: formData.restaurantName,
    p_phone: formData.phone,
    p_address: formData.address,
    p_location_lat: formData.lat,
    p_location_lon: formData.lon,
    p_location_place_id: formData.placeId || null,
    p_address_structured: formData.addressStructured || null
  }
);

if (rpcError) throw rpcError;
if (!rpcData.success) throw new Error(rpcData.error);

console.log('✅ Restaurante creado:', rpcData.restaurant_id);
console.log('✅ Cuenta creada:', rpcData.account_id);
```

### Función SQL (Supabase)

```sql
-- sql_migrations/FIX_COMPLETE_RESTAURANT_REGISTRATION.sql

CREATE OR REPLACE FUNCTION public.register_restaurant_atomic(
  p_user_id uuid,
  p_restaurant_name text,
  p_phone text,
  p_address text,
  p_location_lat double precision,
  p_location_lon double precision,
  p_location_place_id text DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER  -- ← Ejecuta con privilegios elevados
SET search_path = public
AS $$
DECLARE
  v_restaurant_id uuid;
  v_account_id uuid;
BEGIN
  -- 1. Validar que el usuario existe
  IF NOT EXISTS(SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User not found'
    );
  END IF;

  -- 2. Crear registro en public.restaurants
  INSERT INTO public.restaurants (
    user_id,
    name,
    phone,
    address,
    location_lat,
    location_lon,
    location_place_id,
    address_structured,
    status,
    online,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_restaurant_name,
    p_phone,
    p_address,
    p_location_lat,
    p_location_lon,
    p_location_place_id,
    p_address_structured,
    'pending',
    false,
    now(),
    now()
  )
  RETURNING id INTO v_restaurant_id;

  -- 3. Crear cuenta financiera en public.accounts
  INSERT INTO public.accounts (
    user_id,
    account_type,
    balance,
    created_at,
    updated_at
  )
  VALUES (
    p_user_id,
    'restaurant',
    0.00,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    account_type = EXCLUDED.account_type,
    updated_at = now()
  RETURNING id INTO v_account_id;

  -- 4. Actualizar rol en public.users
  UPDATE public.users
  SET 
    role = 'restaurant',
    updated_at = now()
  WHERE id = p_user_id;

  -- 5. Retornar éxito con IDs
  RETURN jsonb_build_object(
    'success', true,
    'restaurant_id', v_restaurant_id,
    'account_id', v_account_id
  );

EXCEPTION WHEN OTHERS THEN
  -- Si algo falla, todo se revierte automáticamente
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

-- Dar permisos de ejecución
GRANT EXECUTE ON FUNCTION public.register_restaurant_atomic(...) 
TO anon, authenticated;
```

### ¿Qué crea esta función?

La RPC `register_restaurant_atomic` crea ATÓMICAMENTE:

1. ✅ `public.users` → Actualiza el rol a 'restaurant'
2. ✅ `public.restaurants` → Registro del restaurante (status='pending')
3. ✅ `public.accounts` → Cuenta financiera (balance=0.00, type='restaurant')

**Si cualquier paso falla, TODA la transacción se revierte.**

---

## 🏍️ Ejemplo: Registro de Repartidor

### Código de la App (Flutter/Dart)

```dart
// lib/screens/public/delivery_agent_registration_screen.dart - líneas 291-410

Future<void> _submitRegistration() async {
  // PASO 1: Crear usuario en auth.users
  final authResponse = await SupabaseAuth.signUp(
    email: _emailController.text.trim(),
    password: _passwordController.text.trim(),
    userData: {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'role': 'repartidor',  // ← Se normaliza a 'delivery_agent'
      'lat': _selectedLat,
      'lon': _selectedLon,
      'vehicle_type': _selectedVehicleType,
      'vehicle_plate': _vehiclePlateController.text.trim(),
      // ... más datos del vehículo
    },
  );

  final userId = authResponse.user!.id;

  // PASO 2: Subir documentos a Storage
  String? idFrontUrl;
  String? idBackUrl;
  if (_idDocumentFront != null) {
    idFrontUrl = await StorageService.uploadIdDocumentFront(
      userId, 
      _idDocumentFront!
    );
  }
  // ... más uploads

  // PASO 3: Llamar RPC atómica
  final rpc = await SupabaseRpc.call(
    'register_delivery_agent_atomic',
    params: {
      'p_user_id': userId,
      'p_email': _emailController.text.trim(),
      'p_name': _nameController.text.trim(),
      'p_phone': _phoneController.text.trim(),
      'p_address': _addressController.text.trim(),
      'p_lat': _selectedLat,
      'p_lon': _selectedLon,
      'p_vehicle_type': _selectedVehicleType,
      'p_vehicle_plate': _vehiclePlateController.text.trim(),
      'p_id_document_front_url': idFrontUrl,
      'p_id_document_back_url': idBackUrl,
      // ... más URLs de documentos
    },
  );

  if (!rpc.success) {
    throw Exception(rpc.error);
  }
}
```

### Equivalente para Web (JavaScript/TypeScript)

```javascript
// 1. PASO 1: Crear usuario en auth.users
const { data: authData, error: authError } = await supabase.auth.signUp({
  email: formData.email,
  password: formData.password,
  options: {
    data: {
      name: formData.name,
      phone: formData.phone,
      role: 'delivery_agent',
      vehicle_type: formData.vehicleType
    }
  }
});

if (authError) throw authError;
const userId = authData.user.id;

// 2. PASO 2: Subir documentos a Supabase Storage
const uploadDocument = async (file, path) => {
  const { data, error } = await supabase.storage
    .from('documents')
    .upload(`${userId}/${path}`, file);
  
  if (error) throw error;
  
  const { data: publicUrl } = supabase.storage
    .from('documents')
    .getPublicUrl(data.path);
  
  return publicUrl.publicUrl;
};

const idFrontUrl = await uploadDocument(formData.idFront, 'id_front.jpg');
const idBackUrl = await uploadDocument(formData.idBack, 'id_back.jpg');

// 3. PASO 3: Llamar RPC atómica
const { data: rpcData, error: rpcError } = await supabase.rpc(
  'register_delivery_agent_atomic',
  {
    p_user_id: userId,
    p_email: formData.email,
    p_name: formData.name,
    p_phone: formData.phone,
    p_address: formData.address,
    p_lat: formData.lat,
    p_lon: formData.lon,
    p_vehicle_type: formData.vehicleType,
    p_vehicle_plate: formData.vehiclePlate,
    p_vehicle_model: formData.vehicleModel || null,
    p_id_document_front_url: idFrontUrl,
    p_id_document_back_url: idBackUrl
  }
);

if (rpcError) throw rpcError;
if (!rpcData.success) throw new Error(rpcData.error);

console.log('✅ Repartidor registrado:', rpcData.data.delivery_agent_id);
```

### Función SQL (Supabase)

```sql
-- supabase_scripts/2025-10-23_register_delivery_agent_atomic.sql

CREATE OR REPLACE FUNCTION public.register_delivery_agent_atomic(
  p_user_id uuid,
  p_email text,
  p_name text,
  p_phone text DEFAULT '',
  p_address text DEFAULT '',
  p_lat double precision DEFAULT NULL,
  p_lon double precision DEFAULT NULL,
  p_address_structured jsonb DEFAULT NULL,
  p_vehicle_type text DEFAULT 'motocicleta',
  p_vehicle_plate text DEFAULT '',
  p_vehicle_model text DEFAULT NULL,
  p_vehicle_color text DEFAULT NULL,
  p_id_document_front_url text DEFAULT NULL,
  p_id_document_back_url text DEFAULT NULL
  -- ... más parámetros
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_delivery_agent_id uuid;
  v_account_id uuid;
BEGIN
  -- 1. Limpiar perfiles de cliente creados automáticamente
  DELETE FROM public.client_profiles WHERE user_id = p_user_id;
  DELETE FROM public.accounts 
  WHERE user_id = p_user_id AND account_type = 'client';

  -- 2. Crear/actualizar perfil en public.users
  INSERT INTO public.users (
    id, email, name, phone, address, role, 
    lat, lon, address_structured, email_confirm,
    created_at, updated_at
  ) VALUES (
    p_user_id, p_email, p_name, p_phone, p_address,
    'delivery_agent', p_lat, p_lon, p_address_structured,
    false, now(), now()
  )
  ON CONFLICT (id) DO UPDATE
    SET role = 'delivery_agent',
        name = EXCLUDED.name,
        phone = EXCLUDED.phone,
        updated_at = now();

  -- 3. Crear perfil de repartidor
  INSERT INTO public.delivery_agent_profiles (
    user_id,
    vehicle_type,
    vehicle_plate,
    vehicle_model,
    vehicle_color,
    id_document_front_url,
    id_document_back_url,
    status,
    account_state,
    onboarding_completed,
    created_at,
    updated_at
  ) VALUES (
    p_user_id,
    p_vehicle_type,
    p_vehicle_plate,
    p_vehicle_model,
    p_vehicle_color,
    p_id_document_front_url,
    p_id_document_back_url,
    'pending',
    'pending',
    false,
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
    SET vehicle_type = EXCLUDED.vehicle_type,
        vehicle_plate = EXCLUDED.vehicle_plate,
        updated_at = now()
  RETURNING user_id INTO v_delivery_agent_id;

  -- 4. Crear cuenta financiera
  INSERT INTO public.accounts (
    user_id, account_type, balance, created_at, updated_at
  )
  VALUES (p_user_id, 'delivery_agent', 0.0, now(), now())
  ON CONFLICT (user_id, account_type) DO UPDATE
    SET updated_at = now()
  RETURNING id INTO v_account_id;

  -- 5. Crear preferencias de usuario
  INSERT INTO public.user_preferences (user_id, created_at, updated_at)
  VALUES (p_user_id, now(), now())
  ON CONFLICT (user_id) DO NOTHING;

  -- 6. Retornar éxito
  RETURN jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'user_id', p_user_id,
      'delivery_agent_id', v_delivery_agent_id,
      'account_id', v_account_id
    )
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;
```

### ¿Qué crea esta función?

La RPC `register_delivery_agent_atomic` crea ATÓMICAMENTE:

1. ✅ `public.users` → Perfil con rol='delivery_agent'
2. ✅ `public.delivery_agent_profiles` → Datos del vehículo y documentos
3. ✅ `public.accounts` → Cuenta financiera (type='delivery_agent')
4. ✅ `public.user_preferences` → Preferencias del usuario

---

## 👤 Ejemplo: Registro de Cliente

Los clientes (comensales) tienen un flujo más simple porque **NO** necesitan una RPC atómica personalizada. El registro se hace directamente con `signUp` y los triggers de base de datos crean automáticamente los registros relacionados.

### Código de la App (Flutter/Dart)

```dart
// lib/screens/auth/register_screen.dart - líneas 143-249

Future<void> _register() async {
  // PASO ÚNICO: Crear usuario en auth.users
  // El trigger de DB crea automáticamente:
  // - public.users
  // - public.client_profiles
  // - public.accounts
  // - public.user_preferences
  
  final response = await SupabaseAuth.signUp(
    email: _emailController.text.trim(),
    password: _passwordController.text,
    userData: {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
      'role': 'client',  // ← Rol de cliente
      'lat': _selectedLat,
      'lon': _selectedLon,
      'address_structured': _addressStructured,
    },
  );

  // Opcional: Asegurar perfil si el trigger falló
  try {
    await DoaRepartosService.upsertUserProfile(
      response.user!.id, 
      _emailController.text.trim(),
      userData,
    );
  } catch (e) {
    print('⚠️ Profile creation warning: $e');
  }
}
```

### Equivalente para Web (JavaScript/TypeScript)

```javascript
// Registro de cliente (más simple)
const { data, error } = await supabase.auth.signUp({
  email: formData.email,
  password: formData.password,
  options: {
    data: {
      name: formData.name,
      phone: formData.phone,
      address: formData.address,
      role: 'client',
      lat: formData.lat,
      lon: formData.lon
    }
  }
});

if (error) throw error;

console.log('✅ Cliente registrado:', data.user.id);

// Los triggers de Supabase crean automáticamente:
// - public.users
// - public.client_profiles
// - public.accounts (type='client')
// - public.user_preferences
```

---

## 📊 Estructura de Respuestas

### Respuesta Exitosa (RPC)

```json
{
  "success": true,
  "restaurant_id": "550e8400-e29b-41d4-a716-446655440000",
  "account_id": "660e8400-e29b-41d4-a716-446655440001",
  "data": {
    "user_id": "770e8400-e29b-41d4-a716-446655440002",
    "delivery_agent_id": "880e8400-e29b-41d4-a716-446655440003"
  }
}
```

### Respuesta con Error (RPC)

```json
{
  "success": false,
  "error": "Restaurant name already exists",
  "error_code": "DUPLICATE_NAME",
  "data": null
}
```

### Respuesta de auth.signUp

```javascript
{
  user: {
    id: "770e8400-e29b-41d4-a716-446655440002",
    email: "restaurant@example.com",
    email_confirmed_at: null,  // ← null hasta que verifique el email
    created_at: "2025-01-01T12:00:00Z",
    user_metadata: {
      name: "Gorditas LAura",
      phone: "+526565731023",
      role: "restaurant"
    }
  },
  session: null  // ← null hasta verificar email
}
```

---

## ⚠️ Manejo de Errores

### Errores Comunes

#### 1. Usuario ya existe

```javascript
// Error de Supabase Auth
{
  message: "User already registered",
  status: 400
}
```

**Solución:** Validar que el email no esté registrado antes de llamar a signUp

```javascript
const { data } = await supabase
  .from('users')
  .select('id')
  .eq('email', formData.email)
  .single();

if (data) {
  throw new Error('Este email ya está registrado');
}
```

#### 2. Nombre de restaurante duplicado

```json
{
  "success": false,
  "error": "Restaurant name already exists",
  "error_code": "DUPLICATE_NAME"
}
```

**Solución:** Validar disponibilidad del nombre ANTES de registrar

```javascript
const { data } = await supabase
  .from('restaurants')
  .select('id')
  .eq('name', formData.restaurantName)
  .single();

if (data) {
  throw new Error('Este nombre de restaurante ya existe');
}
```

#### 3. Contraseña débil

```javascript
{
  message: "Password should be at least 6 characters",
  status: 422
}
```

**Solución:** Validar contraseña en el frontend

```javascript
const validatePassword = (password) => {
  if (password.length < 8) {
    return 'Mínimo 8 caracteres';
  }
  if (!/[A-Z]/.test(password)) {
    return 'Debe contener al menos una mayúscula';
  }
  if (!/[0-9]/.test(password)) {
    return 'Debe contener al menos un número';
  }
  return null;
};
```

#### 4. Coordenadas faltantes

```json
{
  "success": false,
  "error": "Location coordinates are required"
}
```

**Solución:** Asegurar que lat/lon NO sean null

```javascript
if (!formData.lat || !formData.lon) {
  throw new Error('Debes seleccionar una ubicación en el mapa');
}
```

### Patrón de Manejo de Errores Recomendado

```javascript
const registerRestaurant = async (formData) => {
  try {
    // PASO 1: Validaciones previas
    await validateForm(formData);
    
    // PASO 2: Crear auth user
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: formData.email,
      password: formData.password,
      options: { data: { ...formData, role: 'restaurant' } }
    });
    
    if (authError) throw authError;
    
    const userId = authData.user.id;
    
    // PASO 3: Llamar RPC atómica
    const { data: rpcData, error: rpcError } = await supabase.rpc(
      'register_restaurant_atomic',
      { p_user_id: userId, ...formData }
    );
    
    if (rpcError) throw rpcError;
    if (!rpcData.success) throw new Error(rpcData.error);
    
    // ✅ Éxito
    return {
      success: true,
      userId: userId,
      restaurantId: rpcData.restaurant_id
    };
    
  } catch (error) {
    console.error('❌ Error registrando restaurante:', error);
    
    // Retornar error user-friendly
    let message = 'Error al registrar restaurante';
    
    if (error.message.includes('already registered')) {
      message = 'Este email ya está registrado';
    } else if (error.message.includes('already exists')) {
      message = 'Este nombre de restaurante ya existe';
    } else if (error.message.includes('User not found')) {
      message = 'Error creando usuario. Intenta de nuevo.';
    }
    
    throw new Error(message);
  }
};
```

---

## 📌 Notas Importantes

### 1. Verificación de Email

**⚠️ MUY IMPORTANTE:** 
- `auth.signUp()` envía automáticamente un email de verificación
- El usuario NO puede iniciar sesión hasta verificar el email
- Configura la URL de redirect en Supabase Dashboard:
  - `Authentication` → `URL Configuration` → `Redirect URLs`
  - Añade: `https://tu-website.com/confirm`

### 2. Normalización de Roles

La app normaliza roles a inglés:

```dart
// lib/supabase/supabase_config.dart - líneas 136-160

static String normalizeRoleString(dynamic role) {
  final r = role?.toString().toLowerCase().trim() ?? '';
  switch (r) {
    case 'client':
    case 'cliente':
    case 'user':
      return 'client';
    case 'restaurant':
    case 'restaurante':
      return 'restaurant';
    case 'delivery':
    case 'repartidor':
    case 'delivery_agent':
      return 'delivery_agent';
    default:
      return 'client';
  }
}
```

**Usa siempre los valores normalizados:**
- ✅ `'client'`
- ✅ `'restaurant'`
- ✅ `'delivery_agent'`
- ✅ `'admin'`

### 3. Campos Obligatorios vs Opcionales

#### Restaurantes (Obligatorios)
```javascript
{
  p_user_id: UUID,            // ← Del PASO 1
  p_restaurant_name: string,  // ← Mínimo 3 caracteres
  p_phone: string,
  p_address: string,
  p_location_lat: number,     // ← Coordenadas obligatorias
  p_location_lon: number
}
```

#### Repartidores (Obligatorios)
```javascript
{
  p_user_id: UUID,
  p_email: string,
  p_name: string,
  p_phone: string,
  p_address: string,
  p_vehicle_type: string,
  p_vehicle_plate: string,
  p_id_document_front_url: string,  // ← Documento obligatorio
  p_id_document_back_url: string    // ← Documento obligatorio
}
```

### 4. Permissions en Supabase

Asegúrate de que las funciones RPC tengan permisos correctos:

```sql
-- Dar permisos a usuarios anónimos y autenticados
GRANT EXECUTE ON FUNCTION public.register_restaurant_atomic(...) 
TO anon, authenticated;

GRANT EXECUTE ON FUNCTION public.register_delivery_agent_atomic(...) 
TO anon, authenticated;
```

### 5. Transacciones Atómicas

Las funciones RPC usan transacciones implícitas:

```sql
-- Si CUALQUIER paso falla, TODO se revierte
CREATE OR REPLACE FUNCTION public.register_restaurant_atomic(...)
AS $$
BEGIN
  INSERT INTO users ...;      -- Paso 1
  INSERT INTO restaurants ...; -- Paso 2
  INSERT INTO accounts ...;    -- Paso 3
  RETURN jsonb_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
  -- Automáticamente hace ROLLBACK de todos los pasos
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
```

### 6. Testing

Puedes probar las RPCs directamente desde el Supabase Dashboard:

1. Ve a `SQL Editor`
2. Ejecuta:

```sql
SELECT public.register_restaurant_atomic(
  p_user_id := 'UUID-del-usuario',
  p_restaurant_name := 'Test Restaurant',
  p_phone := '+526561234567',
  p_address := 'Test Address 123',
  p_location_lat := 31.7764,
  p_location_lon := -106.4245
);
```

---

## 🎯 Resumen Rápido

### Para implementar en tu website:

1. **Instala Supabase JS Client:**
   ```bash
   npm install @supabase/supabase-js
   ```

2. **Inicializa el cliente:**
   ```javascript
   import { createClient } from '@supabase/supabase-js'
   
   const supabase = createClient(
     'TU_SUPABASE_URL',
     'TU_SUPABASE_ANON_KEY'
   )
   ```

3. **Usa el flujo de 2 pasos:**
   ```javascript
   // PASO 1: auth.signUp()
   const { data: authData } = await supabase.auth.signUp({ ... });
   
   // PASO 2: rpc('register_XXX_atomic')
   const { data: rpcData } = await supabase.rpc('register_restaurant_atomic', { 
     p_user_id: authData.user.id,
     ...params 
   });
   ```

4. **Maneja errores apropiadamente**
5. **Redirige al usuario a verificar su email**

---

## 📚 Referencias

- **Código de Flutter:** 
  - `lib/supabase/supabase_config.dart`
  - `lib/screens/public/restaurant_registration_screen.dart`
  - `lib/screens/public/delivery_agent_registration_screen.dart`

- **Funciones SQL:**
  - `sql_migrations/FIX_COMPLETE_RESTAURANT_REGISTRATION.sql`
  - `supabase_scripts/2025-10-23_register_delivery_agent_atomic.sql`

- **Documentación Supabase:**
  - [Auth Methods](https://supabase.com/docs/reference/javascript/auth-signup)
  - [Database Functions](https://supabase.com/docs/guides/database/functions)
  - [RPC (Remote Procedure Call)](https://supabase.com/docs/reference/javascript/rpc)

---

## 🤝 Dudas y Sugerencias

### ¿Tienes dudas sobre:

- ✅ Cómo subir documentos a Supabase Storage?
- ✅ Cómo validar campos en tiempo real (email/teléfono)?
- ✅ Cómo manejar la verificación de email?
- ✅ Cómo implementar Google Sign-In?
- ✅ Cómo crear una función RPC custom para tu caso de uso?

**Contacta al equipo de desarrollo y te ayudaremos! 🚀**

---

**Última actualización:** 2025-01-01  
**Versión:** 1.0  
**Autor:** Doña Repartos Dev Team
