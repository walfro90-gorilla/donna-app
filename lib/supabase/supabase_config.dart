import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:doa_repartos/core/supabase/supabase_rpc.dart';

/// Supabase configuration for Doa Repartos app
/// Keys are automatically replaced by DreamFlow
class SupabaseConfig {
  static const String supabaseUrl = 'https://cncvxfjsyrntilcbbcfi.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNuY3Z4ZmpzeXJudGlsY2JiY2ZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ4ODIwNTEsImV4cCI6MjA3MDQ1ODA1MX0.jjQXoi5Yvxl2BqR-QlOtjO9vJFWFg4YowjMXTw3WKA0';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: anonKey,
      debug: true,
    );
    // Log minimal environment to help debug auth redirects on web
    try {
      debugPrint('🌐 [SUPABASE] Initialized. Origin: ${Uri.base.origin}  Path: ${Uri.base.path}  HasFragment: ${Uri.base.hasFragment}');
    } catch (_) {}
  }

  /// Debug helper: on web, print redirect params from URL and any error coming from Supabase auth
  /// Safe to call on all platforms; it will no-op on non-web targets.
  static void debugLogAuthRedirect() {
    try {
      final uri = Uri.base; // On web contains query and fragment after redirect
      final queryParams = uri.queryParametersAll;
      final fragment = uri.fragment; // After '#'
      debugPrint('🔎 [AUTH_REDIRECT] URL: ${uri.toString()}');
      if (queryParams.isNotEmpty) {
        debugPrint('🔎 [AUTH_REDIRECT] Query params: $queryParams');
      }
      if (fragment.isNotEmpty) {
        debugPrint('🔎 [AUTH_REDIRECT] Fragment raw: $fragment');
        // Parse fragment into key=value pairs if it looks like querystring
        if (fragment.contains('=') && fragment.contains('&')) {
          final fragUri = Uri.parse('https://dummy.local/?$fragment');
          debugPrint('🔎 [AUTH_REDIRECT] Fragment params: ${fragUri.queryParametersAll}');
          final err = fragUri.queryParameters['error'] ?? fragUri.queryParameters['error_code'];
          final errDesc = fragUri.queryParameters['error_description'];
          if (err != null || errDesc != null) {
            debugPrint('❗ [AUTH_REDIRECT] Error from Supabase: code=$err, description=$errDesc');
          }
          final accessToken = fragUri.queryParameters['access_token'];
          final refreshToken = fragUri.queryParameters['refresh_token'];
          final type = fragUri.queryParameters['type'];
          if (accessToken != null) {
            debugPrint('✅ [AUTH_REDIRECT] access_token present (length=${accessToken.length})  type=$type');
          } else {
            debugPrint('⚠️ [AUTH_REDIRECT] No access_token in fragment. type=$type');
          }
        }
      }

      final user = SupabaseConfig.auth.currentUser;
      debugPrint('👤 [AUTH_REDIRECT] Current user after init: ${user?.email}  confirmedAt=${user?.emailConfirmedAt}');
    } catch (e) {
      debugPrint('⚠️ [AUTH_REDIRECT] Could not parse redirect info: $e');
    }
  }

  /// Test database connection and structure
  static Future<void> testDatabaseConnection() async {
    try {
      debugPrint('🔍 [DB_TEST] Testing database connection...');
      final hasSession = SupabaseConfig.auth.currentUser != null;
      if (!hasSession) {
        debugPrint('⏭️ [DB_TEST] Skipping protected table checks: no authenticated session yet');
        // Optional lightweight connectivity check via a public RPC (ignore if missing)
        try {
          await SupabaseConfig.client.rpc('health_check');
          debugPrint('✅ [DB_TEST] health_check RPC responded');
        } catch (_) {}
        return;
      }
      
      // Test basic table access
      final orders = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .limit(1);
      
      debugPrint('✅ [DB_TEST] Orders table accessible, sample records: ${orders.length}');
      
      // Test order_items table
      final items = await SupabaseConfig.client
          .from('order_items')
          .select('id')
          .limit(1);
      
      debugPrint('✅ [DB_TEST] Order_items table accessible, sample records: ${items.length}');
      
      // Test if accounts table exists (for balance system)
      try {
        final accounts = await SupabaseConfig.client
            .from('accounts')
            .select('id')
            .limit(1);
        debugPrint('✅ [DB_TEST] Accounts table exists, sample records: ${accounts.length}');
      } catch (e) {
        debugPrint('⚠️ [DB_TEST] Accounts table not found: $e');
      }
      
      // Test users table structure
      try {
        final users = await SupabaseConfig.client
            .from('users')
            .select('id, name, role')
            .limit(1);
        debugPrint('✅ [DB_TEST] Users table accessible, sample records: ${users.length}');
      } catch (e) {
        debugPrint('⚠️ [DB_TEST] Users table issue: $e');
      }
      
      debugPrint('✅ [DB_TEST] Database connection test completed');
    } catch (e) {
      debugPrint('❌ [DB_TEST] Database connection test failed: $e');
      if (e is PostgrestException) {
        debugPrint('❌ [DB_TEST] Postgrest code: ${e.code}');
        debugPrint('❌ [DB_TEST] Postgrest message: ${e.message}');
        debugPrint('❌ [DB_TEST] Postgrest details: ${e.details}');
        debugPrint('❌ [DB_TEST] Postgrest hint: ${e.hint}');
      }
    }
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
}

