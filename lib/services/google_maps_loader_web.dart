// Web implementation no-op. We rely on google_maps_flutter_web to inject JS.

import 'dart:async';

/// On web, the google_maps_flutter_web plugin handles script loading.
/// We keep this function for API parity but it resolves immediately.
Future<void> ensureInitialized() async {
  return; // no-op
}
