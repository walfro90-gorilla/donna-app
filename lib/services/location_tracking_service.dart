import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:flutter/foundation.dart';

/// Lightweight singleton to send driver location to Supabase every 30 seconds
/// while a delivery is active. Web-friendly (runs in foreground only).
class LocationTrackingService {
  LocationTrackingService._internal();
  static final LocationTrackingService instance = LocationTrackingService._internal();

  final SupabaseClient _supabase = SupabaseConfig.client;

  Timer? _timer;
  bool _isRunning = false;
  String? _activeOrderId;

  bool get isRunning => _isRunning;
  String? get activeOrderId => _activeOrderId;

  Future<bool> _ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ [LOC] Location services are disabled');
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        debugPrint('❌ [LOC] Location permission denied');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('❌ [LOC] Permission error: $e');
      return false;
    }
  }

  Future<void> start({required String orderId}) async {
    if (_isRunning && _activeOrderId == orderId) {
      debugPrint('ℹ️ [LOC] Already running for order $orderId');
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('❌ [LOC] No authenticated user');
      return;
    }

    if (!await _ensurePermission()) {
      debugPrint('❌ [LOC] Cannot start without permission');
      return;
    }

    _activeOrderId = orderId;
    _isRunning = true;

    // Send immediately, then every 30 seconds
    await _sendOnce();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _sendOnce());
    debugPrint('✅ [LOC] Started location tracking for order $orderId');
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('🛑 [LOC] Stopped location tracking');
  }

  Future<void> _sendOnce() async {
    try {
      if (!_isRunning) return;
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('⚠️ [LOC] No user during send, stopping');
        await stop();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final lat = pos.latitude;
      final lng = pos.longitude;

      await _supabase.rpc('update_my_location', params: {
        'p_lat': lat,
        'p_lng': lng,
      });

      debugPrint('📍 [LOC] Sent position lat=$lat, lng=$lng');
    } catch (e) {
      debugPrint('⚠️ [LOC] Error sending location: $e');
    }
  }
}
