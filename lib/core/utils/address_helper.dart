/// Helper functions for standardized address handling
/// Ensures all address data is stored consistently in address_structured format

import 'package:google_maps_flutter/google_maps_flutter.dart';

class AddressHelper {
  /// Build standardized address_structured JSON from components
  /// 
  /// This ensures all address data follows the schema:
  /// {
  ///   "formatted_address": "Full address string",
  ///   "lat": 123.456,
  ///   "lon": -78.910,
  ///   "street": "Street name" (optional),
  ///   "city": "City name" (optional),
  ///   "state": "State/Province" (optional),
  ///   "country": "Country" (optional),
  ///   "postal_code": "Postal code" (optional),
  ///   "place_id": "Google Place ID" (optional)
  /// }
  static Map<String, dynamic> buildAddressStructured({
    required String formattedAddress,
    required double lat,
    required double lon,
    String? street,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? placeId,
  }) {
    final result = <String, dynamic>{
      'formatted_address': formattedAddress,
      'lat': lat,
      'lon': lon,
    };

    // Add optional fields only if they have values
    if (street != null && street.isNotEmpty) result['street'] = street;
    if (city != null && city.isNotEmpty) result['city'] = city;
    if (state != null && state.isNotEmpty) result['state'] = state;
    if (country != null && country.isNotEmpty) result['country'] = country;
    if (postalCode != null && postalCode.isNotEmpty) result['postal_code'] = postalCode;
    if (placeId != null && placeId.isNotEmpty) result['place_id'] = placeId;

    return result;
  }

  /// Build address_structured from Google Places API result
  static Map<String, dynamic> buildFromGooglePlace({
    required String formattedAddress,
    required LatLng location,
    String? placeId,
    Map<String, dynamic>? addressComponents,
  }) {
    String? street;
    String? city;
    String? state;
    String? country;
    String? postalCode;

    // Parse address components if provided
    if (addressComponents != null) {
      // Try to extract structured components from Google Places result
      // This is a simplified version - you may need to adjust based on your Google Places response format
      street = addressComponents['street'] as String?;
      city = addressComponents['city'] as String?;
      state = addressComponents['state'] as String?;
      country = addressComponents['country'] as String?;
      postalCode = addressComponents['postal_code'] as String?;
    }

    return buildAddressStructured(
      formattedAddress: formattedAddress,
      lat: location.latitude,
      lon: location.longitude,
      street: street,
      city: city,
      state: state,
      country: country,
      postalCode: postalCode,
      placeId: placeId,
    );
  }

  /// Extract lat/lon from address_structured JSON
  static LatLng? getLatLngFromStructured(Map<String, dynamic>? addressStructured) {
    if (addressStructured == null) return null;
    
    final lat = _parseDouble(addressStructured['lat']);
    final lon = _parseDouble(addressStructured['lon']);
    
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  /// Extract formatted address from address_structured JSON
  static String? getFormattedAddress(Map<String, dynamic>? addressStructured) {
    if (addressStructured == null) return null;
    final addr = addressStructured['formatted_address'];
    if (addr is String && addr.isNotEmpty) return addr;
    return null;
  }

  /// Validate that coordinates are within valid ranges
  static bool isValidCoordinate(double? lat, double? lon) {
    if (lat == null || lon == null) return false;
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  /// Helper to safely parse doubles from dynamic values
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Create minimal address_structured when only basic info is available
  static Map<String, dynamic>? buildMinimal({
    String? address,
    double? lat,
    double? lon,
  }) {
    if (lat == null || lon == null) return null;
    if (!isValidCoordinate(lat, lon)) return null;

    return {
      'formatted_address': address ?? 'Dirección no especificada',
      'lat': lat,
      'lon': lon,
    };
  }

  /// Merge legacy address fields with address_structured
  /// Useful during migration period when both formats might exist
  static Map<String, dynamic>? mergeWithLegacy({
    Map<String, dynamic>? addressStructured,
    String? legacyAddress,
    double? legacyLat,
    double? legacyLon,
  }) {
    // If address_structured exists and has valid coords, prefer it
    if (addressStructured != null) {
      final lat = _parseDouble(addressStructured['lat']);
      final lon = _parseDouble(addressStructured['lon']);
      if (isValidCoordinate(lat, lon)) {
        return addressStructured;
      }
    }

    // Fallback to legacy fields
    return buildMinimal(
      address: legacyAddress,
      lat: legacyLat,
      lon: legacyLon,
    );
  }
}
