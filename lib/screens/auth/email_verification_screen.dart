import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EmailVerificationScreen extends StatefulWidget {
  final String email;

  const EmailVerificationScreen({
    super.key,
    required this.email,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isLoading = false;
  bool _canResend = true;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _startListeningToAuthChanges();
  }

  void _startListeningToAuthChanges() {
    SupabaseAuth.authStateChanges.listen((authState) {
      print('🔄 EmailVerificationScreen - Auth state change: ${authState.event}');
      print('📧 User email confirmed: ${authState.session?.user?.emailConfirmedAt != null}');
      
      if (mounted && authState.event == AuthChangeEvent.signedIn) {
        final user = authState.session?.user;
        if (user != null && user.emailConfirmedAt != null) {
          print('✅ Email verified! Navigating to home...');
          
          // Update email_confirm status in database
          _updateEmailConfirmStatus(user.id);
          
          // Navigate to home
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    });
  }

  Future<void> _updateEmailConfirmStatus(String userId) async {
    try {
      await DoaRepartosService.updateEmailConfirmStatus(userId, true);
      print('✅ Updated email_confirm to true in database');
    } catch (e) {
      print('❌ Error updating email_confirm status: $e');
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend) return;

    setState(() {
      _isLoading = true;
      _canResend = false;
      _countdown = 60;
    });

    try {
      await SupabaseConfig.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email de verificación enviado nuevamente'),
            backgroundColor: Colors.green,
          ),
        );
      }

      _startCountdown();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reenviar email: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _canResend = true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _countdown > 0) {
        setState(() => _countdown--);
        _startCountdown();
      } else if (mounted) {
        setState(() => _canResend = true);
      }
    });
  }

  Future<void> _checkVerificationStatus() async {
    setState(() => _isLoading = true);
    
    try {
      final user = SupabaseAuth.currentUser;
      if (user != null) {
        // Refresh user data from server
        await SupabaseConfig.auth.refreshSession();
        final updatedUser = SupabaseAuth.currentUser;
        
        print('🔄 Checking verification status...');
        print('📧 Email confirmed at: ${updatedUser?.emailConfirmedAt}');
        
        if (updatedUser?.emailConfirmedAt != null) {
          print('✅ Email is verified!');
          
          // Update email_confirm status in database
          await _updateEmailConfirmStatus(updatedUser!.id);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ ¡Email verificado correctamente!'),
                backgroundColor: Colors.green,
              ),
            );
            
            // Small delay to show the success message
            await Future.delayed(const Duration(milliseconds: 1000));
            
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('📧 La cuenta aún no ha sido verificada. Por favor, revisa tu email.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error checking verification status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al verificar estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icono de email
              const Icon(
                Icons.mark_email_read,
                size: 120,
                color: Colors.pink,
              ),
              const SizedBox(height: 32),

              // Título
              const Text(
                'Verifica tu email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Mensaje principal
              Text(
                'Te hemos enviado un correo de verificación a:',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Text(
                widget.email,
                style: const TextStyle(
                  color: Colors.pink,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Instrucciones
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[800]!),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 24,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Para activar tu cuenta:\n\n1. Revisa tu bandeja de entrada\n2. Busca el email de DOA Repartos\n3. Haz clic en el enlace de verificación\n4. Regresa a la app para continuar',
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 14,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Botón verificar ahora
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _checkVerificationStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Ya verifiqué mi email',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                ),
              ),
              const SizedBox(height: 16),

              // Botón reenviar email
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _canResend && !_isLoading ? _resendVerificationEmail : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.pink),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Text(
                    _canResend
                      ? 'Reenviar email'
                      : 'Reenviar en ${_countdown}s',
                    style: TextStyle(
                      color: _canResend ? Colors.pink : Colors.grey,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

                      // Link para volver
              TextButton(
                onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                child: const Text(
                  'Volver al inicio de sesión',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 16,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Ayuda
              Text(
                '¿No recibiste el email? Revisa tu carpeta de spam o correo no deseado.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}