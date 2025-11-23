import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;
import 'package:doa_repartos/services/places_service.dart';
import 'package:doa_repartos/services/google_maps_loader.dart';

/// Resultado del picker de direcciones
class AddressPickResult {
  final String formattedAddress;
  final double lat;
  final double lon;
  final String? placeId;
  final Map<String, dynamic>? addressStructured;

  const AddressPickResult({
    required this.formattedAddress,
    required this.lat,
    required this.lon,
    this.placeId,
    this.addressStructured,
  });
  
  @override
  String toString() => 'AddressPickResult(address: "$formattedAddress", lat: $lat, lon: $lon, placeId: $placeId)';
}

/// Modal completo para búsqueda + mapa con pin arrastrable + confirmación
/// Rediseñado según Material Design 3 y mejores prácticas de UI/UX
class AddressPickerModal extends StatefulWidget {
  final String initialAddress;
  final String? sessionToken;
  final LatLng? initialLatLng; // If provided, start directly in map view

  const AddressPickerModal({
    super.key,
    this.initialAddress = '',
    this.sessionToken,
    this.initialLatLng,
  });

  @override
  State<AddressPickerModal> createState() => _AddressPickerModalState();
}

class _AddressPickerModalState extends State<AddressPickerModal> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  // Map state
  GoogleMapController? _mapController;
  LatLng? _selectedLocation;
  String? _selectedPlaceId;
  String? _selectedAddress;
  Map<String, dynamic>? _addressStructured;
  bool _showMap = false;
  bool _isProcessing = false;
  bool _isGoogleMapsReady = false;
  // Web map (FlutterMap) controller and zoom state
  fm.MapController? _webMapController;
  double _webZoom = 17.0;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialAddress;
    _initGoogleMapsIfNeeded();
    // If initial coordinates are provided (e.g., after autocomplete),
    // jump straight to map confirmation step.
    if (widget.initialLatLng != null) {
      _selectedLocation = widget.initialLatLng;
      _selectedAddress = widget.initialAddress.isNotEmpty ? widget.initialAddress : null;
      _showMap = true;
    }
  }

  double _clampZoom(double z) {
    if (z < 12.0) return 12.0;
    if (z > 20.0) return 20.0;
    return z;
  }

  void _zoomIn() {
    if (kIsWeb) {
      if (_selectedLocation == null) return;
      _webZoom = _clampZoom(_webZoom + 1.0);
      try {
        _webMapController?.move(
          ll.LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
          _webZoom,
        );
      } catch (e) {
        debugPrint('🧭 [ADDRESS_PICKER] Web zoomIn failed: $e');
      }
      setState(() {});
    } else {
      try {
        _mapController?.animateCamera(CameraUpdate.zoomIn());
      } catch (e) {
        debugPrint('🧭 [ADDRESS_PICKER] GoogleMap zoomIn failed: $e');
      }
    }
  }

  void _zoomOut() {
    if (kIsWeb) {
      if (_selectedLocation == null) return;
      _webZoom = _clampZoom(_webZoom - 1.0);
      try {
        _webMapController?.move(
          ll.LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
          _webZoom,
        );
      } catch (e) {
        debugPrint('🧭 [ADDRESS_PICKER] Web zoomOut failed: $e');
      }
      setState(() {});
    } else {
      try {
        _mapController?.animateCamera(CameraUpdate.zoomOut());
      } catch (e) {
        debugPrint('🧭 [ADDRESS_PICKER] GoogleMap zoomOut failed: $e');
      }
    }
  }

  Future<void> _initGoogleMapsIfNeeded() async {
    // Make map available immediately on all platforms.
    // On web, google_maps_flutter_web injects JS itself; no need to gate UI.
    if (mounted) {
      setState(() => _isGoogleMapsReady = true);
    }
    // Fire-and-forget best-effort loader (safe if it does nothing)
    try { await GoogleMapsLoader.ensureInitialized(); } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    final qTrim = query.trim();
    if (qTrim.length < 3) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
        _searchError = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await PlacesService.autocomplete(
        qTrim,
        sessionToken: widget.sessionToken,
      );
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
          _searchError = (results.isEmpty && PlacesService.lastError != null)
              ? PlacesService.lastError
              : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchError = e.toString();
        });
      }
    }
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    final pid = (place['place_id'] ?? '').toString();
    debugPrint('🧭 [ADDRESS_PICKER] Selecting place: $pid');
    debugPrint('🧭 [ADDRESS_PICKER] Mounted before processing: $mounted');

    setState(() => _isProcessing = true);

    try {
      debugPrint('🧭 [ADDRESS_PICKER] Fetching place details...');
      final details = await PlacesService.placeDetails(pid);
      debugPrint('🧭 [ADDRESS_PICKER] Place details received: ${details != null}');
      
      if (details == null) {
        debugPrint('❌ [ADDRESS_PICKER] Details is null - mounted=$mounted');
        if (mounted) {
          setState(() => _isProcessing = false);
          _showSnackbar('No se pudieron obtener los detalles de la ubicación', isError: true);
        }
        return;
      }

      final lat = details['lat'] as double?;
      final lon = details['lon'] as double?;
      debugPrint('🧭 [ADDRESS_PICKER] Coordinates: lat=$lat, lon=$lon');
      
      if (lat == null || lon == null) {
        debugPrint('❌ [ADDRESS_PICKER] Invalid coordinates - mounted=$mounted');
        if (mounted) {
          setState(() => _isProcessing = false);
          _showSnackbar('Ubicación sin coordenadas válidas', isError: true);
        }
        return;
      }

      debugPrint('🧭 [ADDRESS_PICKER] About to show map - mounted=$mounted');
      if (mounted) {
        final address = details['formatted_address']?.toString() ?? place['description']?.toString();
        debugPrint('🧭 [ADDRESS_PICKER] Setting state to show map...');
        debugPrint('   - selectedLocation: LatLng($lat, $lon)');
        debugPrint('   - selectedAddress: $address');
        debugPrint('   - showMap: true');
        
        setState(() {
          _selectedLocation = LatLng(lat, lon);
          _selectedPlaceId = pid;
          _selectedAddress = address;
          _showMap = true;
          _isProcessing = false;
        });
        
        debugPrint('✅ [ADDRESS_PICKER] State updated successfully - _showMap=$_showMap');
      } else {
        debugPrint('❌ [ADDRESS_PICKER] Widget not mounted - cannot setState');
      }
    } catch (e) {
      debugPrint('❌ [ADDRESS_PICKER] Exception in _selectPlace: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnackbar('Error: $e', isError: true);
      }
    }
  }

  Future<void> _confirmLocation() async {
    debugPrint('🎯 [ADDRESS_PICKER] _confirmLocation() iniciado');
    debugPrint('   - _selectedLocation: $_selectedLocation');
    debugPrint('   - mounted: $mounted');
    debugPrint('   - context.mounted: ${context.mounted}');
    
    if (_selectedLocation == null) {
      debugPrint('❌ [ADDRESS_PICKER] No hay ubicación seleccionada');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      debugPrint('🔄 [ADDRESS_PICKER] Obteniendo dirección inversa...');
      final reverseResult = await PlacesService.reverseGeocode(
        _selectedLocation!.latitude,
        _selectedLocation!.longitude,
      );

      String finalAddress = _selectedAddress ?? 'Ubicación seleccionada';
      Map<String, dynamic>? structured;

      if (reverseResult != null) {
        finalAddress = reverseResult['formatted_address']?.toString() ?? finalAddress;
        final ac = reverseResult['address_components'];
        if (ac is Map<String, dynamic>) {
          structured = ac;
        } else if (ac is List) {
          structured = {
            'components': ac,
          };
        } else if (reverseResult is Map<String, dynamic>) {
          // Fallback: guardar todo el resultado para posterior análisis
          structured = {
            'reverse_geocode': reverseResult,
          };
        }
        debugPrint('✅ [ADDRESS_PICKER] ReverseGeocode exitoso => $finalAddress');
      } else {
        debugPrint('⚠️ [ADDRESS_PICKER] ReverseGeocode no devolvió resultado, usando: $finalAddress');
      }

      if (!mounted) {
        debugPrint('❌ [ADDRESS_PICKER] Widget desmontado antes de crear resultado');
        return;
      }

      final result = AddressPickResult(
        formattedAddress: finalAddress,
        lat: _selectedLocation!.latitude,
        lon: _selectedLocation!.longitude,
        placeId: _selectedPlaceId,
        addressStructured: structured,
      );
      
      debugPrint('📦 [ADDRESS_PICKER] Resultado creado: $result');
      
      if (!context.mounted) {
        debugPrint('❌ [ADDRESS_PICKER] Context desmontado antes de pop!');
        return;
      }
      
      debugPrint('🚀 [ADDRESS_PICKER] Ejecutando Navigator.pop(context, result)...');
      debugPrint('   - context: $context');
      debugPrint('   - result: $result');
      
      Navigator.pop(context, result);
      
      debugPrint('📤 [ADDRESS_PICKER] Navigator.pop() completado exitosamente');
    } catch (e, stackTrace) {
      debugPrint('❌ [ADDRESS_PICKER] Error en _confirmLocation: $e');
      debugPrint('📚 [ADDRESS_PICKER] StackTrace: $stackTrace');
      
      if (mounted) {
        setState(() => _isProcessing = false);
        _showSnackbar('Error al confirmar ubicación: $e', isError: true);
      }
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🏗️ [ADDRESS_PICKER] Building widget - _showMap=$_showMap, _selectedLocation=$_selectedLocation');
    if (_showMap && _selectedLocation != null) {
      debugPrint('🏗️ [ADDRESS_PICKER] Rendering MAP VIEW');
      return _buildMapView();
    }
    debugPrint('🏗️ [ADDRESS_PICKER] Rendering SEARCH VIEW');
    return _buildSearchView();
  }

  Widget _buildSearchView() {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header mejorado con mejor contraste
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Buscar Dirección',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),
            
            // Search field mejorado
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: theme.textTheme.bodyLarge,
                decoration: InputDecoration(
                  labelText: 'Dirección',
                  hintText: 'Calle, colonia, ciudad...',
                  prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
                  ),
                ),
                onChanged: _performSearch,
                onSubmitted: _performSearch,
              ),
            ),
            
            // Loading / Error states
            if (_isSearching || _isProcessing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            
            if (!_isSearching && !_isProcessing && _searchError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Error: $_searchError',
                          style: TextStyle(color: Colors.red.shade900, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            if (!_isSearching && !_isProcessing && _searchResults.isEmpty && _searchController.text.trim().length >= 3 && _searchError == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    Text(
                      'Sin resultados',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Intenta con otra búsqueda',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            
            // Results list mejorada
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor),
                itemBuilder: (_, i) {
                  final r = _searchResults[i];
                  final description = r['description']?.toString() ?? '';
                  
                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.place, color: Colors.red.shade600, size: 20),
                    ),
                    title: Text(
                      description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16, color: theme.colorScheme.outline),
                    onTap: () => _selectPlace(r),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    final theme = Theme.of(context);
    debugPrint('🗺️ [ADDRESS_PICKER] _buildMapView() called');
    debugPrint('   - _selectedLocation: $_selectedLocation');
    debugPrint('   - _isGoogleMapsReady: $_isGoogleMapsReady');
    debugPrint('   - _selectedAddress: $_selectedAddress');
    
    if (!_isGoogleMapsReady) {
      return Container(
        color: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              AppBar(
                title: const Text('Cargando Mapa...'),
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    setState(() {
                      _showMap = false;
                      _selectedLocation = null;
                      _selectedPlaceId = null;
                      _selectedAddress = null;
                    });
                  },
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Preparando el mapa...',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Header mejorado
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Color(0xFF333333)),
                    onPressed: () {
                      setState(() {
                        _showMap = false;
                        _selectedLocation = null;
                        _selectedPlaceId = null;
                        _selectedAddress = null;
                      });
                    },
                    tooltip: 'Volver a búsqueda',
                  ),
                  Expanded(
                    child: Text(
                      'Confirma tu ubicación',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1A1A1A),
                        fontSize: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Map container
            Expanded(
              child: _selectedLocation == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: theme.colorScheme.primary),
                          const SizedBox(height: 16),
                          Text('Cargando mapa...', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        // GoogleMap (mobile/desktop) or FlutterMap fallback (web)
                        if (kIsWeb)
                          fm.FlutterMap(
                            mapController: (_webMapController ??= fm.MapController()),
                            options: fm.MapOptions(
                              initialCenter: ll.LatLng(_selectedLocation!.latitude, _selectedLocation!.longitude),
                              initialZoom: _webZoom,
                              interactionOptions: const fm.InteractionOptions(
                                flags: fm.InteractiveFlag.pinchZoom | fm.InteractiveFlag.drag,
                              ),
                              onMapEvent: (event) {
                                // Track zoom and center when user stops moving
                                if (event is fm.MapEventMoveEnd || event is fm.MapEventFlingAnimationEnd) {
                                  final c = event.camera.center;
                                  final z = event.camera.zoom;
                                  if (mounted) {
                                    setState(() {
                                      _selectedLocation = LatLng(c.latitude, c.longitude);
                                      _webZoom = _clampZoom(z);
                                    });
                                  }
                                }
                              },
                            ),
                            children: [
                              fm.TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.doa.repartos',
                              ),
                            ],
                          )
                        else
                          GoogleMap(
                            initialCameraPosition: CameraPosition(
                              target: _selectedLocation!,
                              zoom: 17,
                            ),
                            onMapCreated: (controller) {
                              debugPrint('🧭 [ADDRESS_PICKER] GoogleMap created successfully');
                              if (mounted) {
                                setState(() => _mapController = controller);
                                // Apply light map style for better visibility
                                try {
                                  controller.setMapStyle('''
                                    [
                                      {"featureType": "all", "elementType": "geometry", "stylers": [{"color": "#f5f5f5"}]},
                                      {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#c9e5f7"}]}
                                    ]
                                  ''');
                                } catch (e) {
                                  debugPrint('🧭 [ADDRESS_PICKER] Could not apply map style: $e');
                                }
                              }
                            },
                            markers: {
                              Marker(
                                markerId: const MarkerId('selected'),
                                position: _selectedLocation!,
                                draggable: true,
                                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                                onDragEnd: (newPos) {
                                  if (mounted) {
                                    setState(() => _selectedLocation = newPos);
                                    debugPrint('🧭 [ADDRESS_PICKER] Pin moved to: ${newPos.latitude}, ${newPos.longitude}');
                                  }
                                },
                              ),
                            },
                            myLocationButtonEnabled: true,
                            myLocationEnabled: true,
                            zoomControlsEnabled: false,
                            mapToolbarEnabled: false,
                            compassEnabled: true,
                            minMaxZoomPreference: const MinMaxZoomPreference(12, 20),
                          ),

                        // Center pin overlay for web
                        if (kIsWeb)
                          IgnorePointer(
                            child: Center(
                              child: Icon(Icons.location_on, size: 40, color: Colors.red.shade600),
                            ),
                          ),

                        // Zoom controls (+ / -)
                        Positioned(
                          right: 12,
                          top: 100,
                          child: Column(
                            children: [
                              _ZoomButton(icon: Icons.add, onTap: _zoomIn),
                              const SizedBox(height: 8),
                              _ZoomButton(icon: Icons.remove, onTap: _zoomOut),
                            ],
                          ),
                        ),
                        
                        // Confirmation card mejorado con mejor UI/UX
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Address display mejorado
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.location_on, color: Colors.red.shade600, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _selectedAddress ?? 'Ubicación seleccionada',
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              kIsWeb
                                                  ? 'Mueve el mapa para ajustar la ubicación exacta'
                                                  : 'Arrastra el pin para ajustar la ubicación exacta',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  
                                  // Confirm button mejorado
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      onPressed: _isProcessing ? null : _confirmLocation,
                                      icon: _isProcessing
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.check_circle, size: 20),
                                      label: Text(
                                        _isProcessing ? 'Confirmando...' : 'Confirmar Ubicación',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.pink.shade600,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    try {
      _mapController?.dispose();
    } catch (e) {
      debugPrint('🧭 [ADDRESS_PICKER] MapController dispose warning (safe to ignore): $e');
    }
    super.dispose();
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: Colors.black87),
        ),
      ),
    );
  }
}
