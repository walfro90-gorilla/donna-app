import 'package:flutter/foundation.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Servicio para validar disponibilidad de datos únicos en la base de datos
class ValidationService {
  /// Verificar si un email ya está en uso
  static Future<bool> isEmailAvailable(String email) async {
    try {
      final trimmed = email.trim().toLowerCase();
      if (trimmed.isEmpty) return false;

      debugPrint('🔍 [VALIDATION] Checking email availability: $trimmed');

      // Usar RPC function para bypass RLS
      final response = await SupabaseConfig.client
          .rpc('check_email_availability', params: {'p_email': trimmed});

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      debugPrint('   - Email ${isAvailable ? "DISPONIBLE ✅" : "YA EXISTE ❌"}');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking email: $e');
      // En caso de error de red/permisos, bloquear registro (más seguro)
      return false;
    }
  }

  /// Verificar si un teléfono ya está en uso
  static Future<bool> isPhoneAvailable(String phone) async {
    try {
      final trimmed = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
      if (trimmed.isEmpty) return false;

      debugPrint('🔍 [VALIDATION] Checking phone availability: $trimmed');

      // Usar RPC function para bypass RLS
      final response = await SupabaseConfig.client
          .rpc('check_phone_availability', params: {'p_phone': trimmed});

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      debugPrint('   - Phone ${isAvailable ? "DISPONIBLE ✅" : "YA EXISTE ❌"}');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking phone: $e');
      // En caso de error de red/permisos, bloquear registro (más seguro)
      return false;
    }
  }

  /// Verificar si un nombre de restaurante ya está en uso
  static Future<bool> isRestaurantNameAvailable(String name) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return false;

      debugPrint('🔍 [VALIDATION] Checking restaurant name availability: $trimmed');

      // Usar RPC function para bypass RLS
      final response = await SupabaseConfig.client
          .rpc('check_restaurant_name_availability', params: {'p_name': trimmed});

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      debugPrint('   - Restaurant name ${isAvailable ? "DISPONIBLE ✅" : "YA EXISTE ❌"}');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking restaurant name: $e');
      // En caso de error de red/permisos, bloquear registro (más seguro)
      return false;
    }
  }

  /// Verificar disponibilidad de NOMBRE de restaurante excluyendo un id específico (para updates)
  static Future<bool> isRestaurantNameAvailableForUpdate(String name, {String? excludeRestaurantId}) async {
    try {
      final trimmed = name.trim();
      if (trimmed.isEmpty) return false;

      debugPrint('🔍 [VALIDATION] Checking restaurant name available-for-update: $trimmed (exclude=${excludeRestaurantId ?? 'NULL'})');

      final response = await SupabaseConfig.client.rpc(
        'check_restaurant_name_available_for_update',
        params: {
          'p_name': trimmed,
          'p_exclude_id': excludeRestaurantId,
        },
      );

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking restaurant name (update): $e');
      return false;
    }
  }

  /// Verificar si un teléfono ya está en uso en restaurants
  static Future<bool> isRestaurantPhoneAvailable(String phone) async {
    try {
      final trimmed = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
      debugPrint('🔍 [VALIDATION] Checking restaurant phone availability: $trimmed');

      final response = await SupabaseConfig.client.rpc(
        'check_restaurant_phone_availability',
        params: {'p_phone': trimmed},
      );

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking restaurant phone: $e');
      return false;
    }
  }

  /// Verificar disponibilidad de TELÉFONO en restaurants excluyendo un id (para updates)
  static Future<bool> isRestaurantPhoneAvailableForUpdate(String phone, {String? excludeRestaurantId}) async {
    try {
      final trimmed = phone.trim().replaceAll(RegExp(r'[^\d+]'), '');
      debugPrint('🔍 [VALIDATION] Checking restaurant phone available-for-update: $trimmed (exclude=${excludeRestaurantId ?? 'NULL'})');

      final response = await SupabaseConfig.client.rpc(
        'check_restaurant_phone_available_for_update',
        params: {
          'p_phone': trimmed,
          'p_exclude_id': excludeRestaurantId,
        },
      );

      final isAvailable = response == true;
      debugPrint('   - RPC response: $response (${response.runtimeType})');
      return isAvailable;
    } catch (e) {
      debugPrint('❌ [VALIDATION] Error checking restaurant phone (update): $e');
      return false;
    }
  }

  /// Validar email con debounce (para validación en tiempo real)
  static Future<String?> validateEmailRealtime(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return 'El correo es requerido';
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      return 'Ingresa un correo válido';
    }

    final isAvailable = await isEmailAvailable(value);
    if (!isAvailable) {
      return 'Este correo ya está registrado';
    }

    return null;
  }

  /// Validar teléfono con debounce (para validación en tiempo real)
  static Future<String?> validatePhoneRealtime(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return 'El teléfono es requerido';
    }

    if (value.trim().length < 8) {
      return 'El teléfono debe tener al menos 8 dígitos';
    }

    final isAvailable = await isPhoneAvailable(value);
    if (!isAvailable) {
      return 'Este teléfono ya está registrado';
    }

    return null;
  }

  /// Validar teléfono de restaurante con debounce (en tabla restaurants)
  static Future<String?> validateRestaurantPhoneRealtime(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return null; // opcional
    }
    final digitsOnly = value.replaceAll(RegExp(r'[^\d+]'), '');
    if (digitsOnly.length < 8) {
      return 'El teléfono debe tener al menos 8 dígitos';
    }
    final isAvailable = await isRestaurantPhoneAvailable(value);
    if (!isAvailable) {
      return 'Este teléfono ya está registrado para otro restaurante';
    }
    return null;
  }

  /// Validar nombre de restaurante con debounce
  static Future<String?> validateRestaurantNameRealtime(String? value) async {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre del restaurante es requerido';
    }

    if (value.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres';
    }

    final isAvailable = await isRestaurantNameAvailable(value);
    if (!isAvailable) {
      return 'Este nombre de restaurante ya está en uso';
    }

    return null;
  }
}

/// Widget Helper para TextFormField con validación asíncrona debounced
class DebouncedValidator {
  final Future<String?> Function(String?) validator;
  final Duration delay;

  DebouncedValidator({
    required this.validator,
    this.delay = const Duration(milliseconds: 800),
  });

  Future<String?> Function(String?) get call {
    DateTime? lastChangeTime;
    
    return (String? value) async {
      final now = DateTime.now();
      lastChangeTime = now;
      
      // Esperar el delay
      await Future.delayed(delay);
      
      // Si hubo otro cambio durante el delay, cancelar
      if (lastChangeTime != now) {
        return null;
      }
      
      // Ejecutar validación
      return await validator(value);
    };
  }
}
