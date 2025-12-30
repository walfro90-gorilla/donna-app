import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/theme.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/services/network_service.dart';
import 'package:doa_repartos/screens/auth/login_screen.dart';
import 'package:doa_repartos/screens/auth/register_screen.dart';
import 'package:doa_repartos/screens/auth/email_verification_screen.dart';
import 'package:doa_repartos/screens/home/home_screen.dart';
import 'package:doa_repartos/screens/splash/splash_screen.dart';
import 'package:doa_repartos/screens/checkout/checkout_screen.dart';
import 'package:doa_repartos/screens/checkout/order_confirmation_screen.dart';
import 'package:doa_repartos/screens/public/restaurant_registration_screen.dart';
import 'package:doa_repartos/screens/public/delivery_agent_registration_screen.dart';
import 'package:doa_repartos/screens/public/delivery_signup_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_onboarding_dashboard.dart';
import 'package:doa_repartos/screens/public/privacy_policy_screen.dart';
import 'dart:async';
import 'package:doa_repartos/core/theme/app_theme_controller.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Google Maps Renderer (Fix for ImageReader_JNI errors)
  final GoogleMapsFlutterPlatform mapsImplementation = GoogleMapsFlutterPlatform.instance;
  if (mapsImplementation is GoogleMapsFlutterAndroid) {
    debugPrint('🗺️ [MAIN] Initializing Google Maps Android Renderer to LEGACY (Compatibility Mode)');
    mapsImplementation.useAndroidViewSurface = false; // Try false for better performance on some devices, or true if needed.
    // LATEST renderer can cause issues on some devices/emulators. Using platformDefault or legacy is safer.
    try {
      mapsImplementation.initializeWithRenderer(AndroidMapRenderer.legacy);
    } catch (e) {
      debugPrint('⚠️ [MAIN] Failed to initialize map renderer: $e');
    }
  }

  // Initialize theme preference first
  await AppThemeController.initialize();
  // Initialize services
  await _initializeServices();
  runApp(const MyApp());
}

/// Inicializar todos los servicios de la aplicación
Future<void> _initializeServices() async {
  debugPrint('🚀 [MAIN] ===== INICIALIZANDO SERVICIOS DOA REPARTOS =====');

  try {
    // 1. Inicializar Supabase
    debugPrint('📡 [MAIN] Inicializando Supabase...');
    await SupabaseConfig.initialize();
    debugPrint('✅ [MAIN] Supabase inicializado');

    // 1.1. Log de parámetros de redirección (web) para diagnosticar confirmación de email
    SupabaseConfig.debugLogAuthRedirect();

    // 2. Inicializar NetworkService
    debugPrint('🌐 [MAIN] Inicializando NetworkService...');
    await NetworkService().initialize();
    debugPrint('✅ [MAIN] NetworkService inicializado');

    // 3. Inicializar Session Manager (reemplaza auth listener manual)
    debugPrint('🎯 [MAIN] Inicializando Session Manager...');
    await SessionManager.instance.initialize();
    debugPrint('✅ [MAIN] Session Manager inicializado');

    // 3.5. Test database connection SOLO si hay sesión (evita errores RLS en confirmación de email)
    if (SupabaseConfig.auth.currentUser != null) {
      debugPrint('🔍 [MAIN] Probando conexión a base de datos (usuario autenticado)...');
      await SupabaseConfig.testDatabaseConnection();
    } else {
      debugPrint('⏭️ [MAIN] Omitiendo prueba de BD: no hay usuario autenticado aún');
    }

    debugPrint('🎉 [MAIN] ===== TODOS LOS SERVICIOS INICIALIZADOS =====');
  } catch (e) {
    debugPrint('❌ [MAIN] Error crítico inicializando servicios: $e');
    // Continuar con la app aunque haya errores
  }
}

// ===== CÓDIGO LEGACY DE AUTH REMOVIDO =====
// Todo el manejo de autenticación ahora se hace en SessionManager

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // Limpiar servicios al cerrar la app
    SessionManager.instance.dispose();
    NetworkService().dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    debugPrint('📱 [LIFECYCLE] App state changed: $state');

    switch (state) {
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.paused:
        _handleAppPaused();
        break;
      case AppLifecycleState.detached:
        _handleAppDetached();
        break;
      default:
        break;
    }
  }

  /// Manejar cuando la app vuelve al foreground
  void _handleAppResumed() {
    debugPrint('🔄 [LIFECYCLE] App resumed');

    // Verificar conectividad
    debugPrint('🔍 [NETWORK] Verificando conexión...');
    NetworkService().checkConnection();

    // El SessionManager se encarga de reinicializar servicios automáticamente
    debugPrint('✅ [LIFECYCLE] SessionManager maneja servicios automáticamente');
  }

  /// Manejar cuando la app va al background
  void _handleAppPaused() {
    debugPrint('⏸️ [LIFECYCLE] App paused - optimizando recursos');
    // Los servicios continuarán funcionando pero con menor frecuencia
  }

  /// Manejar cuando la app se cierra
  void _handleAppDetached() {
    debugPrint('🔚 [LIFECYCLE] App detached - limpiando recursos');
    SessionManager.instance.dispose();
    NetworkService().dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'Doa Repartos',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: mode,
        initialRoute: '/',
        onGenerateRoute: (settings) {
          // Rutas públicas que no requieren autenticación
          const publicRoutes = [
            '/nueva-donna',
            '/nuevo-repartidor',
            '/login',
            '/register',
            '/email-verification',
            '/delivery/onboarding',
            '/politica-de-privacidad',
          ];

          final routeName = settings.name ?? '/';

          // Si es una ruta pública, navegar directamente
          if (publicRoutes.contains(routeName)) {
            switch (routeName) {
              case '/nueva-donna':
                return MaterialPageRoute(
                  builder: (_) => const RestaurantRegistrationScreen(),
                  settings: settings,
                );
              case '/nuevo-repartidor':
                return MaterialPageRoute(
                  builder: (_) => const DeliverySignupScreen(),
                  settings: settings,
                );
              case '/login':
                return MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                  settings: settings,
                );
              case '/register':
                return MaterialPageRoute(
                  builder: (_) => const RegisterScreen(),
                  settings: settings,
                );
              case '/email-verification':
                final email = settings.arguments as String?;
                if (email == null) {
                  return MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                    settings: settings,
                  );
                }
                return MaterialPageRoute(
                  builder: (_) => EmailVerificationScreen(email: email),
                  settings: settings,
                );
              case '/delivery/onboarding':
                return MaterialPageRoute(
                  builder: (_) => const DeliveryOnboardingDashboard(),
                  settings: settings,
                );
              case '/politica-de-privacidad':
                return MaterialPageRoute(
                  builder: (_) => const PrivacyPolicyScreen(),
                  settings: settings,
                );
            }
          }

          // Rutas que requieren autenticación pasan por SplashScreen
          switch (routeName) {
            case '/':
              return MaterialPageRoute(
                builder: (_) => const SplashScreen(),
                settings: settings,
              );
            case '/home':
              return MaterialPageRoute(
                builder: (_) => const HomeScreen(),
                settings: settings,
              );
            default:
              // Ruta desconocida: redirigir a splash
              return MaterialPageRoute(
                builder: (_) => const SplashScreen(),
                settings: settings,
              );
          }
        },
      ),
    );
  }
}
