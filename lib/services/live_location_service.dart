import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

class DriverLocation {
  final double lat;
  final double lng;
  final DateTime? updatedAt;
  final double? bearing;
  final double? speed;

  const DriverLocation({
    required this.lat,
    required this.lng,
    this.updatedAt,
    this.bearing,
    this.speed,
  });
}

/// Polls Supabase RPC to get the driver location for a specific order.
/// Use for client-side live map without realtime replication.
class LiveLocationService {
  LiveLocationService._internal();
  static final LiveLocationService instance = LiveLocationService._internal();

  final SupabaseClient _supabase = SupabaseConfig.client;

  Future<DriverLocation?> fetchDriverLocation({required String orderId}) async {
    try {
      final result = await _supabase.rpc('get_driver_location_for_order', params: {
        'p_order_id': orderId,
      });

      if (result == null) return await _fallbackQuery(orderId: orderId);

      // Some RPCs return a list, others a single map/record
      final row = _unwrapRow(result);
      if (row == null) {
        debugPrint('⚠️ [LIVE_LOC] RPC returned empty result for order $orderId');
        return await _fallbackQuery(orderId: orderId);
      }

      // Try common key names first (courier_locations_latest uses 'lat' and 'lon')
      double? lat = _toDouble(row['lat'] ?? row['latitude'] ?? row['latitud']);
      double? lng = _toDouble(row['lon'] ?? row['lng'] ?? row['long'] ?? row['longitude'] ?? row['longitud']);

      // Try GeoJSON or geometry-like payloads
      if (lat == null || lng == null) {
        final geo = row['geojson'] ?? row['current_location_geojson'] ?? row['geom_geojson'] ?? row['geom'] ?? row['current_location'];
        final pair = _extractFromGeometry(geo);
        lat ??= pair?.$1;
        lng ??= pair?.$2;
      }

      if (lat == null || lng == null) {
        debugPrint('⚠️ [LIVE_LOC] Could not parse lat/lng from RPC. Row: $row');
        return await _fallbackQuery(orderId: orderId);
      }

      DateTime? updatedAt;
      final updated = row['updated_at']?.toString() ?? row['ts']?.toString() ?? row['last_seen_at']?.toString();
      if (updated != null && updated.isNotEmpty) {
        updatedAt = DateTime.tryParse(updated);
      }

      return DriverLocation(
        lat: lat,
        lng: lng,
        updatedAt: updatedAt,
        bearing: _toDouble(row['bearing']),
        speed: _toDouble(row['speed']),
      );
    } catch (e) {
      debugPrint('❌ [LIVE_LOC] Error fetching driver location via RPC: $e');
      // Try fallback direct selects (subject to RLS)
      return await _fallbackQuery(orderId: orderId);
    }
  }

  /// Fallback path: read orders.delivery_agent_id then users.lat/lon by id.
  Future<DriverLocation?> _fallbackQuery({required String orderId}) async {
    try {
      final order = await _supabase.from('orders').select('delivery_agent_id').eq('id', orderId).maybeSingle();
      final driverId = order != null ? order['delivery_agent_id'] as String? : null;
      if (driverId == null) {
        debugPrint('ℹ️ [LIVE_LOC] No delivery_agent_id for order $orderId');
        return null;
      }
      // Read from public.users as per DATABASE_SCHEMA.sql
      final row = await _supabase
          .from('users')
          .select('lat, lon, updated_at, current_location')
          .eq('id', driverId)
          .maybeSingle();
      if (row == null) return null;

      double? lat = _toDouble(row['lat']);
      double? lon = _toDouble(row['lon']);

      // If lat/lon are null, try to parse from current_location (geography/geometry/geojson)
      if (lat == null || lon == null) {
        final geo = row['current_location'];
        final pair = _extractFromGeometry(geo);
        if (pair != null) {
          lat = lat ?? pair.$1;
          lon = lon ?? pair.$2;
        }
      }

      if (lat == null || lon == null) return null;
      final updatedAt = row['updated_at'] != null ? DateTime.tryParse(row['updated_at'].toString()) : null;
      return DriverLocation(lat: lat, lng: lon, updatedAt: updatedAt);
    } catch (e) {
      debugPrint('❌ [LIVE_LOC] Fallback query failed: $e');
      return null;
    }
  }

  Stream<DriverLocation?> watchDriverLocation({
    required String orderId,
    Duration interval = const Duration(seconds: 8),
  }) {
    late Timer timer;
    StreamController<DriverLocation?>? controller;
    controller = StreamController<DriverLocation?>.broadcast(
      onListen: () async {
        // fire immediately
        controller!.add(await fetchDriverLocation(orderId: orderId));
        timer = Timer.periodic(interval, (_) async {
          controller!.add(await fetchDriverLocation(orderId: orderId));
        });
      },
      onCancel: () {
        timer.cancel();
      },
    );
    return controller.stream;
  }

  Map<String, dynamic>? _unwrapRow(dynamic result) {
    if (result == null) return null;
    if (result is List && result.isNotEmpty) {
      final first = result.first;
      return first is Map<String, dynamic> ? first : null;
    }
    if (result is Map<String, dynamic>) return result;
    return null;
  }

  /// Extract lat,lng from common geometry encodings.
  /// Returns a Dart record (lat,lng) or null if it cannot parse.
  (double, double)? _extractFromGeometry(dynamic geo) {
    if (geo == null) return null;

    // Case: already a map with coordinates [lon, lat]
    if (geo is Map<String, dynamic>) {
      // GeoJSON style
      final coords = geo['coordinates'];
      if (coords is List && coords.length >= 2) {
        final lon = _toDouble(coords[0]);
        final lat = _toDouble(coords[1]);
        if (lat != null && lon != null) return (lat, lon);
      }
      // Some functions return {lat: .., lon: ..}
      final lat = _toDouble(geo['lat'] ?? geo['latitude']);
      final lon = _toDouble(geo['lng'] ?? geo['lon'] ?? geo['long'] ?? geo['longitude']);
      if (lat != null && lon != null) return (lat, lon);
    }

    // Case: string formats
    if (geo is String) {
      final s = geo.trim();
      // GeoJSON string
      if (s.startsWith('{') && s.contains('"coordinates"')) {
        try {
          final m = jsonDecode(s);
          final coords = (m['coordinates'] as List);
          if (coords.length >= 2) {
            final lon = _toDouble(coords[0]);
            final lat = _toDouble(coords[1]);
            if (lat != null && lon != null) return (lat, lon);
          }
        } catch (_) {}
      }
      // WKT: POINT(lon lat)
      if (s.toUpperCase().startsWith('POINT(') && s.endsWith(')')) {
        final inner = s.substring(s.indexOf('(') + 1, s.length - 1);
        final parts = inner.split(RegExp(r'[ ,]+'));
        if (parts.length >= 2) {
          final lon = _toDouble(parts[0]);
          final lat = _toDouble(parts[1]);
          if (lat != null && lon != null) return (lat, lon);
        }
      }
      // WKB hex (0101..): cannot parse reliably on client — skip
    }

    return null;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString());
  }
}
