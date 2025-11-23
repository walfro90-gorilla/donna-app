import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Service for Google Places (via Supabase Edge Function proxy)
/// Supports: Autocomplete, Place Details, Geocoding, Reverse Geocoding, Address Validation
class PlacesService {
  static String? lastError;

  static String newSessionToken() {
    final rnd = Random();
    final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final r = List<int>.generate(8, (_) => rnd.nextInt(36)).map((n) => n.toRadixString(36)).join();
    return 's_${millis}_$r';
  }

  /// Autocomplete: buscar direcciones mientras el usuario escribe
  ///
  /// Robusto a diferentes formatos de payload del Edge Function
  /// - Google nativo: { predictions: [ { description, place_id, ... } ], status }
  /// - Proxy custom: { results: [ ... ], status }
  /// - Otros: { items: [ ... ] }
  static Future<List<Map<String, dynamic>>> autocomplete(
    String query, {
    String? sessionToken,
    String language = 'es',
    String? components,
  }) async {
    try {
      final trimmed = query.trim();
      if (trimmed.isEmpty) {
        debugPrint('🔎 [PLACES] Autocomplete skipped: empty query');
        return [];
      }

      final body = {
        'action': 'autocomplete',
        'input': trimmed,
        'language': language,
        'types': 'geocode',
        if (sessionToken != null) 'sessionToken': sessionToken,
        if (components != null && components.isNotEmpty) 'components': components,
      };

      lastError = null;
      debugPrint('📤 [PLACES] Autocomplete request => $body');
      final response = await SupabaseConfig.client.functions.invoke('google-maps-proxy', body: body);
      final res = response.data;
      debugPrint('📥 [PLACES] Autocomplete response => ${_short(res)}');

      if (res is Map) {
        // Aceptar múltiples claves para la lista de predicciones/resultados
        final dynamic rawList = res['results'] ?? res['predictions'] ?? res['items'];
        final status = (res['status'] ?? '').toString();
        final errorMessage = (res['error_message'] ?? '').toString();
        if (status.isNotEmpty && status != 'OK') {
          debugPrint('⚠️ [PLACES] Google status=$status, error=$errorMessage');
          lastError = errorMessage.isNotEmpty ? errorMessage : 'Google Places status: $status';
        }

        if (rawList is List) {
          // Garantizar List<Map<String, dynamic>> y rellenar campos comunes
          final list = rawList.map<Map<String, dynamic>>((e) {
            if (e is Map<String, dynamic>) {
              // Normalizar algunos campos (description/place_id)
              return {
                ...e,
                'description': e['description'] ?? e['formatted_address'] ?? e['address'] ?? '',
                'place_id': e['place_id'] ?? e['placeId'] ?? e['id'] ?? '',
              };
            }
            return {
              'description': e?.toString() ?? '',
            };
          }).toList();
          debugPrint('✅ [PLACES] Autocomplete results=${list.length}');
          return list;
        }
      }

      debugPrint('⚠️ [PLACES] Unexpected autocomplete payload shape');
      lastError = 'Unexpected autocomplete payload shape';
      return [];
    } catch (e, st) {
      debugPrint('❌ [PLACES] Autocomplete error: $e');
      debugPrint('❌ Stack: $st');
      lastError = e.toString();
      return [];
    }
  }

  /// Place Details: obtener lat/lon y dirección completa de un place_id
  /// Robusto a diferentes formatos (Google result anidado o payload plano)
  static Future<Map<String, dynamic>?> placeDetails(
    String placeId, {
    String language = 'es',
  }) async {
    try {
      if (placeId.isEmpty) {
        debugPrint('🔎 [PLACES] placeDetails skipped: empty placeId');
        return null;
      }
      final body = {
        'action': 'place_details',
        'placeId': placeId,
        'language': language,
      };
      lastError = null;
      debugPrint('📤 [PLACES] PlaceDetails request => $body');
      final response = await SupabaseConfig.client.functions.invoke('google-maps-proxy', body: body);
      final res = response.data;
      debugPrint('📥 [PLACES] PlaceDetails response => ${_short(res)}');

      if (res is Map<String, dynamic>) {
        final status = (res['status'] ?? '').toString();
        final errorMessage = (res['error_message'] ?? '').toString();
        if (status.isNotEmpty && status != 'OK') {
          debugPrint('⚠️ [PLACES] Details status=$status, error=$errorMessage');
          lastError = errorMessage.isNotEmpty ? errorMessage : 'Google Places status: $status';
        }

        // Buscar lat/lon y dirección en diferentes rutas
        Map<String, dynamic>? result = res['result'] is Map<String, dynamic>
            ? (res['result'] as Map<String, dynamic>)
            : null;

        num? latNum;
        num? lonNum;
        String? formatted;
        String? pid;

        // 1) Plano
        latNum = (res['lat'] ?? res['latitude']) as num?;
        lonNum = (res['lon'] ?? res['lng'] ?? res['longitude']) as num?;
        formatted = (res['formatted_address'] ?? res['address'] ?? res['formattedAddress'])?.toString();
        pid = (res['place_id'] ?? res['placeId'] ?? res['id'])?.toString();

        // 2) Anidado en result.geometry.location
        if ((latNum == null || lonNum == null) && result != null) {
          final geometry = result['geometry'] as Map<String, dynamic>?;
          final loc = geometry != null ? geometry['location'] as Map<String, dynamic>? : null;
          latNum = latNum ?? (loc?['lat'] as num?);
          lonNum = lonNum ?? (loc?['lng'] as num?);
          formatted = formatted ?? (result['formatted_address']?.toString());
          pid = pid ?? (result['place_id']?.toString());
        }

        return {
          'lat': latNum?.toDouble(),
          'lon': lonNum?.toDouble(),
          'formatted_address': formatted,
          'place_id': pid,
          ...res,
        };
      }
      debugPrint('⚠️ [PLACES] Unexpected placeDetails payload');
      return null;
    } catch (e, st) {
      debugPrint('❌ [PLACES] placeDetails error: $e');
      debugPrint('❌ Stack: $st');
      lastError = e.toString();
      return null;
    }
  }

