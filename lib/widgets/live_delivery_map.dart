import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:doa_repartos/services/live_location_service.dart';

class LiveDeliveryMap extends StatefulWidget {
  final String orderId;
  final String? deliveryLatlng; // format: "lat,lng"
  final String? restaurantLatlng; // optional, same format
  final double height;
  // When true, show the client destination marker instead of the restaurant marker
  final bool showClientDestination;

  const LiveDeliveryMap({
    super.key,
    required this.orderId,
    this.deliveryLatlng,
    this.restaurantLatlng,
    this.height = 220,
    this.showClientDestination = false,
  });

  @override
  State<LiveDeliveryMap> createState() => _LiveDeliveryMapState();
}

class _LiveDeliveryMapState extends State<LiveDeliveryMap> {
  final MapController _mapController = MapController();
  StreamSubscription<DriverLocation?>? _sub;
  DriverLocation? _driver;
  DateTime? _lastUpdated;

  ll.LatLng? get _dest => _parseLatLng(widget.deliveryLatlng);
  ll.LatLng? get _rest => _parseLatLng(widget.restaurantLatlng);

  @override
  void initState() {
    super.initState();
    _sub = LiveLocationService.instance
        .watchDriverLocation(orderId: widget.orderId)
        .listen((loc) {
      if (!mounted) return;
      setState(() {
        _driver = loc;
        _lastUpdated = DateTime.now();
      });
      if (loc != null) {
        // keep map centered around driver when first data arrives
        _maybeMoveMap(ll.LatLng(loc.lat, loc.lng));
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _maybeMoveMap(ll.LatLng center) {
    try {
      // Calculate bounds to fit both active markers
      final markers = <ll.LatLng>[center];
      // Add second active marker based on current state
      if (widget.showClientDestination) {
        final target = _dest ?? _rest;
        if (target != null) markers.add(target);
      } else {
        if (_rest != null) markers.add(_rest!);
      }

      if (markers.length == 1) {
        // Only courier visible, use fixed zoom
        _mapController.move(center, 15.0);
      } else {
        // Calculate bounds between the two markers
        final lats = markers.map((m) => m.latitude).toList();
        final lngs = markers.map((m) => m.longitude).toList();
        final minLat = lats.reduce((a, b) => a < b ? a : b);
        final maxLat = lats.reduce((a, b) => a > b ? a : b);
        final minLng = lngs.reduce((a, b) => a < b ? a : b);
        final maxLng = lngs.reduce((a, b) => a > b ? a : b);
        
        final bounds = LatLngBounds(
          ll.LatLng(minLat, minLng),
          ll.LatLng(maxLat, maxLng),
        );
        // Fit bounds with some padding
        _mapController.fitCamera(
          CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
        );
      }
    } catch (_) {}
  }

  ll.LatLng? _parseLatLng(String? value) {
    if (value == null || value.isEmpty) return null;
    final parts = value.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return null;
    return ll.LatLng(lat, lng);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine initial center
    final initialCenter = _driver != null
        ? ll.LatLng(_driver!.lat, _driver!.lng)
        : _dest ?? _rest ?? const ll.LatLng(19.4326, -99.1332); // CDMX fallback

    final markers = <Marker>[];
    if (_driver != null) {
      markers.add(
        Marker(
          point: ll.LatLng(_driver!.lat, _driver!.lng),
          width: 40,
          height: 40,
          child: _MarkerDot(icon: Icons.delivery_dining, color: theme.colorScheme.primary),
        ),
      );
    }
    // Business rule:
    //  - Before pickup: show driver + restaurant
    //  - After pickup (on_the_way / delivered): show driver + client home
    if (widget.showClientDestination) {
      // After pickup: prefer client destination; if missing, fall back to restaurant coords
      final target = _dest ?? _rest;
      if (target != null) {
        markers.add(
          Marker(
            point: target,
            width: 36,
            height: 36,
            child: _MarkerDot(icon: Icons.home, color: Colors.green),
          ),
        );
      }
    } else {
      if (_rest != null) {
        markers.add(
          Marker(
            point: _rest!,
            width: 34,
            height: 34,
            child: _MarkerDot(icon: Icons.restaurant, color: Colors.orange),
          ),
        );
      }
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          SizedBox(
            height: widget.height,
            width: double.infinity,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 15,
                // Lock interactions: user cannot move or zoom the map
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.doa.repartos',
                ),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.my_location, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    _driver == null
                        ? 'Esperando ubicación…'
                        : _lastUpdated != null
                            ? 'Actualizado · ${_timeAgo(_lastUpdated!)}'
                            : 'En vivo',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 10) return 'ahora';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

class _MarkerDot extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MarkerDot({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 2)),
      ], border: Border.all(color: color.withValues(alpha: 0.9), width: 2)),
      child: Center(child: Icon(icon, size: 18, color: color)),
    );
  }
}
