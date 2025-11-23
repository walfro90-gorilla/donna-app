import 'package:flutter/material.dart';
import 'package:doa_repartos/services/places_service.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Campo de búsqueda de direcciones con autocomplete de Google Places
/// Sin mapa, solo búsqueda de texto con sugerencias inline
class AddressSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String? labelText;
  final String? hintText;
  final Function(Map<String, dynamic> placeDetails)? onPlaceSelected;
  final String? Function(String?)? validator;
  final bool required;

  const AddressSearchField({
    super.key,
    required this.controller,
    this.labelText,
    this.hintText,
    this.onPlaceSelected,
    this.validator,
    this.required = false,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final FocusNode _focusNode = FocusNode();
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;
  bool _showSuggestions = false;
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = PlacesService.newSessionToken();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final query = widget.controller.text;
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    _searchPlaces(query);
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Delay para permitir tap en sugerencias
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          setState(() => _showSuggestions = false);
        }
      });
    } else {
      // Mostrar sugerencias cuando el campo recibe foco
      if (_suggestions.isNotEmpty && mounted) {
        setState(() => _showSuggestions = true);
      }
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    debugPrint('🔍 [ADDRESS_SEARCH] Buscando: $query');

    final results = await PlacesService.autocomplete(
      query,
      sessionToken: _sessionToken,
      language: 'es',
    );

    debugPrint('📥 [ADDRESS_SEARCH] Resultados: ${results.length}');

    if (mounted) {
      setState(() {
        _suggestions = results;
        _isSearching = false;
        _showSuggestions = results.isNotEmpty && _focusNode.hasFocus;
      });
    }
  }

  Future<void> _onSuggestionSelected(Map<String, dynamic> suggestion) async {
    final placeId = suggestion['place_id'];
    if (placeId == null) return;

    // Ocultar sugerencias, no alteramos el texto hasta confirmar en el mapa
    setState(() {
      _suggestions = [];
      _showSuggestions = false;
    });
    final String originalDescription = suggestion['description']?.toString() ?? '';
    final String prevText = widget.controller.text;
    _focusNode.unfocus();

    debugPrint(
        '📍 [ADDRESS_SEARCH] Seleccionado: ${suggestion['description']}');

    // Mostrar loading breve mientras pedimos detalles
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              SizedBox(width: 12),
              Text('Cargando detalles de la dirección...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
    }

    // Obtener detalles completos (lat, lon, etc.)
    final details = await PlacesService.placeDetails(placeId, language: 'es');

    if (details != null && mounted) {
      debugPrint('✅ [ADDRESS_SEARCH] Detalles obtenidos: lat=${details['lat']}, lon=${details['lon']}');

      // Abrir modal de mapa para confirmar ubicación exacta
      final lat = details['lat'] as double?;
      final lon = (details['lon'] ?? details['lng']) as double?;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (lat != null && lon != null) {
        final confirmed = await showModalBottomSheet<dynamic>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => AddressPickerModal(
            initialAddress: details['formatted_address']?.toString() ?? originalDescription,
            sessionToken: _sessionToken,
            initialLatLng: LatLng(lat, lon),
          ),
        );

        if (confirmed is AddressPickResult) {
          // Fusionar resultado confirmado con los detalles del place
          final merged = Map<String, dynamic>.from(details);
          merged['lat'] = confirmed.lat;
          merged['lon'] = confirmed.lon;
          merged['place_id'] = confirmed.placeId ?? merged['place_id'];
          merged['address_structured'] = confirmed.addressStructured ?? merged['address_structured'];

          // Mantener el texto original seleccionado. Solo actualizamos lat/lon.
          widget.controller.text = originalDescription.isNotEmpty ? originalDescription : prevText;

          widget.onPlaceSelected?.call(merged);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Ubicación confirmada en el mapa'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          // Usuario canceló el mapa: no confirmamos, mantenemos sólo el texto
          // Paso de mapa es obligatorio: no modificamos el texto y avisamos.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Confirma la ubicación en el mapa para continuar'),
                duration: Duration(seconds: 2),
              ),
            );
            // Restaurar texto previo explícitamente por seguridad
            widget.controller.text = prevText;
            // Devolver el foco para que el usuario siga buscando
            _focusNode.requestFocus();
          }
        }
      } else {
        // Si no tenemos coordenadas, enviamos el detalle tal cual (fallback)
        widget.onPlaceSelected?.call(details);
      }
    }

    // Renovar session token después de seleccionar un lugar
    _sessionToken = PlacesService.newSessionToken();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          autovalidateMode: AutovalidateMode.always,
          style: const TextStyle(
            color: Colors.black,
          ),
          decoration: InputDecoration(
            labelText: widget.labelText ?? 'Dirección',
            hintText: widget.hintText ?? 'Buscar dirección...',
            labelStyle: const TextStyle(color: Colors.grey),
            hintStyle: TextStyle(color: Colors.grey[600]),
            border: const OutlineInputBorder(),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.pink),
            ),
            errorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red),
            ),
            focusedErrorBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.red, width: 2),
            ),
            prefixIcon: const Icon(Icons.location_on, color: Colors.pink),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {
                            _suggestions = [];
                            _showSuggestions = false;
                          });
                        },
                      )
                    : null,
          ),
          validator: widget.validator,
        ),

        // Lista de sugerencias debajo del campo
        if (_showSuggestions && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[700]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = _suggestions[index];
                final description = suggestion['description'] ?? '';
                final mainText = suggestion['structured_formatting']
                        ?['main_text'] ??
                    description;
                final secondaryText = suggestion['structured_formatting']
                        ?['secondary_text'] ??
                    '';

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _onSuggestionSelected(suggestion),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: index < _suggestions.length - 1
                                ? Colors.grey[800]!
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Colors.pink, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mainText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (secondaryText.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    secondaryText,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