  /// Geocode: convertir dirección de texto a coordenadas
  static Future<Map<String, dynamic>?> geocodeAddress(
    String address, {
    String language = 'es',
    String? components,
  }) async {
    try {
      final trimmed = address.trim();
      if (trimmed.isEmpty) {
        debugPrint('🔎 [PLACES] Geocode skipped: empty address');
        return null;
      }
      final body = {
        'action': 'geocode',
        'address': trimmed,
        'language': language,
        if (components != null && components.isNotEmpty) 'components': components,
      };
      lastError = null;
      debugPrint('📤 [PLACES] Geocode request => $body');
      final response = await SupabaseConfig.client.functions.invoke('google-maps-proxy', body: body);
      final res = response.data;
      debugPrint('📥 [PLACES] Geocode response => ${_short(res)}');

      if (res is Map<String, dynamic>) {
        final status = (res['status'] ?? '').toString();
        final errorMessage = (res['error_message'] ?? '').toString();
        if (status.isNotEmpty && status != 'OK') {
          debugPrint('⚠️ [PLACES] Geocode status=$status, error=$errorMessage');
          lastError = errorMessage.isNotEmpty ? errorMessage : 'Google Geocode status: $status';
        }
        return res;
      }
      debugPrint('⚠️ [PLACES] Unexpected geocode payload');
      return null;
    } catch (e, st) {
      debugPrint('❌ [PLACES] Geocode error: $e');
      debugPrint('❌ Stack: $st');
      lastError = e.toString();
      return null;
    }
  }

  /// Reverse Geocode: convertir lat/lon a dirección de texto y componentes estructurados
  static Future<Map<String, dynamic>?> reverseGeocode(
    double lat,
    double lon, {
    String language = 'es',
  }) async {
    try {
      final body = {
        'action': 'reverse_geocode',
        'lat': lat,
        'lon': lon,
        'language': language,
      };
      lastError = null;
      debugPrint('📤 [PLACES] ReverseGeocode request => $body');
      final response = await SupabaseConfig.client.functions.invoke('google-maps-proxy', body: body);
      final res = response.data;
      debugPrint('📥 [PLACES] ReverseGeocode response => ${_short(res)}');

      if (res is Map<String, dynamic>) {
        final status = (res['status'] ?? '').toString();
        final errorMessage = (res['error_message'] ?? '').toString();
        if (status.isNotEmpty && status != 'OK') {
          debugPrint('⚠️ [PLACES] ReverseGeocode status=$status, error=$errorMessage');
          lastError = errorMessage.isNotEmpty ? errorMessage : 'Google ReverseGeocode status: $status';
        }

        // Si viene con resultados, tomar el primero
        final results = res['results'];
        if (results is List && results.isNotEmpty && results.first is Map<String, dynamic>) {
          final first = results.first as Map<String, dynamic>;
          return {
            'formatted_address': first['formatted_address'] ?? res['formatted_address'],
            'address_components': first['address_components'] ?? res['address_components'],
            ...res,
          };
        }

        return res;
      }
      debugPrint('⚠️ [PLACES] Unexpected reverse geocode payload');
      return null;
    } catch (e, st) {
      debugPrint('❌ [PLACES] ReverseGeocode error: $e');
      debugPrint('❌ Stack: $st');
      lastError = e.toString();
      return null;
    }
  }

  /// Validate Address: validar y estructurar una dirección con la Address Validation API
  static Future<Map<String, dynamic>?> validateAddress(
    String address, {
    String language = 'es',
  }) async {
    try {
      final trimmed = address.trim();
      if (trimmed.isEmpty) {
        debugPrint('🔎 [PLACES] ValidateAddress skipped: empty address');
        return null;
      }
      final body = {
        'action': 'validate_address',
        'address': trimmed,
        'language': language,
      };
      lastError = null;
      debugPrint('📤 [PLACES] ValidateAddress request => $body');
      final response = await SupabaseConfig.client.functions.invoke('google-maps-proxy', body: body);
      final res = response.data;
      debugPrint('📥 [PLACES] ValidateAddress response => ${_short(res)}');

      if (res is Map<String, dynamic>) {
        return res;
      }
      debugPrint('⚠️ [PLACES] Unexpected validate address payload');
      return null;
    } catch (e, st) {
      debugPrint('❌ [PLACES] ValidateAddress error: $e');
      debugPrint('❌ Stack: $st');
      lastError = e.toString();
      return null;
    }
  }

  static String _short(Object? data) {
    final s = data.toString();
    return s.length > 600 ? s.substring(0, 600) + '…' : s;
  }
}
