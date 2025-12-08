import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doa_repartos/widgets/app_logo.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/widgets/address_search_field.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/services/validation_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart' as ll;

/// Página pública de registro de restaurantes (/nueva-donna)
/// Diseño inspirado en Rappi - limpio, moderno y profesional
class RestaurantRegistrationScreen extends StatefulWidget {
  const RestaurantRegistrationScreen({super.key});

  @override
  State<RestaurantRegistrationScreen> createState() => _RestaurantRegistrationScreenState();
}

class _RestaurantRegistrationScreenState extends State<RestaurantRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _restaurantNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _cuisineTypeController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // State
  int _currentStep = 0;
  bool _isSubmitting = false;
  LatLng? _selectedLocation;
  String? _selectedPlaceId;
  Map<String, dynamic>? _addressStructured;

  // Phone input state (country code + number-only field)
  final TextEditingController _phoneNumberOnlyController = TextEditingController();
  String _countryCode = 'MX'; // MX or US
  String _dialCode = '52'; // '52' for MX, '1' for US
  
  // Validation state
  String? _restaurantNameError;
  String? _emailError;
  String? _phoneError;
  bool _isValidatingRestaurantName = false;
  bool _isValidatingEmail = false;
  bool _isValidatingPhone = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  
  // Validation timers
  Timer? _restaurantNameTimer;
  Timer? _emailTimer;
  Timer? _phoneTimer;
  
  // Location coordinates
  double? _selectedLat;
  double? _selectedLon;
  
  // Images
  PlatformFile? _logoImage;
  PlatformFile? _coverImage;
  PlatformFile? _menuImage;
  PlatformFile? _ownerPhotoImage;
  
  @override
  void initState() {
    super.initState();
    // If _phoneController has a prefilled value, try to parse +code and digits
    final raw = _phoneController.text.trim();
    if (raw.isNotEmpty) {
      final parsed = _parsePhone(raw);
      _countryCode = parsed.countryCode;
      _dialCode = parsed.dialCode;
      _phoneNumberOnlyController.text = parsed.digits;
      // Ensure canonical full phone in controller
      _phoneController.text = '+${_dialCode}${parsed.digits}';
    } else {
      // Initialize full value with default country and empty digits
      _phoneController.text = '+$_dialCode';
    }
  }

  @override
  void dispose() {
    _restaurantNameController.dispose();
    _descriptionController.dispose();
    _cuisineTypeController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _phoneNumberOnlyController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    
    // Dispose validation timers
    _restaurantNameTimer?.cancel();
    _emailTimer?.cancel();
    _phoneTimer?.cancel();
    
    super.dispose();
  }

  /// Handle address selection from AddressSearchField
  void _onAddressSelected(Map<String, dynamic> placeDetails) {
    print('📍 [REGISTRATION] Dirección seleccionada desde AddressSearchField');
    print('   - placeDetails keys: ${placeDetails.keys.toList()}');
    
    // PlacesService.placeDetails retorna: {lat, lon, formatted_address, place_id, ...}
    // No geometry anidado
    final lat = (placeDetails['lat'] ?? placeDetails['latitude'])?.toDouble();
    final lon = (placeDetails['lon'] ?? placeDetails['lng'] ?? placeDetails['longitude'])?.toDouble();
    
    print('   - Coordenadas extraídas: lat=$lat, lon=$lon');
    
    if (lat != null && lon != null) {
      setState(() {
        _selectedLat = lat;
        _selectedLon = lon;
        _selectedLocation = LatLng(lat, lon);
        _selectedPlaceId = placeDetails['place_id'] ?? placeDetails['placeId'];
        _addressStructured = placeDetails;
      });
      // Revalidar formulario para limpiar error visual de dirección
      _formKey.currentState?.validate();
      
      print('✅ [REGISTRATION] Ubicación confirmada:');
      print('   - Dirección: ${_addressController.text}');
      print('   - Coordenadas: ($lat, $lon)');
      print('   - PlaceId: $_selectedPlaceId');
    } else {
      print('❌ [REGISTRATION] No se pudieron extraer coordenadas de placeDetails');
    }
  }

  /// Enviar formulario de registro
  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validar que se haya seleccionado ubicación
    if (_selectedLocation == null) {
      _showErrorDialog('Por favor selecciona la ubicación de tu restaurante en el mapa');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      print('🚀 [REGISTRATION] Iniciando registro de restaurante...');
      
      // 1. Crear usuario en Supabase Auth con verificación de email
      final authResponse = await SupabaseAuth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        userData: {
          'name': _ownerNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          // Store canonical role in English for backend consistency
          'role': 'restaurant',
          'lat': _selectedLat ?? _selectedLocation!.latitude,
          'lon': _selectedLon ?? _selectedLocation!.longitude,
          'address_structured': _addressStructured,
        },
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo crear el usuario');
      }

      final userId = authResponse.user!.id;
      print('✅ [REGISTRATION] Usuario creado: $userId');

      // 2. Asegurar perfil de usuario antes de crear el restaurante (idempotente)
      try {
        await SupabaseAuth.ensureUserProfile(
          userId: userId,
          email: _emailController.text.trim(),
          userData: {
            'name': _ownerNameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'address': _addressController.text.trim(),
            'role': 'restaurant',
            'lat': _selectedLat ?? _selectedLocation!.latitude,
            'lon': _selectedLon ?? _selectedLocation!.longitude,
            'address_structured': _addressStructured,
          },
        );
      } catch (e) {
        print('⚠️ [REGISTRATION] ensureUserProfile warning: $e');
      }

      // 3. Crear restaurante usando RPC atomic
      print('🧩 [REGISTRATION] Creando perfil de restaurante con RPC...');
      
      final result = await SupabaseConfig.client.rpc(
        RpcNames.registerRestaurantAtomic,
        params: {
          'p_user_id': userId,
          'p_restaurant_name': _restaurantNameController.text.trim(),
          'p_phone': _phoneController.text.trim(),
          'p_address': _addressController.text.trim(),
          'p_location_lat': _selectedLat ?? _selectedLocation!.latitude,
          'p_location_lon': _selectedLon ?? _selectedLocation!.longitude,
          if (_selectedPlaceId != null) 'p_location_place_id': _selectedPlaceId,
          if (_addressStructured != null) 'p_address_structured': _addressStructured,
        },
      );

      print('🔍 [REGISTRATION] RPC result: $result');

      if (result == null || result['success'] != true) {
        final errorMsg = result?['error'] ?? 'Unknown error creating restaurant';
        throw Exception(errorMsg);
      }

      print('✅ [REGISTRATION] Restaurant created: ${result['restaurant_id']}');
      print('✅ [REGISTRATION] Account created: ${result['account_id']}');

      // Verify user_preferences linkage for this user (helps confirm DB flow is complete)
      try {
        final prefs = await SupabaseConfig.client
            .from('user_preferences')
            .select('user_id, restaurant_id, updated_at')
            .eq('user_id', userId)
            .maybeSingle();
        if (prefs != null) {
          print('✅ [REGISTRATION] user_preferences row confirmed: restaurant_id=${prefs['restaurant_id']}');
        } else {
          print('⚠️ [REGISTRATION] user_preferences row not found immediately after RPC');
        }
      } catch (e) {
        print('ℹ️ [REGISTRATION] Could not verify user_preferences: $e');
      }

      print('✅ [REGISTRATION] Registro atómico completado');

      // 5. Mostrar mensaje de éxito
      if (mounted) {
        _showSuccessDialog();
      }

    } catch (e) {
      print('❌ [REGISTRATION] Error: $e');
      if (mounted) {
        _showErrorDialog('Error al registrar restaurante: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  /// Validar fortaleza de contraseña
  bool _isPasswordStrong(String password) {
    return password.length >= 8 &&
           password.contains(RegExp(r'[A-Z]')) &&
           password.contains(RegExp(r'[a-z]')) &&
           password.contains(RegExp(r'[0-9]'));
  }

  /// Validate restaurant name with debounce
  void _validateRestaurantName(String value) {
    _restaurantNameTimer?.cancel();
    
    if (value.trim().isEmpty) {
      setState(() {
        _restaurantNameError = null;
        _isValidatingRestaurantName = false;
      });
      return;
    }
    
    if (value.trim().length < 3) {
      setState(() {
        _restaurantNameError = 'Mínimo 3 caracteres';
        _isValidatingRestaurantName = false;
      });
      return;
    }
    
    setState(() => _isValidatingRestaurantName = true);
    
    _restaurantNameTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final error = await ValidationService.validateRestaurantNameRealtime(value);
        if (mounted) {
          setState(() {
            _restaurantNameError = error;
            _isValidatingRestaurantName = false;
          });
          // Revalidar el formulario para limpiar visualmente bordes rojos si ya es válido
          _formKey.currentState?.validate();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _restaurantNameError = 'Error validando nombre';
            _isValidatingRestaurantName = false;
          });
          _formKey.currentState?.validate();
        }
      }
    });
  }
  
  /// Validate email with debounce
  void _validateEmail(String value) {
    _emailTimer?.cancel();
    
    if (value.trim().isEmpty) {
      setState(() {
        _emailError = null;
        _isValidatingEmail = false;
      });
      return;
    }
    
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(value.trim())) {
      setState(() {
        _emailError = 'Ingresa un correo válido';
        _isValidatingEmail = false;
      });
      return;
    }
    
    setState(() => _isValidatingEmail = true);
    
    _emailTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        final error = await ValidationService.validateEmailRealtime(value);
        if (mounted) {
          setState(() {
            _emailError = error;
            _isValidatingEmail = false;
          });
          _formKey.currentState?.validate();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _emailError = 'Error validando correo';
            _isValidatingEmail = false;
          });
          _formKey.currentState?.validate();
        }
      }
    });
  }
  
  /// Validate phone with debounce
  void _validatePhone(String value) {
    _phoneTimer?.cancel();
    
    if (value.trim().isEmpty) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }
    
    // UX: validate digits length only
    if (value.trim().length < 8) {
      setState(() {
        _phoneError = 'Mínimo 8 dígitos';
        _isValidatingPhone = false;
      });
      return;
    }
    
    setState(() => _isValidatingPhone = true);
    
    _phoneTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        // Use the FULL canonical phone from controller (+lada+digits)
        final full = _phoneController.text.trim();
        final error = await ValidationService.validatePhoneRealtime(full);
        if (mounted) {
          setState(() {
            _phoneError = error;
            _isValidatingPhone = false;
          });
          _formKey.currentState?.validate();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _phoneError = 'Error validando teléfono';
            _isValidatingPhone = false;
          });
          _formKey.currentState?.validate();
        }
      }
    });
  }

  /// Mostrar diálogo de éxito
  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('¡Registro Exitoso!'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu solicitud ha sido enviada exitosamente.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('📧 Revisa tu correo electrónico para verificar tu cuenta.'),
            SizedBox(height: 16),
            Text('Nuestro equipo revisará tu solicitud en 24-48 horas y te contactaremos pronto.'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF2D55), foregroundColor: Colors.white),
            child: const Text('Ir al Login'),
          ),
        ],
      ),
    );
  }

  /// Mostrar diálogo de error
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red),
            SizedBox(width: 8),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(maxWidth: isDesktop ? 500 : double.infinity),
            padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 24, vertical: 32),
            child: Card(
              elevation: isDesktop ? 4 : 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isDesktop ? 16 : 0)),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppLogo(size: 64, showTitle: false),
                      const SizedBox(height: 24),
                      Text('Vende en Doña', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A), fontSize: 28)),
                      const SizedBox(height: 8),
                      Text('Completa tus datos para empezar', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF666666))),
                      const SizedBox(height: 32),

                      _buildValidatedTextField(
                        controller: _restaurantNameController,
                        label: 'Nombre del restaurante',
                        hint: 'Ej: Tacos El Güero',
                        icon: Icons.store_outlined,
                        error: _restaurantNameError,
                        isValidating: _isValidatingRestaurantName,
                        onChanged: _validateRestaurantName,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Ingresa el nombre del restaurante';
                          if (value.trim().length < 3) return 'Mínimo 3 caracteres';
                          if (_restaurantNameError != null) return _restaurantNameError;
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      _buildPhoneField(
                        label: 'Teléfono',
                        hint: '656-123-4567',
                        error: _phoneError,
                        isValidating: _isValidatingPhone,
                        validator: (digits) {
                          if (digits == null || digits.trim().isEmpty) return 'Ingresa el teléfono';
                          if (digits.trim().length < 8) return 'Ingresa un teléfono válido';
                          if (_phoneError != null) return _phoneError;
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      Theme(
                        data: Theme.of(context).copyWith(
                          inputDecorationTheme: InputDecorationTheme(
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFFF2D55), width: 2),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            labelStyle: const TextStyle(color: Color(0xFF666666)),
                            hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
                            prefixIconColor: const Color(0xFF666666),
                          ),
                          textTheme: Theme.of(context).textTheme.copyWith(
                            bodyLarge: const TextStyle(color: Color(0xFF1A1A1A)),
                          ),
                        ),
                        child: AddressSearchField(
                          controller: _addressController,
                          labelText: 'Dirección del restaurante',
                          hintText: 'Buscar dirección...',
                          onPlaceSelected: _onAddressSelected,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Busca y confirma tu dirección';
                            if (_selectedLocation == null && (_selectedLat == null || _selectedLon == null)) return 'Confirma la ubicación';
                            return null;
                          },
                        ),
                      ),
                      
                      if (_selectedLocation != null || (_selectedLat != null && _selectedLon != null)) ...[
                        const SizedBox(height: 16),
                        // Mini mapa informativo
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Stack(
                              children: [
                                // Background placeholder
                                Container(color: const Color(0xFFEEEEEE)),
                                // Map Layer
                                fm.FlutterMap(
                                  options: fm.MapOptions(
                                    initialCenter: ll.LatLng(_selectedLat!, _selectedLon!),
                                    initialZoom: 16,
                                    interactionOptions: const fm.InteractionOptions(
                                      flags: fm.InteractiveFlag.none,
                                    ),
                                  ),
                                  children: [
                                    fm.TileLayer(
                                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName: 'com.doa.repartos',
                                    ),
                                    fm.MarkerLayer(
                                      markers: [
                                        fm.Marker(
                                          point: ll.LatLng(_selectedLat!, _selectedLon!),
                                          width: 48,
                                          height: 48,
                                          child: const Icon(Icons.location_on, color: Colors.red, size: 48),
                                          alignment: Alignment.topCenter, 
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF4CAF50), width: 1)),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Text('Ubicación confirmada', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w500))),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                      const SizedBox(height: 32),

                      Text('Información del responsable', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
                      const SizedBox(height: 20),

                      _buildTextField(controller: _ownerNameController, label: 'Nombre completo', hint: 'Juan Pérez', icon: Icons.person_outline, validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Ingresa tu nombre completo';
                        if (value.trim().length < 3) return 'Mínimo 3 caracteres';
                        return null;
                      }),
                      const SizedBox(height: 20),

                      _buildValidatedTextField(
                        controller: _emailController,
                        label: 'Correo electrónico',
                        hint: 'tu@correo.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        error: _emailError,
                        isValidating: _isValidatingEmail,
                        onChanged: _validateEmail,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Ingresa tu correo';
                          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                          if (!emailRegex.hasMatch(value.trim())) return 'Ingresa un correo válido';
                          if (_emailError != null) return _emailError;
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      _buildPasswordField(
                        controller: _passwordController,
                        label: 'Contraseña',
                        hint: 'Mínimo 8 caracteres',
                        isVisible: _passwordVisible,
                        onToggleVisibility: () => setState(() => _passwordVisible = !_passwordVisible),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Ingresa una contraseña';
                          if (value.length < 8) return 'Mínimo 8 caracteres';
                          if (!_isPasswordStrong(value)) return 'Debe incluir mayúsculas, minúsculas y números';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      _buildPasswordField(
                        controller: _confirmPasswordController,
                        label: 'Confirmar contraseña',
                        hint: 'Vuelve a ingresar tu contraseña',
                        isVisible: _confirmPasswordVisible,
                        onToggleVisibility: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Confirma tu contraseña';
                          if (value != _passwordController.text) return 'Las contraseñas no coinciden';
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Te enviaremos un email de confirmación', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 4),
                                  Text('Nuestro equipo revisará tu solicitud en 24-48 horas', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF666666))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submitRegistration,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF2D55),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            disabledBackgroundColor: const Color(0xFFFFCDD2),
                          ),
                          child: _isSubmitting ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)) : const Text('Enviar solicitud', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                          style: TextButton.styleFrom(foregroundColor: const Color(0xFF666666)),
                          child: const Text('¿Ya tienes cuenta? Inicia sesión', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===== Phone field with country code (MX/US) =====
  Widget _buildPhoneField({
    required String label,
    required String hint,
    String? error,
    bool isValidating = false,
    String? Function(String?)? validator, // receives digits-only value
  }) {
    Widget? suffixIcon;
    final hasDigits = _phoneNumberOnlyController.text.isNotEmpty;
    if (isValidating) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF2D55))),
      );
    } else if (hasDigits && error == null && !isValidating) {
      suffixIcon = const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22);
    }

    // Small pill for prefix country code selector
    Widget countryPrefix() {
      final flag = _countryCode == 'US' ? '🇺🇸' : '🇲🇽';
      final dial = _dialCode;
      return Padding(
        padding: const EdgeInsets.only(left: 8, right: 6),
        child: PopupMenuButton<String>(
          tooltip: 'Seleccionar lada',
          onSelected: (value) {
            setState(() {
              if (value == 'US') {
                _countryCode = 'US';
                _dialCode = '1';
              } else {
                _countryCode = 'MX';
                _dialCode = '52';
              }
              // Update full phone in external controller
              final digits = _onlyDigits(_phoneNumberOnlyController.text);
              _phoneNumberOnlyController.text = digits; // sanitize
              _phoneController.text = '+$_dialCode$digits';
              // Keep validation UX based on digits only
              _validatePhone(digits);
            });
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'MX',
              child: Row(
                children: const [
                  Text('🇲🇽', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text('MX +52'),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'US',
              child: Row(
                children: const [
                  Text('🇺🇸', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Text('US +1'),
                ],
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDDDDDD), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(flag, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text('+$dial', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF333333))),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF666666)),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _phoneNumberOnlyController,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (value) {
            // Keep only digits in the visual field
            final digits = _onlyDigits(value);
            if (digits != value) {
              final selectionIndex = digits.length;
              _phoneNumberOnlyController.value = TextEditingValue(
                text: digits,
                selection: TextSelection.collapsed(offset: selectionIndex),
              );
            }
            // Update external controller with full phone value +lada
            _phoneController.text = '+$_dialCode$digits';
            // Trigger existing validation logic based on digits only
            _validatePhone(digits);
          },
          autovalidateMode: AutovalidateMode.always,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
            prefixIcon: const Icon(Icons.phone_outlined, color: Color(0xFF666666), size: 22),
            prefix: countryPrefix(),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF5350) : const Color(0xFFDDDDDD),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF5350) : const Color(0xFFFF2D55),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          // Validate using provided validator but pass digits-only value
          validator: (value) => validator?.call(_onlyDigits(value ?? '')),
        ),
        if (error != null && !isValidating) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFEF5350),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _onlyDigits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  ({String countryCode, String dialCode, String digits}) _parsePhone(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s|-'), '');
    String cc = 'MX';
    String dial = '52';
    String digits = cleaned.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.startsWith('+52')) {
      cc = 'MX';
      dial = '52';
      digits = cleaned.substring(3).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('+1')) {
      cc = 'US';
      dial = '1';
      digits = cleaned.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('52')) {
      cc = 'MX';
      dial = '52';
      digits = cleaned.substring(2).replaceAll(RegExp(r'[^0-9]'), '');
    } else if (cleaned.startsWith('1')) {
      cc = 'US';
      dial = '1';
      digits = cleaned.substring(1).replaceAll(RegExp(r'[^0-9]'), '');
    }
    return (countryCode: cc, dialCode: dial, digits: digits);
  }

  // Small reusable pieces to keep build method clean

// (No extra classes required)

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
        prefixIcon: Icon(icon, color: Color(0xFF666666), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFF2D55), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }

  Widget _buildValidatedTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? error,
    bool isValidating = false,
    Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    Widget? suffixIcon;
    
    if (isValidating) {
      suffixIcon = const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFFFF2D55),
          ),
        ),
      );
    } else if (controller.text.isNotEmpty && error == null && !isValidating) {
      suffixIcon = const Icon(
        Icons.check_circle,
        color: Color(0xFF4CAF50),
        size: 22,
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          autovalidateMode: AutovalidateMode.always,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
            prefixIcon: Icon(icon, color: Color(0xFF666666), size: 22),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF5350) : const Color(0xFFDDDDDD),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: error != null ? const Color(0xFFEF5350) : const Color(0xFFFF2D55),
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          validator: validator,
        ),
        if (error != null && !isValidating) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFEF5350),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !isVisible,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF666666), size: 22),
        suffixIcon: IconButton(
          icon: Icon(
            isVisible ? Icons.visibility_off : Icons.visibility,
            color: const Color(0xFF666666),
            size: 22,
          ),
          onPressed: onToggleVisibility,
        ),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFFF2D55), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      validator: validator,
    );
  }
}
