import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doa_repartos/widgets/app_logo.dart';
import 'package:doa_repartos/widgets/address_search_field.dart';
import 'package:doa_repartos/widgets/address_picker_modal.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/services/validation_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/supabase/supabase_rpc.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:doa_repartos/widgets/phone_dial_input.dart';
import 'dart:async';

/// Página pública de registro de repartidores (/nuevo-repartidor)
/// Diseño responsive y profesional con todos los campos del schema
class DeliveryAgentRegistrationScreen extends StatefulWidget {
  const DeliveryAgentRegistrationScreen({super.key});

  @override
  State<DeliveryAgentRegistrationScreen> createState() => _DeliveryAgentRegistrationScreenState();
}

class _DeliveryAgentRegistrationScreenState extends State<DeliveryAgentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();
  
  // Controllers - Información Personal
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // Controllers - Información del Vehículo
  final _vehiclePlateController = TextEditingController();
  final _vehicleModelController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  
  // Controllers - Contacto de Emergencia
  final _emergencyContactNameController = TextEditingController();
  final _emergencyContactPhoneController = TextEditingController();
  
  // State
  int _currentStep = 0;
  bool _isSubmitting = false;
  String _selectedVehicleType = 'motocicleta';
  
  // Location
  double? _selectedLat;
  double? _selectedLon;
  String? _selectedPlaceId;
  Map<String, dynamic>? _addressStructured;
  
  // Validation state
  String? _emailError;
  String? _phoneError;
  bool _isValidatingEmail = false;
  bool _isValidatingPhone = false;
  Timer? _emailTimer;
  Timer? _phoneTimer;
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  
  // Images/Documents
  PlatformFile? _profileImage;
  PlatformFile? _idDocumentFront;
  PlatformFile? _idDocumentBack;
  PlatformFile? _vehiclePhoto;
  PlatformFile? _vehicleRegistration;
  PlatformFile? _vehicleInsurance;

  final List<Map<String, dynamic>> _vehicleTypes = [
    {'value': 'bicicleta', 'label': 'Bicicleta', 'icon': Icons.pedal_bike},
    {'value': 'motocicleta', 'label': 'Motocicleta', 'icon': Icons.two_wheeler},
    {'value': 'auto', 'label': 'Automóvil', 'icon': Icons.directions_car},
    {'value': 'pie', 'label': 'A pie', 'icon': Icons.directions_walk},
    {'value': 'otro', 'label': 'Otro', 'icon': Icons.help_outline},
  ];

  @override
  void initState() {
    super.initState();
    // Si el usuario borra el texto de dirección, limpiar coordenadas seleccionadas
    _addressController.addListener(_onAddressTextChanged);
  }

  void _onAddressTextChanged() {
    if (_addressController.text.trim().isEmpty) {
      if (_selectedLat != null || _selectedLon != null || _selectedPlaceId != null) {
        setState(() {
          _selectedLat = null;
          _selectedLon = null;
          _selectedPlaceId = null;
          _addressStructured = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.removeListener(_onAddressTextChanged);
    _addressController.dispose();
    _vehiclePlateController.dispose();
    _vehicleModelController.dispose();
    _vehicleColorController.dispose();
    _emergencyContactNameController.dispose();
    _emergencyContactPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pageController.dispose();
    _emailTimer?.cancel();
    _phoneTimer?.cancel();
    super.dispose();
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0: // Información Personal
        return _nameController.text.trim().isNotEmpty &&
               _emailController.text.trim().isNotEmpty &&
               _phoneController.text.trim().isNotEmpty &&
               _addressController.text.trim().isNotEmpty &&
               _selectedLat != null &&
               _selectedLon != null &&
               _emailError == null &&
               _phoneError == null &&
               _passwordController.text.trim().isNotEmpty &&
               _confirmPasswordController.text.trim().isNotEmpty;
      case 1: // Información del Vehículo
        return _vehiclePlateController.text.trim().isNotEmpty;
      case 2: // Documentos
        return _idDocumentFront != null && _idDocumentBack != null;
      default:
        return false;
    }
  }

  void _nextStep() {
    if (!_validateCurrentStep()) {
      _showSnackBar('Por favor completa todos los campos obligatorios', Colors.orange);
      return;
    }

    if (_currentStep < 2) {
      setState(() => _currentStep++);
      _pageController.animateToPage(_currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(_currentStep, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _onAddressSelected(Map<String, dynamic> placeDetails) {
    // AddressSearchField + PlacesService.placeDetails retornan lat/lon a nivel raíz
    // con llaves 'lat' y 'lon' (y variantes de compatibilidad)
    final lat = (placeDetails['lat'] ?? placeDetails['latitude'])?.toDouble();
    final lon = (placeDetails['lon'] ?? placeDetails['lng'] ?? placeDetails['longitude'])?.toDouble();

    // Fallback por compatibilidad si viene con geometry.location
    if (lat == null || lon == null) {
      final geometry = placeDetails['geometry'];
      final loc = geometry != null ? geometry['location'] : null;
      final gLat = (loc?['lat'])?.toDouble();
      final gLon = (loc?['lng'])?.toDouble();
      if (gLat != null && gLon != null) {
        _applySelectedLocation(gLat, gLon, placeDetails);
        return;
      }
    }

    if (lat != null && lon != null) {
      // Normalizar el texto mostrado con la dirección formateada de Google
      final formatted = (placeDetails['formatted_address'] ?? placeDetails['address'] ?? '').toString();
      if (formatted.isNotEmpty && _addressController.text.trim() != formatted.trim()) {
        _addressController.text = formatted;
      }
      _applySelectedLocation(lat, lon, placeDetails);
    }
  }

  void _applySelectedLocation(double lat, double lon, Map<String, dynamic> details) {
    setState(() {
      _selectedLat = lat;
      _selectedLon = lon;
      _selectedPlaceId = details['place_id'] ?? details['placeId'];
      _addressStructured = details;
    });
    // Revalidar formulario para limpiar mensajes de error de dirección
    _formKey.currentState?.validate();
  }

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
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _emailError = 'Error validando correo';
            _isValidatingEmail = false;
          });
        }
      }
    });
  }

  void _validatePhone(String full) {
    _phoneTimer?.cancel();
    
    if (full.trim().isEmpty) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }
    
    // Validate by digits length for UX
    final digits = full.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.trim().length < 8) {
      setState(() {
        _phoneError = 'Mínimo 8 dígitos';
        _isValidatingPhone = false;
      });
      return;
    }
    
    setState(() => _isValidatingPhone = true);
    
    _phoneTimer = Timer(const Duration(milliseconds: 800), () async {
      try {
        // IMPORTANT: pass full canonical phone (+lada+digits) to backend validator
        final error = await ValidationService.validatePhoneRealtime(full);
        if (mounted) {
          setState(() {
            _phoneError = error;
            _isValidatingPhone = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _phoneError = 'Error validando teléfono';
            _isValidatingPhone = false;
          });
        }
      }
    });
  }

  Future<void> _submitRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_validateCurrentStep()) {
      _showSnackBar('Por favor completa todos los campos obligatorios', Colors.orange);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      print('🚀 [DELIVERY_REG] Iniciando registro de repartidor...');
      
      // 1. Crear usuario en Supabase Auth con la contraseña elegida
      final authResponse = await SupabaseAuth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        userData: {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'role': 'repartidor',
          'lat': _selectedLat,
          'lon': _selectedLon,
          'address_structured': _addressStructured,
          'vehicle_type': _selectedVehicleType,
          'vehicle_plate': _vehiclePlateController.text.trim(),
          'vehicle_model': _vehicleModelController.text.trim().isEmpty ? null : _vehicleModelController.text.trim(),
          'vehicle_color': _vehicleColorController.text.trim().isEmpty ? null : _vehicleColorController.text.trim(),
          'emergency_contact_name': _emergencyContactNameController.text.trim().isEmpty ? null : _emergencyContactNameController.text.trim(),
          'emergency_contact_phone': _emergencyContactPhoneController.text.trim().isEmpty ? null : _emergencyContactPhoneController.text.trim(),
        },
      );

      if (authResponse.user == null) {
        throw Exception('No se pudo crear el usuario');
      }

      final userId = authResponse.user!.id;
      print('✅ [DELIVERY_REG] Usuario creado: $userId');

      // 3. Subir imágenes y documentos
      String? profileImageUrl;
      String? idFrontUrl;
      String? idBackUrl;
      String? vehiclePhotoUrl;
      String? vehicleRegistrationUrl;
      String? vehicleInsuranceUrl;

      if (_profileImage != null) {
        profileImageUrl = await StorageService.uploadProfileImage(userId, _profileImage!);
      }
      if (_idDocumentFront != null) {
        idFrontUrl = await StorageService.uploadIdDocumentFront(userId, _idDocumentFront!);
      }
      if (_idDocumentBack != null) {
        idBackUrl = await StorageService.uploadIdDocumentBack(userId, _idDocumentBack!);
      }
      if (_vehiclePhoto != null) {
        vehiclePhotoUrl = await StorageService.uploadVehiclePhoto(userId, _vehiclePhoto!);
      }
      if (_vehicleRegistration != null) {
        vehicleRegistrationUrl = await StorageService.uploadVehicleRegistration(userId, _vehicleRegistration!);
      }
      if (_vehicleInsurance != null) {
        vehicleInsuranceUrl = await StorageService.uploadVehicleInsurance(userId, _vehicleInsurance!);
      }

      // 4. Registro atómico con RPC (perfil + cuenta + user_prefs)
      print('📞 [DELIVERY_REG] Calling register_delivery_agent_atomic RPC...');
      final rpc = await SupabaseRpc.call(
        RpcNames.registerDeliveryAgentAtomic,
        params: {
          'p_user_id': userId,
          'p_email': _emailController.text.trim(),
          'p_name': _nameController.text.trim(),
          'p_phone': _phoneController.text.trim(),
          'p_address': _addressController.text.trim(),
          'p_lat': _selectedLat,
          'p_lon': _selectedLon,
          'p_address_structured': _addressStructured,
          'p_vehicle_type': _selectedVehicleType,
          'p_vehicle_plate': _vehiclePlateController.text.trim(),
          'p_vehicle_model': _vehicleModelController.text.trim().isEmpty ? null : _vehicleModelController.text.trim(),
          'p_vehicle_color': _vehicleColorController.text.trim().isEmpty ? null : _vehicleColorController.text.trim(),
          'p_emergency_contact_name': _emergencyContactNameController.text.trim().isEmpty ? null : _emergencyContactNameController.text.trim(),
          'p_emergency_contact_phone': _emergencyContactPhoneController.text.trim().isEmpty ? null : _emergencyContactPhoneController.text.trim(),
          'p_place_id': _selectedPlaceId,
          'p_profile_image_url': profileImageUrl,
          'p_id_document_front_url': idFrontUrl,
          'p_id_document_back_url': idBackUrl,
          'p_vehicle_photo_url': vehiclePhotoUrl,
          'p_vehicle_registration_url': vehicleRegistrationUrl,
          'p_vehicle_insurance_url': vehicleInsuranceUrl,
        },
      );

      if (!rpc.success) {
        print('❌ [DELIVERY_REG] RPC failed: ${rpc.error}');
        throw Exception('register_delivery_agent_atomic failed: ${rpc.error ?? 'Unknown error'}');
      }

      print('✅ [DELIVERY_REG] RPC completed successfully');

      print('✅ [DELIVERY_REG] Registro completado exitosamente');

      if (mounted) {
        _showSuccessDialog();
      }

    } catch (e) {
      print('❌ [DELIVERY_REG] Error: $e');
      if (mounted) {
        _showErrorDialog('Error al registrar repartidor: ${e.toString()}');
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
            Text('Tu solicitud ha sido enviada exitosamente.', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white),
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
        leading: _currentStep > 0 ? IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF666666)),
          onPressed: _previousStep,
        ) : null,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1PersonalInfo(isDesktop),
                  _buildStep2VehicleInfo(isDesktop),
                  _buildStep3Documents(isDesktop),
                ],
              ),
            ),
            _buildBottomNavigation(isDesktop),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          _buildStepIndicator(0, 'Personal'),
          _buildProgressLine(0),
          _buildStepIndicator(1, 'Vehículo'),
          _buildProgressLine(1),
          _buildStepIndicator(2, 'Documentos'),
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? const Color(0xFF4CAF50) : isActive ? const Color(0xFF4CAF50) : const Color(0xFFEEEEEE),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : Text('${step + 1}', style: TextStyle(color: isActive ? Colors.white : const Color(0xFF999999), fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.w600 : FontWeight.normal, color: isActive ? const Color(0xFF333333) : const Color(0xFF999999))),
        ],
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    final isCompleted = _currentStep > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 24),
        color: isCompleted ? const Color(0xFF4CAF50) : const Color(0xFFEEEEEE),
      ),
    );
  }

  Widget _buildStep1PersonalInfo(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Información Personal', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('Cuéntanos sobre ti', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF666666))),
              const SizedBox(height: 32),

              ImageUploadField(
                label: 'Foto de perfil (opcional)',
                hint: 'Tu foto de perfil',
                icon: Icons.person,
                imageUrl: null,
                helpText: 'Foto clara de tu rostro',
                onImageSelected: (file) => setState(() => _profileImage = file),
              ),
              const SizedBox(height: 24),

              _buildTextField(
                controller: _nameController,
                label: 'Nombre completo',
                hint: 'Juan Pérez',
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Ingresa tu nombre completo';
                  if (value.trim().length < 3) return 'Mínimo 3 caracteres';
                  return null;
                },
              ),
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

              PhoneDialInput(
                controller: _phoneController,
                label: 'Teléfono',
                hint: '656-123-4567',
                isValidating: _isValidatingPhone,
                errorText: _phoneError,
                // Pass FULL value to validation to include +lada
                onChangedFull: (full) => _validatePhone(full),
                validator: (digits) {
                  if (digits.trim().isEmpty) return 'Ingresa el teléfono';
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2)),
                    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1)),
                    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  ),
                ),
                child: AddressSearchField(
                  controller: _addressController,
                  labelText: 'Dirección',
                  hintText: 'Buscar dirección...',
                  onPlaceSelected: _onAddressSelected,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Busca y confirma tu dirección';
                    if (_selectedLat == null || _selectedLon == null) return 'Confirma la ubicación';
                    return null;
                  },
                ),
              ),
              // Acción secundaria para confirmar en mapa grande (flujo idéntico al de restaurantes)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    FocusScope.of(context).unfocus();
                    final result = await showModalBottomSheet<dynamic>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => AddressPickerModal(initialAddress: _addressController.text),
                    );
                    if (result is AddressPickResult) {
                      setState(() {
                        _addressController.text = result.formattedAddress;
                        _selectedLat = result.lat;
                        _selectedLon = result.lon;
                        _selectedPlaceId = result.placeId;
                        _addressStructured = result.addressStructured;
                      });
                      // Revalidar formulario
                      _formKey.currentState?.validate();
                    }
                  },
                  icon: const Icon(Icons.map_outlined, size: 18, color: Color(0xFF4CAF50)),
                  label: const Text('Confirmar en mapa', style: TextStyle(color: Color(0xFF4CAF50))),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                ),
              ),
              
              if (_selectedLat != null && _selectedLon != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF4CAF50))),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                      SizedBox(width: 12),
                      Expanded(child: Text('Ubicación confirmada', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.w500))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildMiniMap(_selectedLat!, _selectedLon!),
              ],
              const SizedBox(height: 24),

              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 24),

              Text('Contacto de emergencia (opcional)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _emergencyContactNameController,
                label: 'Nombre',
                hint: 'María Pérez',
                icon: Icons.contacts_outlined,
              ),
              const SizedBox(height: 20),

              PhoneDialInput(
                controller: _emergencyContactPhoneController,
                label: 'Teléfono',
                hint: '656-987-6543',
              ),
              const SizedBox(height: 24),

              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 24),

              Text('Contraseña', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
              const SizedBox(height: 16),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep2VehicleInfo(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Información del Vehículo', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('Cómo realizarás las entregas', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF666666))),
              const SizedBox(height: 32),

              Text('Tipo de vehículo', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF666666))),
              const SizedBox(height: 12),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _vehicleTypes.map((type) {
                  final isSelected = _selectedVehicleType == type['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedVehicleType = type['value'] as String),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF4CAF50).withValues(alpha: 0.1) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFFDDDDDD), width: isSelected ? 2 : 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(type['icon'] as IconData, color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFF666666), size: 20),
                          const SizedBox(width: 8),
                          Text(type['label'] as String, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal, color: isSelected ? const Color(0xFF4CAF50) : const Color(0xFF666666))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              _buildTextField(
                controller: _vehiclePlateController,
                label: 'Placa/Matrícula',
                hint: 'ABC-1234',
                icon: Icons.badge_outlined,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Ingresa la placa del vehículo';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _vehicleModelController,
                label: 'Modelo (opcional)',
                hint: 'Honda 2020',
                icon: Icons.info_outline,
              ),
              const SizedBox(height: 20),

              _buildTextField(
                controller: _vehicleColorController,
                label: 'Color (opcional)',
                hint: 'Rojo',
                icon: Icons.palette_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep3Documents(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 48 : 24),
      child: Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Documentos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
              const SizedBox(height: 8),
              Text('Sube los documentos necesarios', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: const Color(0xFF666666))),
              const SizedBox(height: 32),

              ImageUploadField(
                label: 'Identificación oficial (frente)',
                hint: 'Frente de tu INE/IFE',
                icon: Icons.badge,
                isRequired: true,
                imageUrl: null,
                helpText: 'Foto clara del frente de tu identificación',
                onImageSelected: (file) => setState(() => _idDocumentFront = file),
              ),
              const SizedBox(height: 24),

              ImageUploadField(
                label: 'Identificación oficial (reverso)',
                hint: 'Reverso de tu INE/IFE',
                icon: Icons.badge,
                isRequired: true,
                imageUrl: null,
                helpText: 'Foto clara del reverso de tu identificación',
                onImageSelected: (file) => setState(() => _idDocumentBack = file),
              ),
              const SizedBox(height: 24),

              const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
              const SizedBox(height: 24),

              Text('Documentos del vehículo (opcional)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
              const SizedBox(height: 16),

              ImageUploadField(
                label: 'Foto del vehículo',
                hint: 'Foto de tu vehículo',
                icon: Icons.directions_bike,
                imageUrl: null,
                helpText: 'Foto clara de tu vehículo',
                onImageSelected: (file) => setState(() => _vehiclePhoto = file),
              ),
              const SizedBox(height: 24),

              ImageUploadField(
                label: 'Tarjeta de circulación',
                hint: 'Registro del vehículo',
                icon: Icons.description,
                imageUrl: null,
                helpText: 'Si aplica para tu tipo de vehículo',
                onImageSelected: (file) => setState(() => _vehicleRegistration = file),
              ),
              const SizedBox(height: 24),

              ImageUploadField(
                label: 'Seguro del vehículo',
                hint: 'Póliza de seguro',
                icon: Icons.shield,
                imageUrl: null,
                helpText: 'Si aplica para tu tipo de vehículo',
                onImageSelected: (file) => setState(() => _vehicleInsurance = file),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Recibirás un email de verificación. Nuestro equipo revisará tu solicitud en 24-48 horas.', style: TextStyle(fontSize: 13, color: Color(0xFF1A1A1A))),
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
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          if (_currentStep > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _previousStep,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), side: const BorderSide(color: Color(0xFFDDDDDD)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Atrás', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : (_currentStep < 2 ? _nextStep : _submitRegistration),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              child: _isSubmitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(_currentStep < 2 ? 'Siguiente' : 'Enviar solicitud', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF666666), size: 22),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
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
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4CAF50))),
      );
    } else if (controller.text.isNotEmpty && error == null && !isValidating) {
      suffixIcon = const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xFF666666), size: 22),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFFAFAFA),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: error != null ? const Color(0xFFEF5350) : const Color(0xFFDDDDDD))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: error != null ? const Color(0xFFEF5350) : const Color(0xFF4CAF50), width: 2)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350))),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
          ),
          validator: validator,
        ),
        if (error != null && !isValidating) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(error, style: const TextStyle(color: Color(0xFFEF5350), fontSize: 12)),
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
    return TextFormField(
      controller: controller,
      obscureText: !isVisible,
      style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF666666), size: 22),
        suffixIcon: IconButton(
          icon: Icon(
            isVisible ? Icons.visibility : Icons.visibility_off,
            color: const Color(0xFF999999),
          ),
          onPressed: onToggleVisibility,
        ),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFDDDDDD))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF4CAF50), width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFEF5350), width: 2)),
      ),
      validator: validator,
    );
  }

  Widget _buildMiniMap(double lat, double lon) {
    final point = ll.LatLng(lat, lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 160,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.doa.repartos',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 36,
                  height: 36,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.location_on, color: Color(0xFF4CAF50), size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