/// Authentication service - Remove this class if your project doesn't need auth
class SupabaseAuth {
  /// Normalize role to canonical English values used by backend: client, restaurant, delivery_agent, admin
  static String normalizeRoleString(dynamic role) {
    final r = role?.toString().toLowerCase().trim() ?? '';
    switch (r) {
      case 'client':
      case 'cliente':
      case 'user':
      case 'usuario':
        return 'client';
      case 'restaurant':
      case 'restaurante':
        return 'restaurant';
      case 'delivery':
      case 'repartidor':
      case 'delivery_agent':
      case 'rider':
      case 'courier':
        return 'delivery_agent';
      case 'admin':
      case 'administrator':
        return 'admin';
      default:
        return 'client';
    }
  }
  /// Sign up with email and password usando RPC Functions (bypasses RLS)
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    Map<String, dynamic>? userData,
  }) async {
    try {
      // Obtener URL de redirect dinámicamente (importante para web)
      String redirectUrl = 'https://i20tpls7s2z0kjevuoyg.share.dreamflow.app';
      try {
        if (kIsWeb) {
          redirectUrl = Uri.base.origin;
        }
      } catch (e) {
        debugPrint('⚠️ Could not get Uri.base.origin, using default: $redirectUrl');
      }
      
      debugPrint('🚀 Starting signup process for: $email');
      debugPrint('🔗 Email redirect URL: $redirectUrl');
      debugPrint('📍 [SIGNUP] userData received in signUp():');
      debugPrint('   - lat: ${userData?['lat']}');
      debugPrint('   - lon: ${userData?['lon']}');
      debugPrint('   - address: ${userData?['address']}');
      debugPrint('   - address_structured: ${userData?['address_structured']}');
      debugPrint('   - Full userData: $userData');
      
      // Registrar usuario en auth.users
      final response = await SupabaseConfig.auth.signUp(
        email: email,
        password: password,
        data: userData,
        emailRedirectTo: redirectUrl,
      );

      if (response.user == null) {
        throw Exception('No se pudo crear el usuario en auth.users');
      }

      debugPrint('✅ User registered in auth.users successfully');
      debugPrint('📧 User needs email verification: ${response.user?.emailConfirmedAt == null}');
      
      // Crear/asegurar perfil en public.users usando RPC (bypasses RLS)
      try {
        debugPrint('📝 Ensuring user profile using RPC...');
        // Intentar versión idempotente primero
        try {
          final rpcParams = {
            'p_user_id': response.user!.id,
            'p_email': email,
            'p_name': userData?['name'] ?? '',
            'p_role': normalizeRoleString(userData?['role']),
            'p_phone': userData?['phone'] ?? '',
            'p_address': userData?['address'] ?? '',
            'p_lat': userData?['lat'],
            'p_lon': userData?['lon'],
            'p_address_structured': userData?['address_structured'],
          };
          
          debugPrint('📍 [RPC] Calling ensure_user_profile_public with params:');
          debugPrint('   - p_lat: ${rpcParams['p_lat']}');
          debugPrint('   - p_lon: ${rpcParams['p_lon']}');
          debugPrint('   - p_address: ${rpcParams['p_address']}');
          debugPrint('   - p_address_structured: ${rpcParams['p_address_structured']}');
          debugPrint('   - Full params: $rpcParams');
          
          final ensureRes = await SupabaseConfig.client.rpc(RpcNames.ensureUserProfilePublic, params: rpcParams);
          debugPrint('🛡️ ensure_user_profile_public result: $ensureRes');
        } on PostgrestException catch (e) {
          if (e.code == 'PGRST202' || e.code == '42883' || e.message.contains('Could not find the function')) {
            debugPrint('↩️ ensure_user_profile_public not available. Falling back to create_user_profile_public');
          } else {
            rethrow;
          }
          // Fallback a create_user_profile_public (puede fallar en instancias legacy por columna metadata)
          try {
            final profileResult = await SupabaseConfig.client.rpc(RpcNames.createUserProfilePublic, params: {
              'p_user_id': response.user!.id,
              'p_email': email,
              'p_name': userData?['name'] ?? '',
              'p_phone': userData?['phone'] ?? '',
              'p_address': userData?['address'] ?? '',
              'p_role': normalizeRoleString(userData?['role']),
              'p_lat': userData?['lat'],
              'p_lon': userData?['lon'],
              'p_address_structured': userData?['address_structured'],
              'p_is_temp_password': false,
            });
            debugPrint('📝 RPC Result: $profileResult');
            if (profileResult is Map && profileResult['success'] != true) {
              debugPrint('⚠️ Warning: Could not create user profile via RPC: ${profileResult['error']}');
            } else {
              debugPrint('✅ User profile created successfully via RPC');
            }
          } on PostgrestException catch (e2) {
            // Tolerar esquema legacy: columna "metadata" no existe en public.users dentro del RPC
            if ((e2.message ?? '').toLowerCase().contains('metadata') || (e2.details ?? '').toString().toLowerCase().contains('metadata')) {
              debugPrint('⚠️ Legacy RPC create_user_profile_public references missing column metadata. Skipping non-fatal.');
            } else {
              debugPrint('⚠️ Warning: Error creating user profile via RPC: ${e2.message} (${e2.code})');
            }
          } catch (e3) {
            debugPrint('⚠️ Warning: Error creating user profile via RPC fallback: $e3');
          }
        }
      } catch (profileError) {
        debugPrint('⚠️ Warning: Error ensuring/creating user profile via RPC: $profileError');
        // No lanzar error - el perfil puede crearse después por trigger
      }
      
      return response;
    } catch (e) {
      debugPrint('❌ Signup error: $e');
      throw _handleAuthError(e);
    }
  }

  /// Ensure the user profile exists in public.users for a given auth user.
  /// Tries ensure_user_profile_public first (idempotent), falls back to create_user_profile_public.
  /// Also attempts to set phone if it's missing, when helper RPC is available.
  static Future<void> ensureUserProfile({
    required String userId,
    required String email,
    Map<String, dynamic>? userData,
    String? role,
  }) async {
    final normalizedRole = normalizeRoleString(role ?? userData?['role']);
    debugPrint('🛡️ Ensuring user profile for $email ($userId) with role=$normalizedRole');
    try {
      // Prefer v2 if available
      try {
        final resV2 = await SupabaseConfig.client.rpc(RpcNames.ensureUserProfileV2, params: {
          'p_user_id': userId,
          'p_email': email,
          'p_role': normalizedRole,
          'p_name': userData?['name'] ?? '',
          'p_phone': userData?['phone'] ?? '',
          'p_address': userData?['address'] ?? '',
          'p_lat': userData?['lat'],
          'p_lon': userData?['lon'],
          'p_address_structured': userData?['address_structured'],
        });
        debugPrint('🛡️ ensure_user_profile_v2 result: $resV2');
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202' && e.code != '42883' && !e.message.contains('Could not find the function')) {
          rethrow;
        }
        debugPrint('↩️ ensure_user_profile_v2 not available. Trying ensure_user_profile_public');
      }

      final res = await SupabaseConfig.client.rpc(RpcNames.ensureUserProfilePublic, params: {
        'p_user_id': userId,
        'p_email': email,
        'p_name': userData?['name'] ?? '',
        'p_role': normalizedRole,
        // Pass optional fields when function signature supports them (ignored otherwise)
        'p_phone': userData?['phone'] ?? '',
        'p_address': userData?['address'] ?? '',
        'p_lat': userData?['lat'],
        'p_lon': userData?['lon'],
        'p_address_structured': userData?['address_structured'],
      });
      debugPrint('🛡️ ensure_user_profile_public result: $res');
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST202' || e.code == '42883' || e.message.contains('Could not find the function')) {
        debugPrint('↩️ ensure_user_profile_public not available. Falling back to create_user_profile_public');
        final res2 = await SupabaseConfig.client.rpc(RpcNames.createUserProfilePublic, params: {
          'p_user_id': userId,
          'p_email': email,
          'p_name': userData?['name'] ?? '',
          'p_phone': userData?['phone'] ?? '',
          'p_address': userData?['address'] ?? '',
          'p_role': normalizedRole,
          'p_lat': userData?['lat'],
          'p_lon': userData?['lon'],
          'p_address_structured': userData?['address_structured'],
          'p_is_temp_password': false,
        });
        debugPrint('🛡️ create_user_profile_public result: $res2');
      } else {
        debugPrint('❌ ensureUserProfile PostgREST error: ${e.message} (${e.code})');
        rethrow;
      }
    }

    // Verify existence
    final existing = await SupabaseConfig.client
        .from('users')
        .select('id, phone, role')
        .eq('id', userId)
        .maybeSingle()
        .timeout(const Duration(seconds: 20));
    if (existing == null) {
      throw Exception('User profile creation failed');
    }

    // If phone is provided but missing in profile, try to set it via helper RPC
    final phone = userData?['phone']?.toString().trim();
    if (phone != null && phone.isNotEmpty && (existing['phone'] == null || existing['phone'].toString().isEmpty)) {
      try {
        await SupabaseConfig.client.rpc(RpcNames.setUserPhoneIfMissing, params: {
          'p_user_id': userId,
          'p_phone': phone,
        });
        debugPrint('📞 set_user_phone_if_missing executed');
      } catch (e) {
        // Best effort only; ignore if function doesn't exist or fails
        debugPrint('ℹ️ set_user_phone_if_missing not available or failed: $e');
      }
    }
  }

  /// Sign in with email and password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      return await SupabaseConfig.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Sign in with Google OAuth
  static Future<AuthResponse> signInWithGoogle() async {
    try {
      debugPrint('🚀 Starting Google OAuth sign-in...');
      // Use dynamic redirect for web to avoid mismatches with share.dreamflow.app subdomain
      // For mobile, use the custom scheme
      final dynamicRedirect = kIsWeb ? Uri.base.origin : 'com.dona.app://login-callback';
      debugPrint('🔗 OAuth redirectTo: $dynamicRedirect');
      final response = await SupabaseConfig.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: dynamicRedirect,
      );
      
      debugPrint('✅ Google OAuth initiated successfully');
      
      // Wait for auth state change to complete
      final authState = await SupabaseConfig.auth.onAuthStateChange
          .firstWhere((data) => data.session != null)
          .timeout(const Duration(seconds: 60));
      
      final user = authState.session?.user;
      
      if (user != null) {
        debugPrint('👤 Google user authenticated: ${user.email}');
        debugPrint('📸 Avatar URL from Google: ${user.userMetadata?['avatar_url']}');
        
        // Check if user profile exists in database
        final existingUser = await SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();
        
        if (existingUser == null) {
          debugPrint('⚠️ User profile does NOT exist in database. Creating now...');
          // Prefer an idempotent SECURITY DEFINER RPC to bypass RLS
          try {
            await SupabaseConfig.client.rpc(RpcNames.ensureUserProfilePublic, params: {
              'p_user_id': user.id,
              'p_email': user.email ?? '',
              'p_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
              'p_role': 'client',
            });
            debugPrint('✅ ensure_user_profile_public executed');
          } on PostgrestException catch (e) {
            if (e.code == 'PGRST202' || e.code == '42883' || e.message.contains('Could not find the function')) {
              debugPrint('↩️ ensure_user_profile_public not available. Falling back to create_user_profile_public');
              try {
                await SupabaseConfig.client.rpc(RpcNames.createUserProfilePublic, params: {
                  'p_user_id': user.id,
                  'p_email': user.email ?? '',
                  'p_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
                  'p_phone': user.userMetadata?['phone'] ?? '',
                  'p_address': user.userMetadata?['address'] ?? '',
                  'p_role': 'client',
                });
                debugPrint('✅ create_user_profile_public executed');
              } catch (e2) {
                debugPrint('⚠️ Could not create user profile via RPC fallback: $e2');
              }
            } else {
              debugPrint('⚠️ PostgREST error calling ensure_user_profile_public: ${e.message} (${e.code})');
            }
          }
        } else {
          debugPrint('✅ User profile exists in database');
          // Update avatar_url if Google provides one and it's different
          debugPrint('ℹ️ User profile synced (avatar handled by client_profiles)');
        }
      }
      
      return AuthResponse(
        session: authState.session,
        user: authState.session?.user,
      );
    } catch (e) {
      debugPrint('❌ Google sign-in error: $e');
      throw _handleAuthError(e);
    }
  }

  /// Sign in with Facebook OAuth
  static Future<AuthResponse> signInWithFacebook() async {
    try {
      debugPrint('🚀 Starting Facebook OAuth sign-in...');

      final dynamicRedirect = kIsWeb ? Uri.base.origin : 'com.dona.app://login-callback';
      debugPrint('🔗 OAuth redirectTo: $dynamicRedirect');
      final response = await SupabaseConfig.auth.signInWithOAuth(
        OAuthProvider.facebook,
        redirectTo: dynamicRedirect,
      );

      debugPrint('✅ Facebook OAuth initiated successfully');

      // Wait for auth state change to complete
      final authState = await SupabaseConfig.auth.onAuthStateChange
          .firstWhere((data) => data.session != null)
          .timeout(const Duration(seconds: 60));

      final user = authState.session?.user;

      if (user != null) {
        debugPrint('👤 Facebook user authenticated: ${user.email}');

        // Check if user profile exists in database
        final existingUser = await SupabaseConfig.client
            .from('users')
            .select('id')
            .eq('id', user.id)
            .maybeSingle();

        if (existingUser == null) {
          debugPrint('⚠️ User profile does NOT exist in database. Creating now...');
          try {
            await SupabaseConfig.client.rpc(RpcNames.ensureUserProfilePublic, params: {
              'p_user_id': user.id,
              'p_email': user.email ?? '',
              'p_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
              'p_role': 'client',
            });
            debugPrint('✅ ensure_user_profile_public executed');
          } on PostgrestException catch (e) {
            if (e.code == 'PGRST202' || e.code == '42883' || e.message.contains('Could not find the function')) {
              debugPrint('↩️ ensure_user_profile_public not available. Falling back to create_user_profile_public');
              try {
                await SupabaseConfig.client.rpc(RpcNames.createUserProfilePublic, params: {
                  'p_user_id': user.id,
                  'p_email': user.email ?? '',
                  'p_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
                  'p_phone': user.userMetadata?['phone'] ?? '',
                  'p_address': user.userMetadata?['address'] ?? '',
                  'p_role': 'client',
                });
                debugPrint('✅ create_user_profile_public executed');
              } catch (e2) {
                debugPrint('⚠️ Could not create user profile via RPC fallback: $e2');
              }
            } else {
              debugPrint('⚠️ PostgREST error calling ensure_user_profile_public: ${e.message} (${e.code})');
            }
          }
        } else {
          debugPrint('✅ User profile exists in database');
        }
      }

      return AuthResponse(
        session: authState.session,
        user: authState.session?.user,
      );
    } catch (e) {
      debugPrint('❌ Facebook sign-in error: $e');
      throw _handleAuthError(e);
    }
  }

  /// Sign out current user
  static Future<void> signOut() async {
    try {
      await SupabaseConfig.auth.signOut();
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Reset password
  static Future<void> resetPassword(String email) async {
    try {
      await SupabaseConfig.auth.resetPasswordForEmail(
        email,
        redirectTo: 'https://1axqls263hxgdsf0e1mn.share.dreamflow.app/',
      );
    } catch (e) {
      throw _handleAuthError(e);
    }
  }

  /// Get current user
  static User? get currentUser => SupabaseConfig.auth.currentUser;

  /// Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  /// Auth state changes stream
  static Stream<AuthState> get authStateChanges =>
      SupabaseConfig.auth.onAuthStateChange;

  /// Handle auth state changes (update email_confirm when user verifies email)
  static void handleAuthStateChange(AuthState state) async {
    final user = state.session?.user;
    final event = state.event;

    debugPrint('🔄 Auth state change: Event: $event, User: ${user?.email}');
    debugPrint('📧 Email confirmed at: ${user?.emailConfirmedAt}');

    // Handle email verification: update email_confirm to true
    if (user != null && event == AuthChangeEvent.signedIn && user.emailConfirmedAt != null) {
      try {
        // Check if user profile exists and needs email confirmation update
        final existingUser = await SupabaseConfig.client
            .from('users')
            .select('email_confirm')
            .eq('id', user.id)
            .maybeSingle();

        if (existingUser != null) {
          // Update email_confirm to true if it's false
          if (existingUser['email_confirm'] == false) {
            await SupabaseConfig.client
                .from('users')
                .update({'email_confirm': true, 'updated_at': DateTime.now().toIso8601String()})
                .eq('id', user.id);
            debugPrint('✅ Updated email_confirm to true for user: ${user.email}');
          }
        } else {
          // If profile doesn't exist, create it (shouldn't happen with new flow)
          debugPrint('⚠️ Profile missing for verified user, creating: ${user.email}');
          await _createUserProfileImmediately(user, user.userMetadata);
        }
      } catch (e) {
        debugPrint('❌ Error handling auth state change: $e');
      }
    }
  }

  /// Create user profile immediately after signup (email_confirm = false)
  static Future<void> _createUserProfileImmediately(
    User user,
    Map<String, dynamic>? userData,
  ) async {
    try {
      debugPrint('🔄 Creating user profile immediately for ${user.email} with ID: ${user.id}');
      debugPrint('🔄 User data: $userData');
      debugPrint('🔄 Email confirmed at: ${user.emailConfirmedAt}');
      debugPrint('🔄 Supabase URL: ${SupabaseConfig.supabaseUrl}');
      debugPrint('🔄 Anon Key: ${SupabaseConfig.anonKey.substring(0, 20)}...');
      
      // Test 1: Basic connectivity test
      try {
        debugPrint('🧪 TEST 1: Testing basic database connectivity...');
        final testResult = await SupabaseConfig.client
            .from('users')
            .select('id')
            .limit(1)
            .timeout(const Duration(seconds: 15));
        debugPrint('✅ TEST 1 PASSED: Database connection verified - got ${testResult.length} rows');
      } catch (connectivityError) {
        debugPrint('❌ TEST 1 FAILED: Database connectivity error: $connectivityError');
        debugPrint('❌ Error type: ${connectivityError.runtimeType}');
        throw 'CONNECTIVITY_ERROR: Cannot connect to Supabase database. Error: $connectivityError';
      }
      
      // Test 2: Check if profile already exists
      try {
        debugPrint('🧪 TEST 2: Checking if user profile already exists...');
        final existingUser = await SupabaseConfig.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle()
            .timeout(const Duration(seconds: 15));
        
        debugPrint('🔍 TEST 2 RESULT: Existing user check: $existingUser');
        
        if (existingUser != null) {
          debugPrint('⚠️ User profile already exists for ${user.email}, skipping creation');
          return;
        }
      } catch (checkError) {
        debugPrint('❌ TEST 2 FAILED: Error checking existing user: $checkError');
        throw 'CHECK_ERROR: Cannot verify existing user profile. Error: $checkError';
      }
      
      // Test 3: Create the profile
      try {
        debugPrint('🧪 TEST 3: Creating new user profile...');
        
        // Determine email_confirm status based on emailConfirmedAt
        final isEmailConfirmed = user.emailConfirmedAt != null;
        
        // Extract avatar_url from metadata (Google OAuth provides this)
        final avatarUrl = user.userMetadata?['avatar_url']?.toString();
        if (avatarUrl != null) {
          debugPrint('📸 Google avatar URL detected: $avatarUrl');
        }
        
          final userProfile = {
          'id': user.id,
          'email': user.email ?? '',
          'name': userData?['name'] ?? '',
          'phone': userData?['phone'] ?? '',
            'role': normalizeRoleString(userData?['role']),
          'email_confirm': isEmailConfirmed, // Set based on actual email confirmation
          // if (avatarUrl != null) 'avatar_url': avatarUrl, // Moved to client_profiles
        };

        debugPrint('📝 TEST 3 DATA: Inserting user profile: $userProfile');

        // Simplified insert without .select() to reduce complexity
        await SupabaseConfig.client
            .from('users')
            .insert(userProfile)
            .timeout(const Duration(seconds: 30)); // Extended timeout for slow connections

        debugPrint('✅ TEST 3 PASSED: User profile created successfully');
        debugPrint('📧 Email confirmation status: $isEmailConfirmed');

        // Persist address to client_profiles if provided
        try {
          await SupabaseClientProfileExtensions.ensureClientProfileAndAccount(userId: user.id);
          final addr = (userData?['address'] ?? '').toString();
          final lat = (userData?['lat'] as num?)?.toDouble();
          final lon = (userData?['lon'] as num?)?.toDouble();
          final addrStructured = userData?['address_structured'] as Map<String, dynamic>?;
          if (addr.isNotEmpty || lat != null || lon != null || addrStructured != null) {
            await DoaRepartosService.updateClientDefaultAddress(
              userId: user.id,
              address: addr,
              lat: lat,
              lon: lon,
              addressStructured: addrStructured,
            );
          }
        } catch (e) {
          debugPrint('ℹ️ Could not persist default client address on create: $e');
        }

        // TEST 4: Auto-create financial account for roles that require it
        try {
          final roleRaw = (userData?['role'] ?? 'cliente').toString().toLowerCase();
          final String? accountType = roleRaw == 'restaurante' || roleRaw == 'restaurant'
              ? 'restaurant'
              : roleRaw == 'repartidor' || roleRaw == 'delivery_agent'
                  ? 'delivery_agent'
                  : null;

          if (accountType != null) {
            debugPrint('🧾 TEST 4: Ensuring financial account for user ${user.id} (type=$accountType)');
            // Check if account exists
            final existingAcc = await SupabaseConfig.client
                .from('accounts')
                .select('id')
                .eq('user_id', user.id)
                .maybeSingle();

            if (existingAcc == null) {
              await SupabaseConfig.client.from('accounts').insert({
                'user_id': user.id,
                'account_type': accountType,
                'balance': 0.00,
              });
              debugPrint('✅ TEST 4 PASSED: Financial account created for ${user.email}');
            } else {
              debugPrint('ℹ️ TEST 4: Account already exists for user ${user.id}');
            }
          } else {
            debugPrint('ℹ️ TEST 4: Role does not require financial account (role=$roleRaw)');
          }
        } catch (accErr) {
          debugPrint('⚠️ TEST 4 WARNING: Could not auto-create financial account: $accErr');
          // Non-fatal: a fallback will ensure account on first session load
        }
        
      } catch (insertError) {
        debugPrint('❌ TEST 3 FAILED: Error inserting user profile: $insertError');
        debugPrint('❌ Insert error type: ${insertError.runtimeType}');
        
        // Specific error handling for insert
        if (insertError is PostgrestException) {
          debugPrint('❌ Postgrest Error Code: ${insertError.code}');
          debugPrint('❌ Postgrest Error Message: ${insertError.message}');
          debugPrint('❌ Postgrest Error Details: ${insertError.details}');
          debugPrint('❌ Postgrest Error Hint: ${insertError.hint}');
          
          if (insertError.code == '42501' || insertError.message.contains('policy')) {
            throw 'RLS_POLICY_ERROR: Row Level Security policy prevents user profile creation. Please check policies for INSERT on "users" table.';
          } else if (insertError.code == '23505' || insertError.message.contains('duplicate key')) {
            throw 'DUPLICATE_USER_ERROR: User profile already exists with this ID.';
          } else if (insertError.code == '42P01' || insertError.message.contains('does not exist')) {
            throw 'TABLE_MISSING_ERROR: Table "users" does not exist. Please run the database schema setup.';
          } else {
            throw 'DATABASE_INSERT_ERROR: ${insertError.message} (Code: ${insertError.code})';
          }
        } else {
          throw 'INSERT_ERROR: Unexpected error creating user profile: $insertError';
        }
      }
      
    } catch (e) {
      debugPrint('❌ FINAL ERROR creating user profile: $e');
      debugPrint('❌ Final error type: ${e.runtimeType}');
      
      // Re-throw with clearer error messages
      if (e.toString().contains('CONNECTIVITY_ERROR')) {
        throw 'Network connection failed. Please check:\n1. Internet connection\n2. Supabase URL is correct\n3. Supabase project is active\n\nTechnical error: $e';
      } else if (e.toString().contains('RLS_POLICY_ERROR')) {
        throw 'Database permission denied. The RLS policy for INSERT on "users" table is blocking the operation. Please check Supabase policies.';
      } else if (e.toString().contains('TABLE_MISSING_ERROR')) {
        throw 'Database table missing. The "users" table does not exist. Please run the database schema setup in Supabase.';
      } else if (e.toString().contains('DUPLICATE_USER_ERROR')) {
        throw 'User already exists. Profile for this user ID already exists in the database.';
      } else {
        throw 'Failed to create user profile: $e';
      }
    }
  }

  /// Create user profile in database (legacy method for auth state handler)
  static Future<void> _createUserProfile(
    User user,
    Map<String, dynamic>? userData,
  ) async {
    return _createUserProfileImmediately(user, userData);
  }

  /// Handle authentication errors
  static String _handleAuthError(dynamic error) {
    if (error is AuthException) {
      switch (error.message) {
        case 'Invalid login credentials':
          return 'Invalid email or password';
        case 'Email not confirmed':
          return 'Please check your email and confirm your account';
        case 'User not found':
          return 'No account found with this email';
        case 'Signup requires a valid password':
          return 'Password must be at least 6 characters';
        case 'Too many requests':
          return 'Too many attempts. Please try again later';
        default:
          return 'Authentication error: ${error.message}';
      }
    } else if (error is PostgrestException) {
      return 'Database error: ${error.message}';
    } else {
      return 'Network error. Please check your connection';
    }
  }
}

/// Specialized database service for Doa Repartos food delivery app
class DoaRepartosService {
  // Import needed for models
  static final _random = [4.1, 4.2, 4.3, 4.4, 4.5, 4.6, 4.7, 4.8, 4.9, 5.0];
  static final _deliveryTimes = [15, 20, 25, 30, 35, 40, 45];
  static final _deliveryFees = [0.0, 0.0, 0.0, 2000.0, 3000.0, 4000.0];
  
  // ========== USERS ==========
  
  /// Get user by ID with role and email confirmation status
  static Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      return await SupabaseConfig.client
          .from('users')
          .select('*, client_profiles(*)')
          .eq('id', userId)
          .maybeSingle();
    } catch (e) {
      throw 'Error fetching user: ${e.toString()}';
    }
  }

  // ========== DELIVERY AGENTS (SYSTEM HEALTH) ==========
  /// Returns true if there is at least one delivery agent online and approved
  static Future<bool> hasActiveCouriers() async {
    try {
      // Llamar a RPC SECURITY DEFINER para evitar RLS
      final result = await SupabaseConfig.client.rpc(RpcNames.hasActiveCouriers);
      final hasAny = (result is bool) ? result : (result?.toString() == 'true');
      debugPrint('📦 [SERVICE] hasActiveCouriers (RPC) = $hasAny');
      return hasAny;
    } on PostgrestException catch (e) {
      debugPrint('⚠️ [SERVICE] hasActiveCouriers Postgrest error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('⚠️ [SERVICE] hasActiveCouriers error: $e');
      return false;
    }
  }

  /// Update email confirmation status
  static Future<void> updateEmailConfirmStatus(String userId, bool confirmed) async {
    try {
      await SupabaseConfig.client
          .from('users')
          .update({
            'email_confirm': confirmed,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (e) {
      throw 'Error updating email confirmation: ${e.toString()}';
    }
  }

  /// Check if user email is confirmed
  static Future<bool> isEmailConfirmed(String userId) async {
    try {
      final user = await SupabaseConfig.client
          .from('users')
          .select('email_confirm')
          .eq('id', userId)
          .maybeSingle();
      return user?['email_confirm'] ?? false;
    } catch (e) {
      debugPrint('Error checking email confirmation: $e');
      return false;
    }
  }

  /// Update user profile
  static Future<void> updateUserProfile(String userId, Map<String, dynamic> data) async {
    try {
      // Always update the updated_at timestamp
      final updateData = {
        ...data,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      await SupabaseConfig.client
          .from('users')
          .update(updateData)
          .eq('id', userId);
    } catch (e) {
      throw 'Error updating user profile: ${e.toString()}';
    }
  }

  /// Update client's default address in client_profiles (preferred with new schema)
  static Future<bool> updateClientDefaultAddress({
    required String userId,
    required String address,
    double? lat,
    double? lon,
    Map<String, dynamic>? addressStructured,
  }) async {
    try {
      debugPrint('🗺️ [updateClientDefaultAddress] INICIO - userId: $userId');
      debugPrint('🗺️ [updateClientDefaultAddress] address: $address');
      debugPrint('🗺️ [updateClientDefaultAddress] lat: $lat');
      debugPrint('🗺️ [updateClientDefaultAddress] lon: $lon');
      debugPrint('🗺️ [updateClientDefaultAddress] addressStructured: $addressStructured');
      
      // 1) Try RPC (SECURITY DEFINER) if available
      try {
        debugPrint('🔧 [updateClientDefaultAddress] Intentando RPC...');
        final rpcParams = {
          'p_user_id': userId,
          'p_address': address,
          if (lat != null) 'p_lat': lat,
          if (lon != null) 'p_lon': lon,
          if (addressStructured != null) 'p_address_structured': addressStructured,
        };
        debugPrint('🔧 [updateClientDefaultAddress] RPC params: $rpcParams');
        
        final rpc = await SupabaseConfig.client.rpc(
          RpcNames.updateClientDefaultAddress,
          params: rpcParams,
        );
        debugPrint('✅ [RPC] update_client_default_address OK: $rpc');
        return true;
      } on PostgrestException catch (e) {
        // Fallback only for function missing or schema cache
        final fnMiss = (e.code == 'PGRST202') || e.code == '404' || e.code == '42883' ||
            e.message.contains('Could not find the function') || e.message.contains('schema cache');
        if (!fnMiss) {
          debugPrint('❌ [RPC] Error en RPC update_client_default_address: ${e.code} - ${e.message}');
          rethrow;
        }
        debugPrint('↩️ [RPC] Fallback: update_client_default_address not available (${e.code}). Using direct upsert.');
      }

      // 2) Direct upsert into client_profiles
      final payload = <String, dynamic>{
        'user_id': userId,
        'address': address,
        'updated_at': DateTime.now().toIso8601String(),
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (addressStructured != null) 'address_structured': addressStructured,
      };

      debugPrint('📝 [updateClientDefaultAddress] FALLBACK - Payload directo: $payload');

      final result = await SupabaseConfig.client
          .from('client_profiles')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .maybeSingle();

      debugPrint('✅ [DB] client_profiles upsert OK para $userId');
      debugPrint('✅ [DB] Resultado: $result');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ updateClientDefaultAddress error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      return false;
    }
  }

  /// Update my phone using a SECURITY DEFINER RPC that enforces uniqueness on server
  /// Returns true if updated, throws a readable error if phone is in use or other failures
  static Future<bool> updateMyPhoneIfUnique(String phone) async {
    try {
      final trimmed = phone.trim();
      if (trimmed.isEmpty) {
        throw 'El teléfono es requerido';
      }
      await SupabaseConfig.client.rpc(
        RpcNames.updateMyPhoneIfUnique,
        params: {
          'p_phone': trimmed,
        },
      );
      return true;
    } on PostgrestException catch (e) {
      // Map server-side exceptions to user-friendly messages
      final msg = (e.message ?? '').toLowerCase();
      if (msg.contains('phone_in_use')) {
        throw 'Este teléfono ya está en uso';
      }
      if (msg.contains('profile_not_found')) {
        throw 'Perfil no encontrado';
      }
      if (e.code == '42501') {
        // Permission denied typically from missing policy when fallback path is used
        throw 'Permisos insuficientes para actualizar el teléfono';
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Upsert user profile (insert if not exists, update if exists)
  static Future<void> upsertUserProfile(String userId, String email, Map<String, dynamic> data) async {
    try {
      debugPrint('🔄 Upserting user profile for: $userId');
      
      // Check if user exists
      final existingUser = await getUserById(userId);
      
      if (existingUser != null) {
        debugPrint('✅ User exists, updating profile...');
        // Split address fields to client_profiles; keep identity fields in users
        final usersUpdate = Map<String, dynamic>.from(data)
          ..remove('address')
          ..remove('lat')
          ..remove('lon')
          ..remove('address_structured');
        if (usersUpdate.isNotEmpty) {
          await updateUserProfile(userId, usersUpdate);
        }
        // Update client profile address if provided
        if (data.containsKey('address') || data.containsKey('lat') || data.containsKey('lon') || data.containsKey('address_structured')) {
          await SupabaseClientProfileExtensions.ensureClientProfileAndAccount(userId: userId);
          await updateClientDefaultAddress(
            userId: userId,
            address: (data['address'] ?? existingUser['client_profiles']?['address'] ?? existingUser['address'] ?? '').toString(),
            lat: (data['lat'] as num?)?.toDouble(),
            lon: (data['lon'] as num?)?.toDouble(),
            addressStructured: data['address_structured'] as Map<String, dynamic>?,
          );
        }
      } else {
        debugPrint('⚠️ User does NOT exist, creating new profile...');
        
        // Create new profile with required fields
        final insertData = {
          'id': userId,
          'email': email,
          'name': data['name'] ?? '',
          'phone': data['phone'] ?? '',
          'role': data['role'] ?? 'cliente',
          'email_confirm': data['email_confirm'] ?? true,
          'avatar_url': data['avatar_url'],
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        
        await SupabaseConfig.client
            .from('users')
            .insert(insertData);
        
        debugPrint('✅ New user profile created');

        // Ensure client profile + financial account and persist address
        await SupabaseClientProfileExtensions.ensureClientProfileAndAccount(userId: userId);
        if (data.containsKey('address') || data.containsKey('lat') || data.containsKey('lon') || data.containsKey('address_structured')) {
          await updateClientDefaultAddress(
            userId: userId,
            address: (data['address'] ?? '').toString(),
            lat: (data['lat'] as num?)?.toDouble(),
            lon: (data['lon'] as num?)?.toDouble(),
            addressStructured: data['address_structured'] as Map<String, dynamic>?,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error upserting user profile: $e');
      throw 'Error creating/updating user profile: ${e.toString()}';
    }
  }

  /// Get users by role (cliente, restaurante, repartidor, admin)
  static Future<List<Map<String, dynamic>>> getUsersByRole(String role, {bool? emailConfirmed}) async {
    try {
      dynamic query = SupabaseConfig.client
          .from('users')
          .select()
          .eq('role', role);
      
      if (emailConfirmed != null) {
        query = query.eq('email_confirm', emailConfirmed);
      }
      
      return await query.order('created_at', ascending: false);
    } catch (e) {
      throw 'Error fetching users by role: ${e.toString()}';
    }
  }

  // ========== RESTAURANTS ==========
  
  /// Get all restaurants with their user info, returns DoaRestaurant objects
  static Future<List<DoaRestaurant>> getRestaurants({String? status, bool? isOnline}) async {
    try {
      print('🔍 Getting restaurants with status filter: $status, online filter: $isOnline');
      
      // Query restaurants WITH user info using JOIN
      dynamic query = SupabaseConfig.client
          .from('restaurants')
          .select('''
            *,
            users:user_id (
              id,
              email,
              name,
              phone,
              role,
              created_at,
              updated_at,
              email_confirm
            )
          ''');
      
      if (status != null && status != 'all') {
        // Handle null status values by using 'is' operator for null check
        if (status == 'pending') {
          query = query.or('status.eq.pending,status.is.null');
        } else {
          query = query.eq('status', status);
        }
      }
      
      // Apply online filter if specified
      if (isOnline != null) {
        query = query.eq('online', isOnline);
      }
      
      final List<Map<String, dynamic>> data = await query.order('created_at', ascending: false);
      print('📊 Found ${data.length} restaurants in database');
      
      // Removed N+1 is_email_verified RPC calls to reduce latency and load.
      // Trust users.email_confirm or verify server-side via triggers/realtime.
      
      // Log ALL restaurant data for debugging
      for (int i = 0; i < data.length; i++) {
        print('📋 Restaurant $i: ${data[i]['name']} - User: ${data[i]['users']}');
      }
      
      return _convertToRestaurantListWithUser(data);
    } catch (e) {
      print('❌ Error fetching restaurants: $e');
      throw 'Error fetching restaurants: ${e.toString()}';
    }
  }

  /// Update restaurant online status
  static Future<void> updateRestaurantOnlineStatus(String restaurantId, bool isOnline) async {
    try {
      print('🔄 Updating restaurant $restaurantId online status to: $isOnline');
      
      await SupabaseConfig.client
          .from('restaurants')
          .update({
            'online': isOnline,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', restaurantId);
      
      print('✅ Restaurant online status updated successfully');
    } catch (e) {
      print('❌ Error updating restaurant online status: $e');
      throw 'Error updating restaurant status: ${e.toString()}';
    }
  }

  /// Get restaurant by user ID
  static Future<Map<String, dynamic>?> getRestaurantByUserId(String userId) async {
    try {
      return await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      throw 'Error fetching restaurant: ${e.toString()}';
    }
  }

  /// Create new restaurant
  static Future<Map<String, dynamic>> createRestaurant(Map<String, dynamic> restaurantData) async {
    try {
      final result = await SupabaseConfig.client
          .from('restaurants')
          .insert(restaurantData)
          .select()
          .single();
      return result;
    } catch (e) {
      throw 'Error creating restaurant: ${e.toString()}';
    }
  }

  /// Update restaurant status (pending, approved, rejected)
  static Future<void> updateRestaurantStatus(String restaurantId, String status) async {
    try {
      await SupabaseConfig.client
          .from('restaurants')
          .update({'status': status})
          .eq('id', restaurantId);
    } catch (e) {
      throw 'Error updating restaurant status: ${e.toString()}';
    }
  }

  // ========== PRODUCTS ==========
  
  /// Get products by restaurant ID
  static Future<List<Map<String, dynamic>>> getProductsByRestaurant(String restaurantId, {bool? isAvailable, String? type}) async {
    try {
      dynamic query = SupabaseConfig.client
          .from('products')
          .select()
          .eq('restaurant_id', restaurantId);
      
      if (isAvailable != null) {
        query = query.eq('is_available', isAvailable);
      }
      if (type != null && type.isNotEmpty) {
        query = query.eq('type', type);
      }
      
      return await query.order('created_at', ascending: false);
    } catch (e) {
      throw 'Error fetching products: ${e.toString()}';
    }
  }

  /// Create new product
  static Future<Map<String, dynamic>> createProduct(Map<String, dynamic> productData) async {
    try {
      final result = await SupabaseConfig.client
          .from('products')
          .insert(productData)
          .select()
          .single();
      return result;
    } catch (e) {
      throw 'Error creating product: ${e.toString()}';
    }
  }

  /// Update product availability
  static Future<void> updateProductAvailability(String productId, bool isAvailable) async {
    try {
      await SupabaseConfig.client
          .from('products')
          .update({'is_available': isAvailable})
          .eq('id', productId);
    } catch (e) {
      throw 'Error updating product availability: ${e.toString()}';
    }
  }

  // ========== COMBOS ==========
  /// Return set of product_ids that are combos for a restaurant
  static Future<Set<String>> getComboProductIdsByRestaurant(String restaurantId) async {
    try {
      final data = await SupabaseConfig.client
          .from('product_combos')
          .select('product_id')
          .eq('restaurant_id', restaurantId);
      return {
        for (final row in data) (row['product_id'] as String)
      };
    } catch (e) {
      debugPrint('⚠️ getComboProductIdsByRestaurant failed (tables may not exist yet): $e');
      return <String>{};
    }
  }

  /// Get combos with their items for a restaurant
  static Future<List<Map<String, dynamic>>> getCombosByRestaurant(String restaurantId) async {
    try {
      final data = await SupabaseConfig.client
          .from('product_combos')
          .select('''
            *,
            items:product_combo_items(*, product:products(*))
          ''')
          .eq('restaurant_id', restaurantId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('⚠️ getCombosByRestaurant failed: $e');
      return [];
    }
  }

  /// Create or update a combo: ensure a product row exists, then link items
  /// combo: {
  ///   'product': {restaurant_id, name, description, price, image_url, is_available},
  ///   'items': [{'product_id': '...', 'quantity': 1}, ...]
  /// }
  static Future<Map<String, dynamic>> upsertCombo({String? productId, required Map<String, dynamic> product, required List<Map<String, dynamic>> items}) async {
    // Always enforce type on server
    product['type'] = 'combo';
    
    // IMPORTANTE: NO enviar 'contains' en product - la RPC lo calcula automáticamente desde 'items'
    // Esto evita conflictos cuando contains viene vacío o null desde el cliente
    product.remove('contains');

    // Prefer RPC so DB validation executes once after all items are applied
    final rpcParams = {
      'product': product,
      'items': items,
      if (productId != null) 'product_id': productId,
    };
    final rpc = await SupabaseRpc.call(RpcNames.upsertComboAtomic, params: rpcParams);
    if (rpc.success) {
      final data = rpc.data;
      if (data is Map<String, dynamic>) return data;
      if (data is List && data.isNotEmpty && data.first is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data.first);
      }
      // Fallback shape
      return {'data': data};
    }

    // If function missing, expose a clear error to run migration script
    if ((rpc.error ?? '').startsWith('FUNCTION_NOT_FOUND')) {
      throw 'Falta la RPC ${RpcNames.upsertComboAtomic}. Ejecuta el script de migración supabase_scripts/2025-11-12_07_RPC_upsert_combo_atomic.sql y vuelve a intentar.';
    }

    // Otherwise bubble the backend validation message
    throw 'Error upserting combo: ${rpc.error ?? 'unknown'}';
  }

  static Future<void> deleteComboByProductId(String productId) async {
    try {
      // Delete combo first (cascade deletes items), then delete product
      try {
        final combo = await SupabaseConfig.client
            .from('product_combos')
            .select('id')
            .eq('product_id', productId)
            .maybeSingle();
        if (combo != null) {
          await SupabaseConfig.client
              .from('product_combos')
              .delete()
              .eq('id', combo['id']);
        }
      } catch (_) {}

      await SupabaseConfig.client
          .from('products')
          .delete()
          .eq('id', productId);
    } catch (e) {
      throw 'Error deleting combo: ${e.toString()}';
    }
  }

  // ========== ORDERS ==========
  
  /// Get orders with full details (restaurant, user, items, products)
  static Future<List<Map<String, dynamic>>> getOrdersWithDetails({String? userId, String? restaurantId, String? status}) async {
    try {
      dynamic query = SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            users:user_id (
              name,
              email,
              phone,
              client_profiles(*)
            ),
            restaurants:restaurant_id (
              name,
              logo_url
            ),
            delivery_agent_user:users!delivery_agent_id(
              name,
              phone
            ),
            order_items (
              *,
              products (
                name,
                image_url
              )
            )
          ''');
      
      if (userId != null) {
        query = query.eq('user_id', userId);
      }
      if (restaurantId != null) {
        query = query.eq('restaurant_id', restaurantId);
      }
      if (status != null) {
        query = query.eq('status', status);
      }
      
      return await query.order('created_at', ascending: false);
    } catch (e) {
      throw 'Error fetching orders: ${e.toString()}';
    }
  }

  // 🎯 Método wrapper para crear órdenes con items usando RPC segura
  static Future<Map<String, dynamic>> createOrderWithItemsStatic({
    required String userId,
    required String restaurantId,
    required double totalAmount,
    required String deliveryAddress,
    required List<Map<String, dynamic>> items,
    String orderNotes = '',
    String paymentMethod = 'cash',
    double? deliveryLat,
    double? deliveryLon,
    String? deliveryPlaceId,
    Map<String, dynamic>? deliveryAddressStructured,
  }) async {
    try {
      print('🎯 [SUPABASE] Wrapper: Creating order using SAFE RPC method...');
      
      // Debug información
      print('🎯 [SUPABASE] userId: $userId');
      print('🎯 [SUPABASE] restaurantId: $restaurantId');
      print('🎯 [SUPABASE] totalAmount: $totalAmount');
      print('🎯 [SUPABASE] deliveryAddress: $deliveryAddress');
      print('🎯 [SUPABASE] items count: ${items.length}');
      
      // 1. Crear orden usando función RPC segura con tipos correctos
      print('🎯 [SUPABASE] Llamando create_order_safe con tipos correctos...');
      if (deliveryLat != null && deliveryLon != null) {
        print('📍 [SUPABASE] Coordenadas de entrega: lat=$deliveryLat, lon=$deliveryLon');
      }
      final orderResult = await SupabaseConfig.client.rpc(RpcNames.createOrderSafe, params: {
        'p_user_id': userId,                              // UUID
        'p_restaurant_id': restaurantId,                  // UUID  
        'p_total_amount': totalAmount,                    // NUMERIC
        'p_delivery_address': deliveryAddress,            // TEXT
        'p_delivery_fee': 35.0,                          // NUMERIC (not INTEGER!)
        'p_order_notes': orderNotes,                     // TEXT (default)
        'p_payment_method': paymentMethod,               // TEXT (default)
      });
      
      print('🎯 [SUPABASE] RPC Response: $orderResult');
      
      // Verificar si la respuesta es directamente el UUID
      String? orderId;
      if (orderResult is String) {
        orderId = orderResult;
      } else if (orderResult is Map && orderResult['id'] != null) {
        orderId = orderResult['id'].toString();
      } else if (orderResult != null) {
        orderId = orderResult.toString();
      }
      
      if (orderId == null || orderId.isEmpty) {
        throw Exception('No se recibió ID de orden válido: $orderResult');
      }
      
      print('✅ [SUPABASE] Orden creada con ID: $orderId');
      
      // 1.5. Si tenemos coordenadas precisas, actualizar la orden ANTES de insertar items
      if (deliveryLat != null && deliveryLon != null) {
        try {
          print('📍 [SUPABASE] Guardando coordenadas y metadatos de entrega...');
          final geoUpdateData = <String, dynamic>{
            'delivery_lat': deliveryLat,
            'delivery_lon': deliveryLon,
            'updated_at': DateTime.now().toIso8601String(),
          };
          if (deliveryPlaceId != null) geoUpdateData['delivery_place_id'] = deliveryPlaceId;
          if (deliveryAddressStructured != null) {
            geoUpdateData['delivery_address_structured'] = deliveryAddressStructured;
          }

          await SupabaseConfig.client.from('orders').update(geoUpdateData).eq('id', orderId);
          print('✅ [SUPABASE] Coordenadas guardadas: lat=$deliveryLat, lon=$deliveryLon');
        } catch (e) {
          print('⚠️ [SUPABASE] Error guardando coordenadas (no-fatal): $e');
          // No lanzar error - las coordenadas son opcionales
        }
      }
      
      // 2. Insertar items usando función RPC segura con JSON (no JSONB)
      if (items.isNotEmpty) {
        print('🎯 [SUPABASE] Insertando items usando RPC con JSON...');
        
        final itemsResult = await SupabaseConfig.client.rpc('insert_order_items_v2', params: {
          'p_order_id': orderId,                          // UUID
          'p_items': items,                               // JSON (not JSONB!)
        });
        
        print('🎯 [SUPABASE] Items RPC Response: $itemsResult');
        
        // La función insert_order_items puede retornar diferentes formatos
        if (itemsResult != null) {
          if (itemsResult is Map && itemsResult['error'] != null) {
            throw Exception('Error inserting items: ${itemsResult['error']}');
          }
          
          final itemsInserted = itemsResult is Map 
              ? (itemsResult['items_inserted'] ?? items.length)
              : items.length;
          
          print('✅ [SUPABASE] $itemsInserted items insertados');
        }
      }
      
      return {
        'success': true,
        'order_id': orderId,
        'message': 'Orden creada exitosamente'
      };
      
    } catch (e) {
      print('❌ [SUPABASE] Wrapper error: $e');
      return {
        'success': false,
        'error': e.toString()
      };
    }
  }

  // Create order with items using direct insert (no RPC, sin deliveryPhone)
  static Future<String> _createOrderWithItemsRPC({
    required String userId,
    required String restaurantId,
    required String deliveryAddress,
    String? orderNotes,
    String paymentMethod = 'cash',
    required double totalAmount,
    double deliveryFee = 35.00,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      print('🎯 [SUPABASE] Usando RPC Functions con UUID...');
      print('🎯 [SUPABASE] Restaurant ID: $restaurantId');
      print('🎯 [SUPABASE] User ID: $userId');
      print('🎯 [SUPABASE] Total: $totalAmount');
      print('🎯 [SUPABASE] Items: ${items.length}');
      
      // Step 1: Create order using RPC function
      final Map<String, dynamic> response = await SupabaseConfig.client
          .rpc(RpcNames.createOrderSafe, params: {
        'p_user_id': userId,
        'p_restaurant_id': restaurantId,
        'p_total_amount': totalAmount,
        'p_delivery_address': deliveryAddress,
        'p_delivery_fee': deliveryFee,
        'p_order_notes': orderNotes ?? '',
        'p_payment_method': paymentMethod,
      });

      print('🎯 [SUPABASE] RPC Response: $response');

      if (response.containsKey('error')) {
        throw Exception('Error creating order: ${response['error']}');
      }

      final String createdOrderId = response['id'].toString();
      print('✅ [SUPABASE] Orden creada con UUID: $createdOrderId');

      // Step 2: Insert order items using RPC function
      if (items.isNotEmpty) {
        print('🎯 [SUPABASE] Insertando ${items.length} items...');
        
        final List<Map<String, dynamic>> itemsForRPC = items.map((item) => {
          'product_id': item['product_id'],
          'quantity': item['quantity'],
          'unit_price': item['unit_price'],
        }).toList();

        print('🎯 [SUPABASE] Items for RPC: $itemsForRPC');

        final dynamic itemsResponse = await SupabaseConfig.client
            .rpc(RpcNames.insertOrderItemsV2, params: {
          'p_order_id': createdOrderId,
          'p_items': itemsForRPC,
        });

        print('🎯 [SUPABASE] Items RPC Response: $itemsResponse');

        if (itemsResponse is Map && itemsResponse.containsKey('error')) {
          throw Exception('Error creating order items: ${itemsResponse['error']}');
        }

        print('✅ [SUPABASE] Items insertados correctamente');
      }

      print('✅ [SUPABASE] Orden y items creados exitosamente: $createdOrderId');
      return createdOrderId;

    } on PostgrestException catch (e) {
      print('❌ [SUPABASE] Error insertando orden: $e');
      print('❌ [SUPABASE] Error type: ${e.runtimeType}');
      print('❌ [SUPABASE] Postgrest code: ${e.code}');
      print('❌ [SUPABASE] Postgrest message: ${e.message}');
      print('❌ [SUPABASE] Postgrest details: ${e.details}');
      print('❌ [SUPABASE] Postgrest hint: ${e.hint}');
      rethrow;
    } catch (e, stackTrace) {
      print('❌ [SUPABASE] Error general creando orden: $e');
      print('❌ [SUPABASE] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Update order status
  static Future<void> updateOrderStatus(String orderId, String status, {String? deliveryAgentId}) async {
    try {
      final updateData = <String, dynamic>{'status': status};
      if (deliveryAgentId != null) {
        updateData['delivery_agent_id'] = deliveryAgentId;
      }
      
      await SupabaseConfig.client
          .from('orders')
          .update(updateData)
          .eq('id', orderId);
    } catch (e) {
      throw 'Error updating order status: ${e.toString()}';
    }
  }

  /// Accept an order atomically via RPC (assigns current user and sets status 'assigned')
  static Future<bool> acceptOrder(String orderId) async {
    try {
      debugPrint('✋ [SUPABASE] RPC accept_order for: $orderId');
      final result = await SupabaseConfig.client
          .rpc(RpcNames.acceptOrder, params: {'p_order_id': orderId});
      debugPrint('📦 [SUPABASE] accept_order result: $result');

      if (result is Map && result['success'] == true) return true;
      // Some setups might return json as string
      if (result is String) {
        if (result.contains('success') && result.contains('true')) return true;
      }
      return false;
    } on PostgrestException catch (e) {
      debugPrint('❌ [SUPABASE] accept_order Postgrest error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [SUPABASE] accept_order error: $e');
      rethrow;
    }
  }

  /// Mark an order as not delivered via SECURITY DEFINER RPC
  /// Server will:
  /// - Set orders.status = 'not_delivered'
  /// - Create client_debts record and financial transactions
  /// - Preserve audit trail and reason/notes/photo_url
  static Future<bool> markOrderNotDelivered({
    required String orderId,
    required String deliveryAgentId,
    required String reason,
    String? notes,
    String? photoUrl,
  }) async {
    try {
      debugPrint('🚫 [SUPABASE] RPC mark_order_not_delivered for: $orderId');
      final params = <String, dynamic>{
        'p_order_id': orderId,
        'p_delivery_agent_id': deliveryAgentId,
        'p_reason': reason,
        if (notes != null && notes.isNotEmpty) 'p_delivery_notes': notes,
        if (photoUrl != null && photoUrl.isNotEmpty) 'p_photo_url': photoUrl,
      };
      debugPrint('📤 [SUPABASE] Params: $params');
      final result = await SupabaseConfig.client
          .rpc(RpcNames.markOrderNotDelivered, params: params);
      debugPrint('📦 [SUPABASE] mark_order_not_delivered result: $result');

      if (result is Map && result['success'] == true) return true;
      if (result is String) {
        if (result.contains('success') && result.contains('true')) return true;
      }
      return false;
    } on PostgrestException catch (e) {
      debugPrint('❌ [SUPABASE] mark_order_not_delivered Postgrest error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [SUPABASE] mark_order_not_delivered error: $e');
      rethrow;
    }
  }

  /// Get available orders for delivery agents
  static Future<List<Map<String, dynamic>>> getAvailableOrdersForDelivery() async {
    try {
      debugPrint('🔍 [SERVICE] Buscando pedidos disponibles para repartidores...');
      // Mostrar solo pedidos aceptados por el restaurante y aún sin repartidor
      final res = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            restaurants:restaurant_id (
              name,
              address,
              phone
            )
          ''')
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup'])
          .isFilter('delivery_agent_id', null)
          .order('created_at', ascending: true);

      debugPrint('📦 [SERVICE] Pedidos disponibles encontrados: ${res.length}');
      return List<Map<String, dynamic>>.from(res as List);
    } on PostgrestException catch (e) {
      debugPrint('❌ [SERVICE] Error Postgrest al obtener pedidos disponibles: ${e.message}');
      rethrow;
    } catch (e) {
      throw 'Error fetching available orders: ${e.toString()}';
    }
  }

  // ========== PAYMENTS ==========
  
  /// Create payment record
  static Future<Map<String, dynamic>> createPayment(Map<String, dynamic> paymentData) async {
    try {
      final result = await SupabaseConfig.client
          .from('payments')
          .insert(paymentData)
          .select()
          .single();
      return result;
    } catch (e) {
      throw 'Error creating payment: ${e.toString()}';
    }
  }

  /// Update payment status
  static Future<void> updatePaymentStatus(String paymentId, String status) async {
    try {
      await SupabaseConfig.client
          .from('payments')
          .update({'status': status})
          .eq('id', paymentId);
    } catch (e) {
      throw 'Error updating payment status: ${e.toString()}';
    }
  }

  /// Get payment by order ID
  static Future<Map<String, dynamic>?> getPaymentByOrderId(String orderId) async {
    try {
      return await SupabaseConfig.client
          .from('payments')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();
    } catch (e) {
      throw 'Error fetching payment: ${e.toString()}';
    }
  }

  // ========== DELIVERY AGENTS ==========
  
  /// Get all delivery agents (repartidores) with user info
  static Future<List<Map<String, dynamic>>> getDeliveryAgents({String? status}) async {
    try {
      print('🔍 Getting delivery agents (repartidores) from profiles+users');

      // Cargar desde delivery_agent_profiles y hacer join con users
      // Esto asegura que el status provenga SIEMPRE del perfil (delivery_agent_profiles.status)
      final rows = await SupabaseConfig.client
          .from('delivery_agent_profiles')
          .select('''
            user_id,
            status,
            account_state,
            updated_at,
            profile_image_url,
            id_document_front_url,
            id_document_back_url,
            vehicle_type,
            vehicle_plate,
            vehicle_model,
            vehicle_color,
            vehicle_registration_url,
            vehicle_insurance_url,
            vehicle_photo_url,
            emergency_contact_name,
            emergency_contact_phone,
            users ( id,email,name,phone,role,created_at,updated_at,email_confirm )
          ''')
          .order('updated_at', ascending: false);

      print('📊 Found ${rows.length} delivery agents in database (profiles+users)');

      // Aplanar estructura para que los modelos existentes puedan parsear
      final data = <Map<String, dynamic>>[];
      for (final r in rows) {
        final row = Map<String, dynamic>.from(r as Map);
        final users = row['users'] != null ? Map<String, dynamic>.from(row['users']) : <String, dynamic>{};
        
        // Verificar el estado REAL de verificación de email desde auth.users
        // Removed per-row email verification RPC to avoid N+1 calls.
        
        final flattened = <String, dynamic>{
          ...users,
          'id': users['id'] ?? row['user_id'],
          'user_id': row['user_id'],
          'status': (row['status'] ?? users['status'])?.toString(),
          'account_state': row['account_state']?.toString(),
          'created_at': users['created_at'],
          'updated_at': row['updated_at'] ?? users['updated_at'],
          // From delivery_agent_profiles (documents, vehicle, emergency contact, geo)
          'profile_image_url': row['profile_image_url'],
          'id_document_front_url': row['id_document_front_url'],
          'id_document_back_url': row['id_document_back_url'],
          'vehicle_type': row['vehicle_type'],
          'vehicle_plate': row['vehicle_plate'],
          'vehicle_model': row['vehicle_model'],
          'vehicle_color': row['vehicle_color'],
          'vehicle_registration_url': row['vehicle_registration_url'],
          'vehicle_insurance_url': row['vehicle_insurance_url'],
          'vehicle_photo_url': row['vehicle_photo_url'],
          'emergency_contact_name': row['emergency_contact_name'],
          'emergency_contact_phone': row['emergency_contact_phone'],
          // Nota: delivery_agent_profiles no contiene lat/lon; omitimos coordenadas aquí
          'lat': users['lat'],
          'lon': users['lon'],
          'address_structured': users['address_structured'],
        };
        data.add(flattened);
      }

      // Filtro por estado opcional
      if (status != null && status.isNotEmpty && status != 'all') {
        final s = status.toLowerCase();
        final filtered = data.where((e) => (e['status']?.toString().toLowerCase() ?? 'pending') == s).toList();
        print('🎯 Filtered by status=$status -> ${filtered.length} rows');
        return filtered;
      }

      // Log delivery agents para debugging
      for (int i = 0; i < data.length; i++) {
        print('📋 Delivery Agent $i: ${data[i]['name']} - Email: ${data[i]['email']} - Status: ${data[i]['status']}');
      }

      return data;
    } on PostgrestException catch (e) {
      debugPrint('❌ [ADMIN] PostgrestException while fetching delivery agents');
      debugPrint('   • code: ${e.code}');
      debugPrint('   • message: ${e.message}');
      debugPrint('   • details: ${e.details}');
      debugPrint('   • hint: ${e.hint}');
      throw 'Error fetching delivery agents: ${e.message}';
    } catch (e) {
      print('❌ Error fetching delivery agents: $e');
      throw 'Error fetching delivery agents: ${e.toString()}';
    }
  }

  /// Create delivery agent profile
  static Future<Map<String, dynamic>> createDeliveryAgent(Map<String, dynamic> deliveryData) async {
    try {
      final result = await SupabaseConfig.client
          .from('delivery_agents')
          .insert(deliveryData)
          .select()
          .single();
      return result;
    } catch (e) {
      throw 'Error creating delivery agent: ${e.toString()}';
    }
  }

  /// Get delivery agent by user ID
  static Future<Map<String, dynamic>?> getDeliveryAgentByUserId(String userId) async {
    try {
      // Leer perfil + usuario y devolver estructura aplanada, priorizando el status del perfil
      final profileRow = await SupabaseConfig.client
          .from('delivery_agent_profiles')
          .select('''
            user_id,
            status,
            account_state,
            updated_at,
            profile_image_url,
            id_document_front_url,
            id_document_back_url,
            vehicle_type,
            vehicle_plate,
            vehicle_model,
            vehicle_color,
            vehicle_registration_url,
            vehicle_insurance_url,
            vehicle_photo_url,
            emergency_contact_name,
            emergency_contact_phone,
            users ( id,email,name,phone,role,created_at,updated_at )
          ''')
          .eq('user_id', userId)
          .maybeSingle();

      if (profileRow != null) {
        final p = Map<String, dynamic>.from(profileRow);
        final users = p['users'] != null ? Map<String, dynamic>.from(p['users']) : <String, dynamic>{};
        final flattened = <String, dynamic>{
          ...users,
          'id': users['id'] ?? p['user_id'],
          'user_id': p['user_id'],
          'status': (p['status'] ?? users['status'])?.toString(),
          'account_state': p['account_state']?.toString(),
          'created_at': users['created_at'],
          'updated_at': p['updated_at'] ?? users['updated_at'],
          // From delivery_agent_profiles (documents, vehicle, emergency contact, geo)
          'profile_image_url': p['profile_image_url'],
          'id_document_front_url': p['id_document_front_url'],
          'id_document_back_url': p['id_document_back_url'],
          'vehicle_type': p['vehicle_type'],
          'vehicle_plate': p['vehicle_plate'],
          'vehicle_model': p['vehicle_model'],
          'vehicle_color': p['vehicle_color'],
          'vehicle_registration_url': p['vehicle_registration_url'],
          'vehicle_insurance_url': p['vehicle_insurance_url'],
          'vehicle_photo_url': p['vehicle_photo_url'],
          'emergency_contact_name': p['emergency_contact_name'],
          'emergency_contact_phone': p['emergency_contact_phone'],
          'lat': users['lat'],
          'lon': users['lon'],
          'address_structured': users['address_structured'],
        };
        return flattened;
      }

      // Si no existe perfil, intentar al menos devolver el usuario para que la UI no falle
      final userRow = await SupabaseConfig.client
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (userRow == null) return null;
      final u = Map<String, dynamic>.from(userRow);
      u['id'] = u['id'] ?? userId;
      u['user_id'] = u['id'];
      return u;
    } on PostgrestException catch (e) {
      debugPrint('❌ [ADMIN] PostgrestException while fetching delivery agent by userId');
      debugPrint('   • code: ${e.code}');
      debugPrint('   • message: ${e.message}');
      debugPrint('   • details: ${e.details}');
      debugPrint('   • hint: ${e.hint}');
      throw 'Error fetching delivery agent: ${e.message}';
    } catch (e) {
      throw 'Error fetching delivery agent: ${e.toString()}';
    }
  }

  /// Update delivery agent availability
  static Future<void> updateDeliveryAgentAvailability(String userId, bool isAvailable) async {
    try {
      await SupabaseConfig.client
          .from('delivery_agents')
          .update({'is_available': isAvailable})
          .eq('id', userId);
    } catch (e) {
      throw 'Error updating delivery agent availability: ${e.toString()}';
    }
  }

  // ========== ANALYTICS ==========
  
  /// Get restaurant analytics
  static Future<Map<String, dynamic>> getRestaurantAnalytics(String restaurantId) async {
    try {
      // Get total orders count
      final ordersCountResult = await SupabaseConfig.client
          .from('orders')
          .select('id')
          .eq('restaurant_id', restaurantId);
      
      // Get total revenue (sum of completed orders)
      final revenueResult = await SupabaseConfig.client
          .from('orders')
          .select('total_amount')
          .eq('restaurant_id', restaurantId)
          .eq('status', 'delivered');
      
      double totalRevenue = 0;
      for (final order in revenueResult) {
        totalRevenue += (order['total_amount'] as num).toDouble();
      }
      
      // Get popular products
      final popularProducts = await SupabaseConfig.client
          .from('order_items')
          .select('''
            product_id,
            quantity,
            products!inner (
              name,
              restaurant_id
            )
          ''')
          .eq('products.restaurant_id', restaurantId);
      
      return {
        'total_orders': ordersCountResult.length,
        'total_revenue': totalRevenue,
        'popular_products': popularProducts,
      };
    } catch (e) {
      throw 'Error fetching restaurant analytics: ${e.toString()}';
    }
  }

  /// Convert raw data to DoaRestaurant objects with user info (optimized method)
  static List<DoaRestaurant> _convertToRestaurantListWithUser(List<Map<String, dynamic>> data) {
    return data.map((json) {
      try {
        // Handle the nested user data from the JOIN
        DoaUser? user;
        if (json['users'] != null) {
          final userData = json['users'] as Map<String, dynamic>;
          user = DoaUser(
            id: userData['id'] ?? json['user_id'] ?? '',
            email: userData['email'] ?? '',
            name: userData['name'],
            phone: userData['phone'],
            address: userData['address'],
            role: UserRole.fromString(userData['role'] ?? 'restaurante'),
            createdAt: DateTime.tryParse(userData['created_at'] ?? '') ?? DateTime.now(),
            updatedAt: DateTime.tryParse(userData['updated_at'] ?? '') ?? DateTime.now(),
            emailConfirm: userData['email_confirm'] ?? false,
          );
        }
        
        // Create the restaurant object with proper model fields
        return DoaRestaurant(
          id: json['id'] ?? '',
          userId: json['user_id'] ?? '',
          name: json['name'] ?? '',
          description: json['description'],
          logoUrl: json['logo_url'],
          status: RestaurantStatus.fromString(json['status']),
          createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(json['updated_at'] ?? json['created_at'] ?? '') ?? DateTime.now(),
          user: user,
          // UI properties
          imageUrl: json['image_url'] ?? json['logo_url'],
          rating: (json['rating'] as num?)?.toDouble(),
          deliveryTime: json['delivery_time'] as int?,
          deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
          isOpen: json['is_open'] ?? true,
        );
      } catch (e) {
        print('❌ Error converting restaurant with user data: $e');
        print('📋 Raw data: $json');
        // Return a basic restaurant if conversion fails
        return DoaRestaurant(
          id: json['id'] ?? 'unknown',
          userId: json['user_id'] ?? 'unknown', 
          name: json['name'] ?? 'Unknown Restaurant',
          description: json['description'],
          logoUrl: json['logo_url'],
          status: RestaurantStatus.fromString(json['status']),
          createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
        );
      }
    }).toList();
  }

  /// Convert raw data to DoaRestaurant objects with user info
  static List<DoaRestaurant> _convertToRestaurantList(List<Map<String, dynamic>> data) {
    return data.map((json) {
      // Handle the nested user data from the join
      DoaUser? user;
      if (json['users'] != null) {
        final userData = json['users'] as Map<String, dynamic>;
        user = DoaUser(
          id: json['user_id'] ?? '',
          email: userData['email'] ?? '',
          name: userData['name'],
          phone: userData['phone'],
          address: userData['address'],
          role: UserRole.restaurant, // Correct enum value
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          emailConfirm: userData['email_confirm'] ?? false,
        );
      }
      
      // Create the restaurant object with proper model fields
      return DoaRestaurant(
        id: json['id'] ?? '',
        userId: json['user_id'] ?? '',
        name: json['name'] ?? '',
        description: json['description'],
        logoUrl: json['logo_url'],
        status: _parseRestaurantStatus(json['status']),
        online: json['online'] ?? false, // ✅ FIXED: Added missing online field
        createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
        updatedAt: json['updated_at'] != null 
            ? DateTime.parse(json['updated_at']) 
            : DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
        user: user,
        // UI properties
        imageUrl: json['image_url'] ?? json['logo_url'],
        rating: (json['rating'] as num?)?.toDouble(),
        deliveryTime: json['delivery_time'] as int?,
        deliveryFee: (json['delivery_fee'] as num?)?.toDouble(),
        isOpen: json['is_open'] ?? true,
      );
    }).toList();
  }

  /// Convert raw data to DoaRestaurant objects (simple conversion)
  static List<DoaRestaurant> _simpleConvertToRestaurantList(List<Map<String, dynamic>> data) {
    return data.map((json) {
      try {
        // Ensure dates are properly handled - provide defaults if missing
        final Map<String, dynamic> processedJson = {
          ...json,
          'created_at': json['created_at'] ?? DateTime.now().toIso8601String(),
          'updated_at': json['updated_at'] ?? json['created_at'] ?? DateTime.now().toIso8601String(),
        };
        
        return DoaRestaurant.fromJson(processedJson);
      } catch (e) {
        print('❌ Error converting restaurant data: $e');
        print('📋 Raw data: $json');
        // Return a basic restaurant if conversion fails
        return DoaRestaurant(
          id: json['id'] ?? 'unknown',
          userId: json['user_id'] ?? 'unknown',
          name: json['name'] ?? 'Unknown Restaurant',
          description: json['description'],
          logoUrl: json['logo_url'],
          status: RestaurantStatus.fromString(json['status']),
          online: json['online'] ?? false, // ✅ FIXED: Added missing online field in fallback
          createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
          updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
        );
      }
    }).toList();
  }

  /// Parse restaurant status string to enum
  static RestaurantStatus _parseRestaurantStatus(String? status) {
    // Handle null or empty status as pending
    if (status == null || status.isEmpty) {
      return RestaurantStatus.pending;
    }
    
    switch (status.toLowerCase()) {
      case 'approved':
        return RestaurantStatus.approved;
      case 'rejected':
        return RestaurantStatus.rejected;
      case 'pending':
        return RestaurantStatus.pending;
      default:
        // Log unexpected status values for debugging
        print('Unknown restaurant status: $status - defaulting to pending');
        return RestaurantStatus.pending;
    }
  }

  // ========== USER ORDERS SECTION ==========

  /// Get orders by user ID with optional filtering
  static Future<List<DoaOrder>> getOrdersByUser({
    required String userId,
    List<String>? statuses,
    int? limit,
  }) async {
    try {
      print('🔍 [SERVICE] Obteniendo pedidos para usuario: $userId');
      print('🔍 [SERVICE] Estados filtro: $statuses');
      
      // Query simplificado y más tolerante - primero obtener órdenes básicas
      var baseQuery = SupabaseConfig.client
          .from('orders')
          .select('''
            id,
            user_id,
            restaurant_id,
            delivery_agent_id,
            status,
            total_amount,
            payment_method,
            delivery_address,
            delivery_latlng,
            created_at,
            updated_at
          ''')
          .eq('user_id', userId);
      
      // Filtrar por estados si se proporcionan
      if (statuses != null && statuses.isNotEmpty) {
        baseQuery = baseQuery.inFilter('status', statuses);
      }
      
      // Ejecutar la consulta con ordenamiento y límite
      final query = baseQuery.order('created_at', ascending: false);
      
      final List<Map<String, dynamic>> data = await (limit != null 
        ? query.limit(limit) 
        : query);
      
      print('📊 [SERVICE] Pedidos encontrados: ${data.length}');
      if (data.isNotEmpty) {
        print('📋 [SERVICE] Primer pedido - ID: ${data[0]['id']}, Status: ${data[0]['status']}');
        print('📋 [SERVICE] Restaurant ID: ${data[0]['restaurant_id']}');
      }
      
      // Enriquecer órdenes con datos de restaurant si es necesario
      final enrichedOrders = <DoaOrder>[];
      
      for (final orderJson in data) {
        try {
          // Si tenemos restaurant_id, intentar obtener la información del restaurant
          if (orderJson['restaurant_id'] != null) {
            try {
              final restaurantData = await SupabaseConfig.client
                  .from('restaurants')
                  .select('id, name, description, logo_url, address, phone, online')
                  .eq('id', orderJson['restaurant_id'])
                  .maybeSingle();
              
              if (restaurantData != null) {
                orderJson['restaurants'] = restaurantData;
                print('✅ [SERVICE] Restaurant data added for order ${orderJson['id']}');
              }
            } catch (restaurantError) {
              print('⚠️ [SERVICE] No se pudo obtener restaurant: $restaurantError');
            }
          }
          
          final order = DoaOrder.fromJson(orderJson);
          enrichedOrders.add(order);
        } catch (orderParseError) {
          print('❌ [SERVICE] Error parsing order ${orderJson['id']}: $orderParseError');
          // Continuar con las siguientes órdenes en lugar de fallar completamente
        }
      }
      
      print('✅ [SERVICE] Órdenes procesadas exitosamente: ${enrichedOrders.length}');
      return enrichedOrders;
    } catch (e) {
      print('❌ [SERVICE] Error obteniendo pedidos del usuario: $e');
      print('❌ [SERVICE] Stack trace completo: ${StackTrace.current}');
      throw 'Error fetching orders by user: ${e.toString()}';
    }
  }

  /// Get current authenticated user
  static DoaUser? getCurrentUser() {
    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session?.user == null) {
        print('❌ [SERVICE] No hay sesión de usuario activa');
        return null;
      }

      final user = session!.user;
      print('✅ [SERVICE] Usuario actual: ${user.email} (ID: ${user.id})');
      
      // Crear un DoaUser básico con la información disponible
      return DoaUser(
        id: user.id,
        email: user.email ?? '',
        name: user.userMetadata?['name']?.toString() ?? user.email ?? 'Usuario',
        phone: user.userMetadata?['phone']?.toString() ?? '',
        address: user.userMetadata?['address']?.toString() ?? '',
        role: _parseUserRole(user.userMetadata?['role']?.toString() ?? 'cliente'),
        createdAt: user.createdAt != null ? DateTime.parse(user.createdAt!) : DateTime.now(),
        updatedAt: DateTime.now(),
        status: UserStatus.offline, // Default status for general users
        emailConfirm: user.emailConfirmedAt != null, // ✅ Check auth.users email confirmation
      );
    } catch (e) {
      print('❌ [SERVICE] Error obteniendo usuario actual: $e');
      return null;
    }
  }

  /// Get detailed user data from database
  static Future<DoaUser?> getCurrentUserFromDatabase() async {
    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session?.user == null) {
        return null;
      }

      final userId = session!.user.id;
      final userData = await getUserById(userId);
      
      if (userData != null && userData.isNotEmpty) {
        return DoaUser.fromJson(userData[0]);
      }
      
      return null;
    } catch (e) {
      print('❌ [SERVICE] Error obteniendo datos de usuario de la base de datos: $e');
      return null;
    }
  }

  /// Parse user role string to enum
  static UserRole _parseUserRole(String role) {
    switch (role.toLowerCase()) {
      case 'cliente':
      case 'client':
      case 'usuario':
      case 'user':
        return UserRole.client;
      case 'restaurante':
      case 'restaurant':
        return UserRole.restaurant;
      case 'repartidor':
      case 'delivery':
      case 'delivery_agent':
      case 'rider':
      case 'courier':
        return UserRole.delivery_agent;
      case 'admin':
      case 'administrator':
        return UserRole.admin;
      default:
        return UserRole.client;
    }
  }

  /// DEBUG: Check if there are any orders in the database
  static Future<void> debugCheckOrdersInDatabase() async {
    try {
      print('🔍 [DEBUG] === VERIFICANDO ÓRDENES EN BASE DE DATOS ===');
      
      // Obtener todas las órdenes para debug
      final allOrders = await SupabaseConfig.client
          .from('orders')
          .select('id, user_id, status, created_at')
          .order('created_at', ascending: false)
          .limit(10);
      
      print('📊 [DEBUG] Total de órdenes en BD: ${allOrders.length}');
      
      if (allOrders.isNotEmpty) {
        for (int i = 0; i < allOrders.length; i++) {
          final order = allOrders[i];
          print('📋 [DEBUG] Orden $i: ID=${order['id']?.toString().substring(0, 8)}, UserID=${order['user_id']}, Status=${order['status']}');
        }
      } else {
        print('❌ [DEBUG] NO HAY ÓRDENES EN LA BASE DE DATOS');
      }
      
      // Verificar usuario actual
      final currentUser = getCurrentUser();
      if (currentUser != null) {
        print('👤 [DEBUG] Usuario actual ID: ${currentUser.id}');
        
        // Buscar órdenes específicas de este usuario
        final userOrders = await SupabaseConfig.client
            .from('orders')
            .select('id, status, created_at')
            .eq('user_id', currentUser.id);
        
        print('📊 [DEBUG] Órdenes del usuario actual: ${userOrders.length}');
        for (final order in userOrders) {
          print('📋 [DEBUG] Orden del usuario: ID=${order['id']?.toString().substring(0, 8)}, Status=${order['status']}');
        }
      } else {
        print('❌ [DEBUG] NO HAY USUARIO AUTENTICADO');
      }
      
      print('🔍 [DEBUG] === FIN DE VERIFICACIÓN ===');
    } catch (e) {
      print('❌ [DEBUG] Error verificando órdenes: $e');
    }
  }
}

/// Generic database service for CRUD operations
class SupabaseService {
  /// Select multiple records from a table
  static Future<List<Map<String, dynamic>>> select(
    String table, {
    String? select,
    Map<String, dynamic>? filters,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      // Apply filters
      if (filters != null) {
        for (final entry in filters.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }

      // Apply ordering
      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }

      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }

      return await query;
    } catch (e) {
      throw _handleDatabaseError('select', table, e);
    }
  }

  /// Select a single record from a table
  static Future<Map<String, dynamic>?> selectSingle(
    String table, {
    String? select,
    required Map<String, dynamic> filters,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).select(select ?? '*');

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      return await query.maybeSingle();
    } catch (e) {
      throw _handleDatabaseError('selectSingle', table, e);
    }
  }

  /// Insert a record into a table
  static Future<List<Map<String, dynamic>>> insert(
    String table,
    Map<String, dynamic> data,
  ) async {
    try {
      return await SupabaseConfig.client.from(table).insert(data).select();
    } catch (e) {
      throw _handleDatabaseError('insert', table, e);
    }
  }

  /// Insert multiple records into a table
  static Future<List<Map<String, dynamic>>> insertMultiple(
    String table,
    List<Map<String, dynamic>> data,
  ) async {
    try {
      return await SupabaseConfig.client.from(table).insert(data).select();
    } catch (e) {
      throw _handleDatabaseError('insertMultiple', table, e);
    }
  }

  /// Update records in a table
  static Future<List<Map<String, dynamic>>> update(
    String table,
    Map<String, dynamic> data, {
    required Map<String, dynamic> filters,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).update(data);

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      return await query.select();
    } catch (e) {
      throw _handleDatabaseError('update', table, e);
    }
  }

  /// Delete records from a table
  static Future<void> delete(
    String table, {
    required Map<String, dynamic> filters,
  }) async {
    try {
      dynamic query = SupabaseConfig.client.from(table).delete();

      for (final entry in filters.entries) {
        query = query.eq(entry.key, entry.value);
      }

      await query;
    } catch (e) {
      throw _handleDatabaseError('delete', table, e);
    }
  }

  /// Get direct table reference for complex queries
  static SupabaseQueryBuilder from(String table) =>
      SupabaseConfig.client.from(table);

  /// Handle database errors
  static String _handleDatabaseError(
    String operation,
    String table,
    dynamic error,
  ) {
    if (error is PostgrestException) {
      return 'Failed to $operation from $table: ${error.message}';
    } else {
      return 'Failed to $operation from $table: ${error.toString()}';
    }
  }
}

/// Extensiones para perfiles y cuentas del cliente (client_profiles + accounts)
extension SupabaseClientProfileExtensions on SupabaseConfig {
  /// Asegura (idempotente) que exista client_profiles y su cuenta 'client' con balance 0
  /// IMPORTANTE: Asume que public.users ya existe (creado por master_handle_signup trigger)
  static Future<void> ensureClientProfileAndAccount({required String userId}) async {
    try {
      // Preferir RPC (SECURITY DEFINER) para respetar RLS y lógica de negocio
      try {
        final res = await SupabaseConfig.client.rpc(
          RpcNames.ensureClientProfileAndAccount,
          params: {'p_user_id': userId},
        );
        debugPrint('✅ [RPC] ensure_client_profile_and_account OK: $res');
        return;
      } on PostgrestException catch (e) {
        // Fallback solo si la función no existe o hay un schema cache miss
        if ((e.code == 'PGRST202') || e.code == '404' || e.code == '42883' ||
            e.message.contains('Could not find the function') || e.message.contains('schema cache')) {
          debugPrint('↩️ [RPC] Fallback: ensure_client_profile_and_account no disponible, intentando upsert directo');
        } else {
          // Si es FK constraint (23503), significa que public.users no existe aún
          if (e.code == '23503') {
            debugPrint('⚠️ [SESSION] FK error: public.users no existe para $userId. El trigger debería haberlo creado.');
          }
          throw Exception('ensureClientProfileAndAccount error: ${e.message} (${e.code})');
        }
      }

      // Fallback: crear client_profiles y accounts directamente (asume users existe)
      // 1) Upsert en client_profiles PRIMERO (para evitar FK error en accounts)
      try {
        await SupabaseConfig.client.from('client_profiles').upsert(
          {
            'user_id': userId,
            'status': 'active',
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'user_id',
        );
        debugPrint('✅ [DB] client_profiles upsert OK para cliente $userId');
      } on PostgrestException catch (e) {
        // Si falla por FK, users no existe → problema serio
        if (e.code == '23503') {
          debugPrint('❌ [DB] FK error: public.users no existe para $userId. No se puede crear client_profiles.');
          throw Exception('public.users missing for $userId');
        }
        debugPrint('⚠️ [DB] Fallback client_profiles upsert falló: ${e.message} (${e.code})');
      }

      // 2) Upsert en accounts
      try {
        await SupabaseConfig.client.from('accounts').upsert(
          {
            'user_id': userId,
            'account_type': 'client',
            'balance': 0.00,
          },
          onConflict: 'user_id',
        );
        debugPrint('✅ [DB] accounts upsert OK para cliente $userId');
      } on PostgrestException catch (e) {
        debugPrint('⚠️ [DB] Fallback accounts upsert falló: ${e.message} (${e.code})');
      }
    } catch (e) {
      debugPrint('❌ ensureClientProfileAndAccount error: $e');
      // Re-lanzar solo si es un error crítico (FK constraint = users no existe)
      if (e.toString().contains('public.users missing')) {
        rethrow;
      }
    }
  }
}

extension SupabaseDeliveryProfileExtensions on SupabaseConfig {
  /// Wrapper para actualizar/crear el perfil de repartidor usando la RPC segura
  /// Mantiene compatibilidad aunque cambie la firma en el backend.
  static Future<dynamic> updateMyDeliveryProfile(Map<String, dynamic> data) async {
    try {
      // 1) Normalizar payload y mapear a params con prefijo p_
      final payload = <String, dynamic>{
        // Identidad
        'user_id': data['user_id'] ?? data['p_user_id'],
        // Vehículo
        'vehicle_type': data['vehicle_type'] ?? data['p_vehicle_type'],
        'vehicle_plate': data['vehicle_plate'] ?? data['p_vehicle_plate'],
        if ((data['vehicle_model'] ?? data['p_vehicle_model']) != null)
          'vehicle_model': data['vehicle_model'] ?? data['p_vehicle_model'],
        if ((data['vehicle_color'] ?? data['p_vehicle_color']) != null)
          'vehicle_color': data['vehicle_color'] ?? data['p_vehicle_color'],
        // Contacto de emergencia
        if ((data['emergency_contact_name'] ?? data['p_emergency_contact_name']) != null)
          'emergency_contact_name': data['emergency_contact_name'] ?? data['p_emergency_contact_name'],
        if ((data['emergency_contact_phone'] ?? data['p_emergency_contact_phone']) != null)
          'emergency_contact_phone': data['emergency_contact_phone'] ?? data['p_emergency_contact_phone'],
        // Geocoding
        if ((data['place_id'] ?? data['p_place_id']) != null)
          'place_id': data['place_id'] ?? data['p_place_id'],
        if ((data['lat'] ?? data['p_lat']) != null)
          'lat': data['lat'] ?? data['p_lat'],
        if ((data['lon'] ?? data['p_lon']) != null)
          'lon': data['lon'] ?? data['p_lon'],
        if ((data['address_structured'] ?? data['p_address_structured']) != null)
          'address_structured': data['address_structured'] ?? data['p_address_structured'],
        // Imágenes/documentos (opcionales)
        if ((data['profile_image_url'] ?? data['p_profile_image_url']) != null)
          'profile_image_url': data['profile_image_url'] ?? data['p_profile_image_url'],
        if ((data['id_document_front_url'] ?? data['p_id_document_front_url']) != null)
          'id_document_front_url': data['id_document_front_url'] ?? data['p_id_document_front_url'],
        if ((data['id_document_back_url'] ?? data['p_id_document_back_url']) != null)
          'id_document_back_url': data['id_document_back_url'] ?? data['p_id_document_back_url'],
        if ((data['vehicle_photo_url'] ?? data['p_vehicle_photo_url']) != null)
          'vehicle_photo_url': data['vehicle_photo_url'] ?? data['p_vehicle_photo_url'],
        if ((data['vehicle_registration_url'] ?? data['p_vehicle_registration_url']) != null)
          'vehicle_registration_url': data['vehicle_registration_url'] ?? data['p_vehicle_registration_url'],
        if ((data['vehicle_insurance_url'] ?? data['p_vehicle_insurance_url']) != null)
          'vehicle_insurance_url': data['vehicle_insurance_url'] ?? data['p_vehicle_insurance_url'],
      }..removeWhere((key, value) => value == null);

      // Crear versión con prefijo p_ esperado por la mayoría de RPCs
      final pParams = <String, dynamic>{
        if (payload['user_id'] != null) 'p_user_id': payload['user_id'],
        if (payload['vehicle_type'] != null) 'p_vehicle_type': payload['vehicle_type'],
        if (payload['vehicle_plate'] != null) 'p_vehicle_plate': payload['vehicle_plate'],
        if (payload['vehicle_model'] != null) 'p_vehicle_model': payload['vehicle_model'],
        if (payload['vehicle_color'] != null) 'p_vehicle_color': payload['vehicle_color'],
        if (payload['emergency_contact_name'] != null) 'p_emergency_contact_name': payload['emergency_contact_name'],
        if (payload['emergency_contact_phone'] != null) 'p_emergency_contact_phone': payload['emergency_contact_phone'],
        if (payload['place_id'] != null) 'p_place_id': payload['place_id'],
        if (payload['lat'] != null) 'p_lat': payload['lat'],
        if (payload['lon'] != null) 'p_lon': payload['lon'],
        if (payload['address_structured'] != null) 'p_address_structured': payload['address_structured'],
        if (payload['profile_image_url'] != null) 'p_profile_image_url': payload['profile_image_url'],
        if (payload['id_document_front_url'] != null) 'p_id_document_front_url': payload['id_document_front_url'],
        if (payload['id_document_back_url'] != null) 'p_id_document_back_url': payload['id_document_back_url'],
        if (payload['vehicle_photo_url'] != null) 'p_vehicle_photo_url': payload['vehicle_photo_url'],
        if (payload['vehicle_registration_url'] != null) 'p_vehicle_registration_url': payload['vehicle_registration_url'],
        if (payload['vehicle_insurance_url'] != null) 'p_vehicle_insurance_url': payload['vehicle_insurance_url'],
      }..removeWhere((key, value) => value == null);

      debugPrint('🛠️ [RPC] delivery_profile payload keys: ${payload.keys.toList()}');
      debugPrint('🛠️ [RPC] delivery_profile pParams keys: ${pParams.keys.toList()}');

      // 2) Intento 1: nueva RPC estandarizada
      try {
        final result = await SupabaseConfig.client.rpc(RpcNames.upsertDeliveryAgentProfile, params: pParams);
        debugPrint('✅ [RPC] upsert_delivery_agent_profile OK: $result');
        return result;
      } on PostgrestException catch (e) {
        // Si la función no existe o firma distinta, probamos fallback
        if ((e.code == 'PGRST202') || e.code == '404' || e.code == '42883' || e.message.contains('Could not find the function') || e.message.contains('schema cache')) {
          debugPrint('↩️ [RPC] Fallback a update_my_delivery_profile por firma/nombre distinto');
        } else {
          rethrow;
        }
      }

      // 3) Intento 2: nombre legado
      try {
        final result = await SupabaseConfig.client.rpc(RpcNames.updateMyDeliveryProfile, params: pParams);
        debugPrint('✅ [RPC] update_my_delivery_profile OK: $result');
        return result;
      } on PostgrestException catch (e) {
        if ((e.code == 'PGRST202') || e.code == '404' || e.code == '42883' || e.message.contains('Could not find the function') || e.message.contains('schema cache')) {
          debugPrint('↩️ [RPC] Fallback a payload JSON por firma distinta');
        } else {
          rethrow;
        }
      }

      // 4) Intento 3: RPC esperando un solo parámetro JSON/JSONB
      try {
        final result = await SupabaseConfig.client.rpc(RpcNames.upsertDeliveryAgentProfile, params: { 'payload': payload });
        debugPrint('✅ [RPC] upsert_delivery_agent_profile (payload) OK: $result');
        return result;
      } on PostgrestException catch (e) {
        try {
          // último intento de RPC: nombre legado con JSON
          final result = await SupabaseConfig.client.rpc(RpcNames.updateMyDeliveryProfile, params: { 'payload': payload });
          debugPrint('✅ [RPC] update_my_delivery_profile (payload) OK: $result');
          return result;
        } on PostgrestException catch (e2) {
          // 5) Fallback final: upsert directo en la tabla (requiere RLS apropiada)
          if ((e2.code == 'PGRST202') || e2.code == '404' || e2.code == '42883' ||
              e2.message.contains('Could not find the function') || e2.message.contains('schema cache')) {
            debugPrint('↘️ [DB] RPCs no disponibles. Intentando upsert directo en delivery_agent_profiles');

            final String? userId = (payload['user_id'] ?? SupabaseConfig.auth.currentUser?.id)?.toString();
            if (userId == null || userId.isEmpty) {
              throw PostgrestException(message: 'Missing user_id for delivery profile update', code: '400', details: null, hint: null);
            }

            final directData = {
              'user_id': userId,
              if (payload['vehicle_type'] != null) 'vehicle_type': payload['vehicle_type'],
              if (payload['vehicle_plate'] != null) 'vehicle_plate': payload['vehicle_plate'],
              if (payload['vehicle_model'] != null) 'vehicle_model': payload['vehicle_model'],
              if (payload['vehicle_color'] != null) 'vehicle_color': payload['vehicle_color'],
              if (payload['emergency_contact_name'] != null) 'emergency_contact_name': payload['emergency_contact_name'],
              if (payload['emergency_contact_phone'] != null) 'emergency_contact_phone': payload['emergency_contact_phone'],
              if (payload['place_id'] != null) 'place_id': payload['place_id'],
              if (payload['lat'] != null) 'lat': payload['lat'],
              if (payload['lon'] != null) 'lon': payload['lon'],
              if (payload['address_structured'] != null) 'address_structured': payload['address_structured'],
              if (payload['profile_image_url'] != null) 'profile_image_url': payload['profile_image_url'],
              if (payload['id_document_front_url'] != null) 'id_document_front_url': payload['id_document_front_url'],
              if (payload['id_document_back_url'] != null) 'id_document_back_url': payload['id_document_back_url'],
              if (payload['vehicle_photo_url'] != null) 'vehicle_photo_url': payload['vehicle_photo_url'],
              if (payload['vehicle_registration_url'] != null) 'vehicle_registration_url': payload['vehicle_registration_url'],
              if (payload['vehicle_insurance_url'] != null) 'vehicle_insurance_url': payload['vehicle_insurance_url'],
              'updated_at': DateTime.now().toIso8601String(),
            }..removeWhere((k, v) => v == null);

            final res = await SupabaseConfig.client
                .from('delivery_agent_profiles')
                .upsert(directData, onConflict: 'user_id')
                .select()
                .maybeSingle();

            debugPrint('✅ [DB] Upsert directo OK: $res');
            return res ?? {'success': true};
          } else {
            rethrow;
          }
        }
      }
    } on PostgrestException catch (e) {
      debugPrint('❌ [RPC] update_my_delivery_profile error: ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ [RPC] update_my_delivery_profile error: $e');
      rethrow;
    }
  }
}

/// Extensiones para cuentas financieras (accounts)
extension SupabaseAccountExtensions on SupabaseConfig {
  /// Asegura que exista la cuenta financiera del usuario (idempotente)
  /// Intenta usar la RPC SECURITY DEFINER `ensure_financial_account` y
  /// si no existe cae a un upsert directo (si las políticas lo permiten).
  static Future<void> ensureFinancialAccount({
    required String userId,
    required String accountType,
  }) async {
    try {
      // 1) Intentar RPC estándar
      try {
        final res = await SupabaseConfig.client.rpc(
          RpcNames.ensureFinancialAccount,
          params: {
            'p_user_id': userId,
            'p_account_type': accountType,
          },
        );
        debugPrint('✅ [RPC] ensure_financial_account OK: $res');
        return;
      } on PostgrestException catch (e) {
        if ((e.code == 'PGRST202') || e.message.contains('Could not find the function') || e.message.contains('schema cache')) {
          debugPrint('↩️ [RPC] Fallback: ensure_financial_account no disponible, intentamos upsert directo en accounts');
        } else {
          rethrow;
        }
      }

      // 2) Fallback: upsert directo (requiere política RLS adecuada)
      try {
        await SupabaseConfig.client.from('accounts').upsert({
          'user_id': userId,
          'account_type': accountType,
          'balance': 0.00,
        }, onConflict: 'user_id');
        debugPrint('✅ [DB] accounts upsert OK para $userId');
      } on PostgrestException catch (e) {
        debugPrint('❌ [DB] accounts upsert falló: ${e.message}');
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ ensureFinancialAccount error: $e');
      rethrow;
    }
  }
}
