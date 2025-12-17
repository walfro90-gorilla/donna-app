import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/widgets/app_logo.dart';
import 'package:doa_repartos/widgets/address_search_field.dart';
import 'package:doa_repartos/services/validation_service.dart';
import 'package:doa_repartos/widgets/phone_dial_input.dart';

class RegisterScreen extends StatefulWidget {
  final String? prefillEmail;
  final String? prefillName;
  final bool isGoogleSignup;
  
  const RegisterScreen({
    super.key,
    this.prefillEmail,
    this.prefillName,
    this.isGoogleSignup = false,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  // Rol fijo para clientes (comensales)
  final String _selectedRole = 'cliente';
  bool _hasShownEmailVerificationDialog = false;
  double? _selectedLat;
  double? _selectedLon;
  String? _selectedPlaceId;
  Map<String, dynamic>? _addressStructured;
  
  // Validación estados
  String? _emailError;
  String? _phoneError;
  bool _isValidatingEmail = false;
  bool _isValidatingPhone = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill data from Google if provided
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
    }
    if (widget.prefillName != null) {
      _nameController.text = widget.prefillName!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  /// Callback cuando se selecciona una dirección
  void _onPlaceSelected(Map<String, dynamic> placeDetails) {
    setState(() {
      _selectedLat = placeDetails['lat']?.toDouble();
      _selectedLon = placeDetails['lon']?.toDouble();
      _selectedPlaceId = placeDetails['place_id'];
      _addressStructured = placeDetails['address_structured'];
    });
    print('📍 [REGISTER] Place selected: lat=$_selectedLat, lon=$_selectedLon');
    print('📍 [REGISTER] Address structured: $_addressStructured');
  }

  /// Validación de email con debounce
  Future<void> _validateEmail(String? value) async {
    if (value == null || value.trim().isEmpty) {
      setState(() {
        _emailError = null;
        _isValidatingEmail = false;
      });
      return;
    }

    setState(() => _isValidatingEmail = true);

    // Debounce
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (!mounted || _emailController.text != value) {
      return; // User continued typing
    }

    final error = await ValidationService.validateEmailRealtime(value);
    if (mounted && _emailController.text == value) {
      setState(() {
        _emailError = error;
        _isValidatingEmail = false;
      });
    }
  }

  /// Validación de teléfono con debounce
  Future<void> _validatePhone(String? value) async {
    if (value == null || value.trim().isEmpty) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }

    setState(() => _isValidatingPhone = true);

    // Debounce
    await Future.delayed(const Duration(milliseconds: 800));
    
    if (!mounted || _phoneController.text != value) {
      return; // User continued typing
    }

    final error = await ValidationService.validatePhoneRealtime(value);
    if (mounted && _phoneController.text == value) {
      setState(() {
        _phoneError = error;
        _isValidatingPhone = false;
      });
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Check if this is a Google signup (user already authenticated)
      if (widget.isGoogleSignup) {
        print('🚀 Completing Google signup profile for: ${_emailController.text.trim()}');
        
        final currentUser = SupabaseAuth.currentUser;
        if (currentUser == null) {
          throw 'Sesión de Google expirada. Por favor, inténtalo de nuevo.';
        }
        
        // Get avatar_url from Google metadata
        final avatarUrl = currentUser.userMetadata?['avatar_url']?.toString();
        
        // Create/update profile in database (user already authenticated via Google)
        await DoaRepartosService.upsertUserProfile(
          currentUser.id, 
          currentUser.email ?? _emailController.text.trim(),
          {
            'name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'address': _addressController.text.trim(),
            'role': _selectedRole,
            'lat': _selectedLat,
            'lon': _selectedLon,
            'address_structured': _addressStructured,
            'email_confirm': true, // Google users are auto-verified
          },
        );
        
        print('✅ Google user profile created successfully');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Cuenta creada exitosamente!'),
              backgroundColor: Colors.green,
            ),
          );
          // Navigate to home
          Navigator.of(context).pushReplacementNamed('/home');
        }
      } else {
        print('🚀 Starting email/password registration for: ${_emailController.text.trim()}');
        
        // Log location data BEFORE sending to signUp
        print('📍 [REGISTER] Pre-signup location data:');
        print('   - lat: $_selectedLat');
        print('   - lon: $_selectedLon');
        print('   - address: ${_addressController.text.trim()}');
        print('   - address_structured: $_addressStructured');
        
        final userData = {
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'address': _addressController.text.trim(),
          'role': _selectedRole,
          'lat': _selectedLat,
          'lon': _selectedLon,
          'address_structured': _addressStructured,
        };
        
        print('📦 [REGISTER] Complete userData being sent to signUp: $userData');
        
        // Create user in Supabase Auth with email confirmation required
        final response = await SupabaseAuth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          userData: userData,
        );

