import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/home/home_screen.dart';
import 'package:doa_repartos/screens/auth/register_screen.dart';
import 'package:doa_repartos/screens/auth/email_verification_screen.dart';
import 'package:doa_repartos/screens/auth/change_password_screen.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/widgets/app_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recuperar Contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Ingresa tu correo para recibir un enlace de recuperación:'),
            const SizedBox(height: 16),
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isNotEmpty && email.contains('@')) {
                try {
                  await SupabaseAuth.resetPassword(email);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Enlace de recuperación enviado a tu correo'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      print('🚀 Starting login process...');

      final response = await SupabaseAuth.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (response.user != null && mounted) {
        print('✅ Login successful for: ${response.user!.email}');
        print('📧 Email confirmed at: ${response.user!.emailConfirmedAt}');

        // Check if email is verified in Auth
        if (response.user!.emailConfirmedAt == null) {
          print(
              '⚠️ Email not confirmed in Auth, redirecting to verification...');
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                email: _emailController.text.trim(),
              ),
            ),
          );
        } else {
          // Double check email confirmation status in database
          try {
            final isEmailConfirmed =
                await DoaRepartosService.isEmailConfirmed(response.user!.id);
            print('📊 Email confirmed in database: $isEmailConfirmed');

            if (!isEmailConfirmed) {
              // Update database to match Auth status
              await DoaRepartosService.updateEmailConfirmStatus(
                  response.user!.id, true);
              print('✅ Updated database email_confirm status to true');
            }

            // Navigate based on user role
            await _navigateByUserRole();
          } catch (dbError) {
            print('⚠️ Error checking database email status: $dbError');
            // Still navigate based on role if Auth says verified
            await _navigateByUserRole();
          }
        }
      }
    } catch (e) {
      print('❌ Login error: $e');
      if (mounted) {
        String errorMessage = e.toString();

        // Handle specific authentication errors
        if (errorMessage.contains('Email not confirmed')) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EmailVerificationScreen(
                email: _emailController.text.trim(),
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error de autenticación: $errorMessage'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Starting Google Sign-In...');

      final response = await SupabaseAuth.signInWithGoogle();

      if (response.user != null && mounted) {
        print('✅ Google login successful for: ${response.user!.email}');

        // Navigate based on user role (Google users are auto-verified)
        await _navigateByUserRole();
      }
    } catch (e) {
      print('❌ Google login error: $e');
      if (mounted) {
        // Check if error is due to user not found in database
        if (e.toString().contains('USER_NOT_FOUND_IN_DB')) {
          print('⚠️ User authenticated with Google but profile not found in DB');
          _showUserNotFoundDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al iniciar sesión con Google: $e'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() => _isLoading = true);

    try {
      print('🚀 Starting Facebook Sign-In...');

      final response = await SupabaseAuth.signInWithFacebook();

      if (response.user != null && mounted) {
        print('✅ Facebook login successful for: ${response.user!.email}');
        await _navigateByUserRole();
      }
    } catch (e) {
      print('❌ Facebook login error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar sesión con Facebook: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Show dialog when Google user is not found in database
  void _showUserNotFoundDialog() {
    final currentUser = SupabaseAuth.currentUser;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('Cuenta no registrada')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bienvenido, ${currentUser?.email ?? "usuario"}!',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            const Text(
              'Hemos detectado que esta es tu primera vez en nuestra plataforma.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              '¿Deseas crear tu cuenta ahora?',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Solo necesitamos algunos datos adicionales para completar tu perfil.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              // Sign out and go back
              await SupabaseAuth.signOut();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToRegisterWithGoogleData();
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Crear Cuenta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Navigate to RegisterScreen with pre-filled Google data
  void _navigateToRegisterWithGoogleData() {
    final currentUser = SupabaseAuth.currentUser;
    
    if (currentUser != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegisterScreen(
            prefillEmail: currentUser.email ?? '',
            prefillName: currentUser.userMetadata?['full_name']?.toString() ?? 
                        currentUser.userMetadata?['name']?.toString() ?? '',
            isGoogleSignup: true,
          ),
        ),
      );
    }
  }

  /// Navigate to appropriate dashboard based on user role
  Future<void> _navigateByUserRole() async {
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        print('❌ No current user found during navigation');
        return;
      }

      print('🔍 Fetching user profile for role-based navigation...');
      print('👤 Current user ID: ${currentUser.id}');
      print('📧 Current user email: ${currentUser.email}');

      // Get user profile from database to determine role
      final userProfile = await DoaRepartosService.getUserById(currentUser.id);

      print('📄 User profile from database: $userProfile');

      if (userProfile != null) {
        // Los usuarios ahora establecen su propia contraseña durante el registro
        // Ya no hay contraseñas temporales que requieran cambio
        final userProvider = currentUser.appMetadata['provider']?.toString() ?? 'email';
        print('✅ [LOGIN] Usuario autenticado correctamente');
        print('🔐 [LOGIN] Provider: $userProvider');

        final roleString = userProfile['role'] ?? 'cliente';
        print('📝 Role string from database: "$roleString"');

        final userRole = UserRole.fromString(roleString);
        print('✅ User role determined: $userRole (enum value)');

        // Log navigation action
        print('🎯 About to navigate to dashboard for role: $userRole');

        // Navigate based on role
        if (mounted) {
          NavigationService.navigateByRole(context, userRole,
              userData: userProfile);
        } else {
          print('⚠️ Widget not mounted, skipping navigation');
        }
      } else {
        print('⚠️ User profile not found, defaulting to client role');
        // Default to client if no profile found
        if (mounted) {
          NavigationService.navigateByRole(context, UserRole.client);
        }
      }
    } catch (e) {
      print('❌ Error determining user role: $e');
      print('❌ Error type: ${e.runtimeType}');
      // Default to home screen on error
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),

              // Logo y titulo
              Column(
                children: [
                  const AppLogo(size: 120, showTitle: false),
                  const SizedBox(height: 24),
                  Text(
                    "Doña Repartos",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tu comida favorita a domicilio 🍕',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // Botón de Google Sign-In (PRIMERO Y PROMINENTE)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    side: BorderSide(color: Colors.grey.shade300, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: SvgPicture.network(
                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                    height: 24,
                    width: 24,
                  ),
                  label: const Text(
                    'Continuar con Google',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Botón de Facebook Sign-In (debajo de Google)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _signInWithFacebook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1877F2), // Facebook blue
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.facebook, color: Colors.white, size: 24),
                  label: const Text(
                    'Continuar con Facebook',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Divider con texto
              Row(
                children: [
                  Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'O usa tu email',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Theme.of(context).colorScheme.outline)),
                ],
              ),

              const SizedBox(height: 24),

              // Form de email/password
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu correo electrónico';
                        }
                        if (!value.contains('@')) {
                          return 'Ingresa un correo válido';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(
                                () => _obscurePassword = !_obscurePassword);
                          },
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surface,
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Ingresa tu contraseña';
                        }
                        if (value.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 8),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _resetPassword(),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _login,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text(
                                'Iniciar Sesión',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                      child: const Text(
                        'Crear Cuenta Nueva',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Demo login buttons
                    // Wrap(
                    //   alignment: WrapAlignment.center,
                    //   children: [
                    //     TextButton.icon(
                    //       onPressed: _isLoading
                    //           ? null
                    //           : () {
                    //               _emailController.text = 'client@donna.app';
                    //               _passwordController.text = '123123123';
                    //               _login();
                    //             },
                    //       icon: const Icon(Icons.person, color: Colors.blue),
                    //       label: const Text('Demo Cliente',
                    //           style: TextStyle(color: Colors.blue)),
                    //     ),
                    //     TextButton.icon(
                    //       onPressed: _isLoading
                    //           ? null
                    //           : () {
                    //               _emailController.text =
                    //                   'restaurant@donna.app';
                    //               _passwordController.text = '123123123';
                    //               _login();
                    //             },
                    //       icon: const Icon(Icons.store, color: Colors.orange),
                    //       label: const Text('Demo Restaurante',
                    //           style: TextStyle(color: Colors.orange)),
                    //     ),
                    //     TextButton.icon(
                    //       onPressed: _isLoading
                    //           ? null
                    //           : () {
                    //               _emailController.text =
                    //                   'repartidor@donna.app';
                    //               _passwordController.text = '123123123';
                    //               _login();
                    //             },
                    //       icon: const Icon(Icons.delivery_dining,
                    //           color: Colors.green),
                    //       label: const Text('Demo Repartidor',
                    //           style: TextStyle(color: Colors.green)),
                    //     ),
                    //     TextButton.icon(
                    //       onPressed: _isLoading
                    //           ? null
                    //           : () {
                    //               _emailController.text = 'walfre.am@gmail.com';
                    //               _passwordController.text = 'Gorillabs2026!';
                    //               _login();
                    //             },
                    //       icon: const Icon(Icons.admin_panel_settings,
                    //           color: Colors.purple),
                    //       label: const Text('Demo Admin',
                    //           style: TextStyle(color: Colors.purple)),
                    //     ),
                    //   ],
                    // ),

                    // const SizedBox(height: 32),

                    // Divider
                    Divider(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                    
                    const SizedBox(height: 16),

                    // Registro de Restaurante y Repartidor buttons
                    Column(
                      children: [
                        Text(
                          '¿Quieres unirte como socio?',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.of(context).pushNamed('/nueva-donna');
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.store, size: 22),
                            label: const Text(
                              'Registrar mi Restaurante',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    Navigator.of(context).pushNamed('/nuevo-repartidor');
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.delivery_dining, size: 22),
                            label: const Text(
                              'Registrarme como Repartidor',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
