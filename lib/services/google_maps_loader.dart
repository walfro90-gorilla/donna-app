// Cross-platform loader for Google Maps JavaScript API (web only).
// On mobile, this is a no-op.

import 'package:doa_repartos/services/google_maps_loader_stub.dart'
    if (dart.library.html) 'package:doa_repartos/services/google_maps_loader_web.dart' as impl;

class GoogleMapsLoader {
  /// Ensure Google Maps JS is loaded (web) before rendering GoogleMap widget.
  /// On mobile platforms, this completes immediately.
  static Future<void> ensureInitialized() => impl.ensureInitialized();
}