        print('✅ Registration response: User ID: ${response.user?.id}, Session: ${response.session != null}');

        if (mounted) {
          // If signup was successful (either user returned or session created), show verification dialog
          if ((response.user != null || response.session != null) && !_hasShownEmailVerificationDialog) {
            _hasShownEmailVerificationDialog = true;
            print('📧 Showing email verification dialog');
            _showEmailVerificationDialog();
          } else {
            _showErrorDialog('No se pudo crear el usuario. Por favor, inténtalo de nuevo.');
          }
        }
      }
    } catch (e) {
      print('❌ DETAILED Registration error: $e');
      if (mounted) {
        // Show more specific error messages
        String errorMessage = 'Error al crear cuenta';
        if (e.toString().contains('profile creation failed')) {
          errorMessage = 'Usuario creado en Auth, pero falló la creación del perfil: ${e.toString()}';
        } else {
          errorMessage = 'Error al crear cuenta: ${e.toString()}';
        }
        _showErrorDialog(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Starting Google Sign-In from Register...');

      final response = await SupabaseAuth.signInWithGoogle();

      if (response.user != null && mounted) {
        print('✅ Google login successful for: ${response.user!.email}');

        // Navigate to home or role selection
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      print('❌ Google login error: $e');
      if (mounted) {
        _showErrorDialog('Error al iniciar sesión con Google: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEmailVerificationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.email, color: Colors.pink),
            SizedBox(width: 8),
            Text('Verifica tu email'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mark_email_read,
              size: 64,
              color: Colors.pink,
            ),
            const SizedBox(height: 16),
            Text(
              'Te hemos enviado un correo de verificación a:\n${_emailController.text}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'Por favor, revisa tu bandeja de entrada y haz clic en el enlace de verificación para activar tu cuenta.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushReplacementNamed(
                '/email-verification',
                arguments: _emailController.text.trim(),
              );
            },
            child: const Text('Entendido'),
          ),
          ElevatedButton(
            onPressed: () => _resendVerificationEmail(),
            child: const Text('Reenviar email'),
          ),
        ],
      ),
    );
  }

  Future<void> _resendVerificationEmail() async {
    try {
      await SupabaseConfig.auth.resend(
        type: OtpType.signup,
        email: _emailController.text.trim(),
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email de verificación enviado nuevamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reenviar email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Logo y título
              const AppLogo(size: 100, showTitle: false),
              const SizedBox(height: 16),
              const Text(
                'DOÑA Repartos',
                style: TextStyle(
                  color: Colors.pink,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                widget.isGoogleSignup 
                    ? 'Completa tu perfil' 
                    : 'Crea tu cuenta',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
              if (widget.isGoogleSignup) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Autenticado con Google ✓',
                          style: TextStyle(color: Colors.blue, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),

              // Información de tipo de cuenta (solo clientes)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.pink),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.restaurant_menu, color: Colors.pink, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cuenta de Cliente',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ordena comida de tus restaurantes favoritos',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nombre completo
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  labelStyle: TextStyle(color: Colors.grey),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.pink),
                  ),
                  prefixIcon: Icon(Icons.person, color: Colors.pink),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es requerido';
                  }
                  if (value.trim().length < 2) {
                    return 'El nombre debe tener al menos 2 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Email con validación en tiempo real
              TextFormField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                enabled: !widget.isGoogleSignup, // Disable if Google signup
                onChanged: _validateEmail,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _emailError != null ? Colors.red : Colors.grey,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: _emailError != null ? Colors.red : Colors.pink,
                    ),
                  ),
                  errorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.red, width: 2),
                  ),
                  prefixIcon: const Icon(Icons.email, color: Colors.pink),
                  suffixIcon: _isValidatingEmail
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.pink,
                            ),
                          ),
                        )
                      : null,
                  errorText: _emailError,
                  errorStyle: const TextStyle(color: Colors.red),
                ),
                validator: (value) {
                  if (_emailError != null) {
                    return _emailError;
                  }
                  if (value == null || value.trim().isEmpty) {
                    return 'El correo es requerido';
                  }
                  final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                  if (!emailRegex.hasMatch(value.trim())) {
                    return 'Ingresa un correo válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Teléfono con selector de lada (MX/US) y validación en tiempo real
              PhoneDialInput(
                controller: _phoneController,
                label: 'Teléfono',
                hint: '656-123-4567',
                isValidating: _isValidatingPhone,
                errorText: _phoneError,
                // Pass FULL canonical phone (+lada+digits) to validator
                onChangedFull: (full) => _validatePhone(full),
              ),
              const SizedBox(height: 16),

              // Dirección (con buscador inteligente OBLIGATORIO para TODOS los roles)
              AddressSearchField(
                controller: _addressController,
                labelText: 'Dirección *',
                hintText: 'Buscar dirección...',
                onPlaceSelected: _onPlaceSelected,
                required: true,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La dirección es obligatoria';
                  }
                  if (_selectedLat == null || _selectedLon == null) {
                    return 'Debes seleccionar una ubicación del buscador';
                  }
                  return null;
                },
              ),
              if (_selectedLat != null && _selectedLon != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ubicación confirmada (${_selectedLat!.toStringAsFixed(6)}, ${_selectedLon!.toStringAsFixed(6)})',
                          style: const TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Contraseña (solo para email/password signup)
              if (!widget.isGoogleSignup) TextFormField(
                controller: _passwordController,
                style: const TextStyle(color: Colors.white),
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.pink),
                  ),
                  prefixIcon: const Icon(Icons.lock, color: Colors.pink),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'La contraseña es requerida';
                  }
                  if (value.length < 6) {
                    return 'La contraseña debe tener al menos 6 caracteres';
                  }
                  return null;
                },
              ),
              if (!widget.isGoogleSignup) const SizedBox(height: 16),

              // Confirmar contraseña (solo para email/password signup)
              if (!widget.isGoogleSignup) TextFormField(
                controller: _confirmPasswordController,
                style: const TextStyle(color: Colors.white),
                obscureText: _obscureConfirmPassword,
                decoration: InputDecoration(
                  labelText: 'Confirmar contraseña',
                  labelStyle: const TextStyle(color: Colors.grey),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.pink),
                  ),
                  prefixIcon: const Icon(Icons.lock_outline, color: Colors.pink),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirma tu contraseña';
                  }
                  if (value != _passwordController.text) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // Botón registrarse
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.isGoogleSignup ? 'Completar Registro' : 'Crear Cuenta',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                ),
              ),
              
              // Solo mostrar opciones de Google si NO es signup de Google
              if (!widget.isGoogleSignup) ...[
                const SizedBox(height: 24),

                // Divider con texto
                Row(
                  children: [
                    Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'O regístrate con',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                  ],
                ),

                const SizedBox(height: 24),

                // Botón de Google Sign-In
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: SvgPicture.network(
                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                    height: 24,
                    width: 24,
                  ),
                  label: const Text(
                    'Continuar con Google',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
              ],

              if (!widget.isGoogleSignup) ...[
                const SizedBox(height: 24),

                // Link para volver al login
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                  child: RichText(
                    text: const TextSpan(
                      text: '¿Ya tienes una cuenta? ',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                      children: [
                        TextSpan(
                          text: 'Inicia Sesión',
                          style: TextStyle(
                            color: Colors.pink,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () async {
                    await SupabaseAuth.signOut();
                    if (mounted) {
                      Navigator.of(context).pushReplacementNamed('/login');
                    }
                  },
                  icon: const Icon(Icons.arrow_back, color: Colors.grey),
                  label: const Text(
                    'Cancelar y volver',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}