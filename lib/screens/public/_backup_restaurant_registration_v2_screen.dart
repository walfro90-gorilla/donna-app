import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doa_repartos/widgets/app_logo.dart';
import 'package:doa_repartos/widgets/address_search_field.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/services/validation_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:file_picker/file_picker.dart';

/// 🆕 Pantalla MEJORADA de registro de restaurantes
/// Wizard de 3 pasos con carga de imágenes
class RestaurantRegistrationV2Screen extends StatefulWidget {
  const RestaurantRegistrationV2Screen({super.key});

  @override
  State<RestaurantRegistrationV2Screen> createState() => _RestaurantRegistrationV2ScreenState();
}

class _RestaurantRegistrationV2ScreenState extends State<RestaurantRegistrationV2Screen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  
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
  
  // Validación en tiempo real
  String? _emailError;
  String? _phoneError;
  String? _restaurantNameError;
  bool _isValidatingEmail = false;
  bool _isValidatingPhone = false;
  bool _isValidatingRestaurantName = false;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  
  // Location coordinates
  double? _selectedLat;
  double? _selectedLon;
  
  // Images
  PlatformFile? _logoImage;
  PlatformFile? _coverImage;
  PlatformFile? _menuImage;
  PlatformFile? _ownerPhotoImage;

  // Tipos de cocina
  final List<String> _cuisineTypes = [
    'Mexicana',
    'Italiana',
    'China',
    'Japonesa',
    'Americana',
    'Árabe',
    'Vegetariana',
    'Mariscos',
    'Postres',
    'Café & Snacks',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    // Listeners para validación en tiempo real
    _restaurantNameController.addListener(_validateRestaurantName);
    _emailController.addListener(_validateEmail);
    _phoneController.addListener(_validatePhone);
  }

  @override
  void dispose() {
    _restaurantNameController.removeListener(_validateRestaurantName);
    _emailController.removeListener(_validateEmail);
    _phoneController.removeListener(_validatePhone);
    _restaurantNameController.dispose();
    _descriptionController.dispose();
    _cuisineTypeController.dispose();
    _ownerNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Validar nombre del restaurante en tiempo real (con debounce)
  Future<void> _validateRestaurantName() async {
    final value = _restaurantNameController.text.trim();
    
    if (value.isEmpty) {
      setState(() {
        _restaurantNameError = null;
        _isValidatingRestaurantName = false;
      });
      return;
    }

    setState(() => _isValidatingRestaurantName = true);
    
    // Debounce: esperar 800ms antes de validar
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Verificar si el valor cambió durante el debounce
    if (_restaurantNameController.text.trim() != value) return;
    
    final error = await ValidationService.validateRestaurantNameRealtime(value);
    
    if (mounted && _restaurantNameController.text.trim() == value) {
      setState(() {
        _restaurantNameError = error;
        _isValidatingRestaurantName = false;
      });
    }
  }

  /// Validar email en tiempo real (con debounce)
  Future<void> _validateEmail() async {
    final value = _emailController.text.trim();
    
    if (value.isEmpty) {
      setState(() {
        _emailError = null;
        _isValidatingEmail = false;
      });
      return;
    }

    setState(() => _isValidatingEmail = true);
    
    // Debounce: esperar 800ms antes de validar
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Verificar si el valor cambió durante el debounce
    if (_emailController.text.trim() != value) return;
    
    final error = await ValidationService.validateEmailRealtime(value);
    
    if (mounted && _emailController.text.trim() == value) {
      setState(() {
        _emailError = error;
        _isValidatingEmail = false;
      });
    }
  }

  /// Validar teléfono en tiempo real (con debounce)
  Future<void> _validatePhone() async {
    final value = _phoneController.text.trim();
    
    if (value.isEmpty) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }

    setState(() => _isValidatingPhone = true);
    
    // Debounce: esperar 800ms antes de validar
    await Future.delayed(const Duration(milliseconds: 800));
    
    // Verificar si el valor cambió durante el debounce
    if (_phoneController.text.trim() != value) return;
    
    final error = await ValidationService.validatePhoneRealtime(value);
    
    if (mounted && _phoneController.text.trim() == value) {
      setState(() {
        _phoneError = error;
        _isValidatingPhone = false;
      });
    }
  }

  /// Validar paso actual
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _restaurantNameController.text.trim().isNotEmpty &&
               _cuisineTypeController.text.trim().isNotEmpty &&
               _addressController.text.trim().isNotEmpty &&
               _selectedLocation != null;
      case 1:
        return _logoImage != null && _coverImage != null;
      case 2:
        return _ownerNameController.text.trim().isNotEmpty &&
               _emailController.text.trim().isNotEmpty &&
               _phoneController.text.trim().isNotEmpty &&
               _passwordController.text.trim().isNotEmpty &&
               _confirmPasswordController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  /// Ir al siguiente paso
  void _nextStep() {
    // Validar paso actual antes de avanzar
    if (_currentStep == 0) {
      print('🔍 [REGISTRO_V2] Validando Paso 1 (Información de Negocio)...');
      print('   - Nombre: "${_restaurantNameController.text.trim()}"');
      print('   - Cocina: "${_cuisineTypeController.text.trim()}"');
      print('   - Dirección (texto): "${_addressController.text.trim()}"');
      print('   - Ubicación (LatLng): $_selectedLocation');
      print('   - PlaceId: $_selectedPlaceId');
      
      // Paso 1: Validar campos de negocio
      if (_restaurantNameController.text.trim().isEmpty) {
        print('❌ [REGISTRO_V2] Falta nombre del restaurante');
        _showSnackBar('Ingresa el nombre del restaurante', Colors.orange);
        return;
      }
      if (_cuisineTypeController.text.trim().isEmpty) {
        print('❌ [REGISTRO_V2] Falta tipo de cocina');
        _showSnackBar('Selecciona el tipo de cocina', Colors.orange);
        return;
      }
      if (_addressController.text.trim().isEmpty) {
        print('❌ [REGISTRO_V2] Falta texto de dirección');
        _showSnackBar('Busca y selecciona la dirección del restaurante', Colors.orange);
        return;
      }
      if (_selectedLocation == null) {
        print('❌ [REGISTRO_V2] Falta coordenadas de ubicación (_selectedLocation es null)');
        print('   DIAGNÓSTICO: El texto de dirección está presente pero las coordenadas no.');
        print('   POSIBLE CAUSA: El modal no está retornando correctamente el resultado.');
        _showSnackBar('Confirma la ubicación en el mapa', Colors.orange);
        return;
      }
      print('✅ [REGISTRO_V2] Paso 1 validado correctamente');
    } else if (_currentStep == 1) {
      // Paso 2: Validar imágenes obligatorias
      if (_logoImage == null) {
        _showSnackBar('Sube el logo del restaurante', Colors.orange);
        return;
      }
      if (_coverImage == null) {
        _showSnackBar('Sube una foto de portada', Colors.orange);
        return;
      }
    }

    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Volver al paso anterior
  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Handle address selection from AddressSearchField
  void _onAddressSelected(Map<String, dynamic> placeDetails) {
    print('📍 [REGISTRO_V2] Dirección seleccionada desde AddressSearchField');
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
      
      print('✅ [REGISTRO_V2] Ubicación confirmada:');
      print('   - Dirección: ${_addressController.text}');
      print('   - Coordenadas: ($lat, $lon)');
      print('   - PlaceId: $_selectedPlaceId');
    } else {
      print('❌ [REGISTRO_V2] No se pudieron extraer coordenadas de placeDetails');
    }
  }

  /// Enviar formulario
  Future<void> _submitRegistration() async {
    // Validar paso 3 antes de enviar
    if (_ownerNameController.text.trim().isEmpty) {
      _showSnackBar('Ingresa el nombre del responsable', Colors.orange);
      return;
    }
    if (_emailController.text.trim().isEmpty) {
      _showSnackBar('Ingresa el correo electrónico', Colors.orange);
      return;
    }
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(_emailController.text.trim())) {
      _showSnackBar('Ingresa un correo válido', Colors.orange);
      return;
    }
    if (_phoneController.text.trim().isEmpty) {
      _showSnackBar('Ingresa el teléfono', Colors.orange);
      return;
    }
    if (_passwordController.text.trim().isEmpty) {
      _showSnackBar('Ingresa una contraseña', Colors.orange);
      return;
    }
    if (_passwordController.text.trim().length < 8) {
      _showSnackBar('La contraseña debe tener al menos 8 caracteres', Colors.orange);
      return;
    }
    final hasUpperCase = RegExp(r'[A-Z]').hasMatch(_passwordController.text.trim());
    final hasLowerCase = RegExp(r'[a-z]').hasMatch(_passwordController.text.trim());
    final hasDigit = RegExp(r'[0-9]').hasMatch(_passwordController.text.trim());
    if (!hasUpperCase || !hasLowerCase || !hasDigit) {
      _showSnackBar('La contraseña debe contener mayúsculas, minúsculas y números', Colors.orange);
      return;
    }
    if (_confirmPasswordController.text.trim() != _passwordController.text.trim()) {
      _showSnackBar('Las contraseñas no coinciden', Colors.orange);
      return;
    }

    // Validar que no haya errores de validación asíncrona
    if (_restaurantNameError != null) {
      _showSnackBar(_restaurantNameError!, const Color(0xFFEF5350));
      return;
    }
    if (_emailError != null) {
      _showSnackBar(_emailError!, const Color(0xFFEF5350));
      return;
    }
    if (_phoneError != null) {
      _showSnackBar(_phoneError!, const Color(0xFFEF5350));
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      print('🚀 [REGISTRATION] Iniciando registro de restaurante...');
      
      // 1. Crear usuario en Supabase Auth con la contraseña elegida
      final authResponse = await SupabaseAuth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        userData: {
          'name': _ownerNameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'role': 'restaurante',
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

      // 3. Subir imágenes del usuario (dueño)
      String? ownerPhotoUrl;
      if (_ownerPhotoImage != null) {
        ownerPhotoUrl = await StorageService.uploadProfileImage(userId, _ownerPhotoImage!);
      }

      // 4. Actualizar perfil del usuario con imagen
      if (ownerPhotoUrl != null) {
        await SupabaseConfig.client.from('users').update({
          'profile_image_url': ownerPhotoUrl,
        }).eq('id', userId);
      }

      // 5. Crear entrada en tabla restaurants (sin imágenes primero)
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .insert({
            'user_id': userId,
            'name': _restaurantNameController.text.trim(),
            'description': _descriptionController.text.trim().isEmpty 
                ? null 
                : _descriptionController.text.trim(),
            'cuisine_type': _cuisineTypeController.text.trim(),
            'status': 'pending',
            'location_lat': _selectedLat ?? _selectedLocation?.latitude,
            'location_lon': _selectedLon ?? _selectedLocation?.longitude,
            'location_place_id': _selectedPlaceId,
            'address': _addressController.text.trim(),
            'address_structured': _addressStructured,
            'phone': _phoneController.text.trim(),
            'online': false,
          })
          .select()
          .single();

      final restaurantId = restaurantResponse['id'];
      print('✅ [REGISTRATION] Restaurante creado: $restaurantId');

      // 6. Subir imágenes del restaurante
      String? logoUrl;
      String? coverUrl;
      String? menuUrl;

      if (_logoImage != null) {
        logoUrl = await StorageService.uploadRestaurantLogo(restaurantId, _logoImage!);
      }
      if (_coverImage != null) {
        coverUrl = await StorageService.uploadRestaurantCover(restaurantId, _coverImage!);
      }
      if (_menuImage != null) {
        menuUrl = await StorageService.uploadRestaurantMenu(restaurantId, _menuImage!);
      }

      // 7. Actualizar restaurante con URLs de imágenes
      await SupabaseConfig.client.from('restaurants').update({
        'logo_url': logoUrl,
        'cover_image_url': coverUrl,
        'menu_image_url': menuUrl,
      }).eq('id', restaurantId);

      // 8. Crear cuenta financiera
      await SupabaseConfig.client.from('accounts').insert({
        'user_id': userId,
        'account_type': 'restaurant',
        'balance': 0.00,
      });

      print('✅ [REGISTRATION] Registro completado exitosamente');

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

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

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
            Text('Tu solicitud ha sido enviada exitosamente.', 
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('📧 Revisa tu correo electrónico para verificar tu cuenta.'),
            SizedBox(height: 16),
            Text('✅ Tu contraseña ha sido configurada correctamente. Podrás iniciar sesión una vez que verifiques tu correo y tu cuenta sea aprobada.'),
            SizedBox(height: 16),
            Text('Nuestro equipo revisará tu solicitud y te contactaremos en 24-48 horas.'),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed('/login');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2D55), 
              foregroundColor: Colors.white
            ),
            child: const Text('Ir al Login'),
          ),
        ],
      ),
    );
  }

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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const AppLogo(size: 32, showTitle: false),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Progress Indicator
            _buildProgressIndicator(),
            
            // Content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1BusinessInfo(isDesktop),
                  _buildStep2Images(isDesktop),
                  _buildStep3OwnerInfo(isDesktop),
                ],
              ),
            ),
            
            // Bottom Navigation
            _buildBottomNavigation(isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
      color: Colors.white,
      child: Row(
        children: [
          _buildStepIndicator(0, 'Negocio'),
          _buildProgressLine(0),
          _buildStepIndicator(1, 'Imágenes'),
          _buildProgressLine(1),
          _buildStepIndicator(2, 'Responsable'),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? const Color(0xFF4CAF50)
                  : isActive
                      ? const Color(0xFFFF2D55)
                      : const Color(0xFFEEEEEE),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? Colors.white : const Color(0xFF999999),
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              color: isActive ? const Color(0xFF333333) : const Color(0xFF999999),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    final isCompleted = _currentStep > step;
    
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 32),
        color: isCompleted ? const Color(0xFF4CAF50) : const Color(0xFFEEEEEE),
      ),
    );
  }

  Widget _buildStep1BusinessInfo(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Información del Negocio',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Cuéntanos sobre tu restaurante',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 32),

              _buildTextField(
                controller: _restaurantNameController,
                label: 'Nombre del restaurante',
                hint: 'Ej: Tacos El Güero',
                icon: Icons.store,
                suffixIcon: _isValidatingRestaurantName
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _restaurantNameError == null && _restaurantNameController.text.trim().isNotEmpty
                        ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                        : null,
                errorText: _restaurantNameError,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el nombre del restaurante';
                  }
                  if (_restaurantNameError != null) {
                    return _restaurantNameError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              DropdownButtonFormField<String>(
                value: _cuisineTypeController.text.isEmpty ? null : _cuisineTypeController.text,
                decoration: InputDecoration(
                  labelText: 'Tipo de cocina',
                  prefixIcon: const Icon(Icons.restaurant_menu, color: Color(0xFFFF2D55)),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                ),
                items: _cuisineTypes.map((type) => DropdownMenuItem(
                  value: type,
                  child: Text(type),
                )).toList(),
                onChanged: (value) {
                  if (value != null) {
                    _cuisineTypeController.text = value;
                  }
                },
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _descriptionController,
                label: 'Descripción (opcional)',
                hint: 'Describe tu especialidad...',
                icon: Icons.description,
                maxLines: 3,
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
                    prefixIconColor: const Color(0xFFFF2D55),
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
                    if (value == null || value.trim().isEmpty) {
                      return 'Busca y confirma tu dirección';
                    }
                    if (_selectedLocation == null && (_selectedLat == null || _selectedLon == null)) {
                      return 'Confirma la ubicación';
                    }
                    return null;
                  },
                ),
              ),
              
              if (_selectedLocation != null || (_selectedLat != null && _selectedLon != null)) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50), width: 1),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Ubicación confirmada',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF2E7D32),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if ((_selectedLocation == null && (_selectedLat == null || _selectedLon == null)) && _addressController.text.trim().isEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFB74D)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Escribe la dirección de tu restaurante en el campo de arriba',
                          style: TextStyle(color: Color(0xFFE65100), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep2Images(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Imágenes del Restaurante',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sube fotos de calidad para atraer más clientes',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 32),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _logoImage != null ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _logoImage != null ? Icons.check_circle : Icons.cloud_upload,
                      color: _logoImage != null ? Colors.green.shade600 : Colors.orange.shade600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _logoImage != null ? '✓ Logo cargado' : 'Sube tu logo (requerido)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _logoImage != null ? Colors.green.shade700 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ImageUploadField(
                label: 'Logo del restaurante',
                hint: 'Tu logo o marca',
                icon: Icons.image,
                isRequired: true,
                imageUrl: null,
                helpText: 'Logo cuadrado recomendado (mínimo 512x512)',
                onImageSelected: (file) => setState(() => _logoImage = file),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _coverImage != null ? Colors.green.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _coverImage != null ? Icons.check_circle : Icons.cloud_upload,
                      color: _coverImage != null ? Colors.green.shade600 : Colors.orange.shade600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _coverImage != null ? '✓ Portada cargada' : 'Sube foto de portada (requerido)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _coverImage != null ? Colors.green.shade700 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ImageUploadField(
                label: 'Foto de portada',
                hint: 'Imagen principal del restaurante',
                icon: Icons.photo_camera,
                isRequired: true,
                imageUrl: null,
                helpText: 'Foto horizontal del restaurante, comida o ambiente',
                aspectRatio: 16 / 9,
                onImageSelected: (file) => setState(() => _coverImage = file),
              ),
              const SizedBox(height: 24),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _menuImage != null ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _menuImage != null ? Icons.check_circle : Icons.menu_book,
                      color: _menuImage != null ? Colors.green.shade600 : Colors.grey.shade600,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _menuImage != null ? '✓ Menú cargado' : 'Foto del menú (opcional)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _menuImage != null ? Colors.green.shade700 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ImageUploadField(
                label: 'Foto del menú (opcional)',
                hint: 'Foto del menú físico',
                icon: Icons.menu_book,
                imageUrl: null,
                helpText: 'Ayuda a los clientes a conocer tus platillos',
                onImageSelected: (file) => setState(() => _menuImage = file),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep3OwnerInfo(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Información del Responsable',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Datos del propietario o encargado',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF666666),
                ),
              ),
              const SizedBox(height: 32),

              ImageUploadField(
                label: 'Foto del responsable (opcional)',
                hint: 'Foto de perfil',
                icon: Icons.person,
                imageUrl: null,
                helpText: 'Foto del dueño o encargado del restaurante',
                onImageSelected: (file) => setState(() => _ownerPhotoImage = file),
              ),
              const SizedBox(height: 24),

              _buildTextField(
                controller: _ownerNameController,
                label: 'Nombre completo',
                hint: 'Juan Pérez',
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa tu nombre completo';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _emailController,
                label: 'Correo electrónico',
                hint: 'tu@correo.com',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                suffixIcon: _isValidatingEmail
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _emailError == null && _emailController.text.trim().isNotEmpty
                        ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                        : null,
                errorText: _emailError,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa tu correo';
                  }
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Ingresa un correo válido';
                  }
                  if (_emailError != null) {
                    return _emailError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _phoneController,
                label: 'Teléfono',
                hint: '656-123-4567',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                suffixIcon: _isValidatingPhone
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _phoneError == null && _phoneController.text.trim().isNotEmpty
                        ? const Icon(Icons.check_circle, color: Color(0xFF4CAF50))
                        : null,
                errorText: _phoneError,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa el teléfono';
                  }
                  if (_phoneError != null) {
                    return _phoneError;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Password fields
              _buildPasswordField(
                controller: _passwordController,
                label: 'Contraseña',
                hint: 'Mínimo 8 caracteres',
                isVisible: _passwordVisible,
                onToggleVisibility: () => setState(() => _passwordVisible = !_passwordVisible),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingresa una contraseña';
                  }
                  if (value.trim().length < 8) {
                    return 'Mínimo 8 caracteres';
                  }
                  final hasUpperCase = RegExp(r'[A-Z]').hasMatch(value);
                  final hasLowerCase = RegExp(r'[a-z]').hasMatch(value);
                  final hasDigit = RegExp(r'[0-9]').hasMatch(value);
                  if (!hasUpperCase || !hasLowerCase || !hasDigit) {
                    return 'Debe contener mayúsculas, minúsculas y números';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildPasswordField(
                controller: _confirmPasswordController,
                label: 'Confirmar contraseña',
                hint: 'Repite tu contraseña',
                isVisible: _confirmPasswordVisible,
                onToggleVisibility: () => setState(() => _confirmPasswordVisible = !_confirmPasswordVisible),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Confirma tu contraseña';
                  }
                  if (value.trim() != _passwordController.text.trim()) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Recibirás un email de verificación. Nuestro equipo revisará tu solicitud en 24-48 horas.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(bool isDesktop) {
    return Container(
      padding: EdgeInsets.all(isDesktop ? 32 : 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFFDDDDDD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Atrás', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : (_currentStep < 2 ? _nextStep : _submitRegistration),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF2D55),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      _currentStep < 2 ? 'Siguiente' : 'Enviar solicitud',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
    String? errorText,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
            prefixIcon: Icon(icon, color: const Color(0xFFFF2D55), size: 22),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null ? const Color(0xFFEF5350) : const Color(0xFFDDDDDD),
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null ? const Color(0xFFEF5350) : const Color(0xFFDDDDDD),
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: errorText != null ? const Color(0xFFEF5350) : const Color(0xFFFF2D55),
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
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBEE),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFEF5350), width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFEF5350), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    errorText,
                    style: const TextStyle(
                      color: Color(0xFFC62828),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
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
    required String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          obscureText: !isVisible,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFBBBBBB)),
            prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFF2D55), size: 22),
            suffixIcon: IconButton(
              icon: Icon(
                isVisible ? Icons.visibility : Icons.visibility_off,
                color: const Color(0xFF999999),
              ),
              onPressed: onToggleVisibility,
            ),
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
          ),
          validator: validator,
        ),
      ],
    );
  }
}
