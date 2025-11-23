import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/core/session/user_session.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/registry/service_registry.dart';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/alert_sound_service.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/polling_service.dart';

/// Session Manager Centralizado - Controlador único de todas las sesiones
class SessionManager {
  static SessionManager? _instance;
  static SessionManager get instance => _instance ??= SessionManager._();
  SessionManager._();

  // Core dependencies
  final SupabaseClient _supabase = Supabase.instance.client;
  final EventBus _eventBus = EventBus.instance;
  final ServiceRegistry _serviceRegistry = ServiceRegistry.instance;

  // Session state
  UserSession _currentSession = UserSession.empty();
  SessionState _state = SessionState.idle;
  StreamSubscription<AuthState>? _authSubscription;
  
  // Prevent infinite loops during session switching
  bool _isProcessingSessionChange = false;

  // Stream controllers
  final StreamController<UserSession> _sessionController = StreamController.broadcast();
  final StreamController<SessionState> _stateController = StreamController.broadcast();

  // Getters
  UserSession get currentSession => _currentSession;
  SessionState get state => _state;
  bool get hasActiveSession => _currentSession.isValid;
  Stream<UserSession> get sessionStream => _sessionController.stream;
  Stream<SessionState> get stateStream => _stateController.stream;

  /// Inicializa el Session Manager
  Future<void> initialize() async {
    print('🚀 [SESSION] ===== INITIALIZING SESSION MANAGER =====');
    
    try {
      _setState(SessionState.initializing);
      
      // Escuchar cambios de autenticación
      _authSubscription = _supabase.auth.onAuthStateChange.listen(_onAuthStateChanged);
      
      // Verificar sesión actual
      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null) {
        print('🔄 [SESSION] Found existing auth session');
        await _loadUserSession(currentUser);
      } else {
        print('ℹ️ [SESSION] No existing auth session');
        _setState(SessionState.idle);
      }
      
      print('✅ [SESSION] Session Manager initialized successfully');
    } catch (e) {
      print('❌ [SESSION] Error initializing Session Manager: $e');
      _setState(SessionState.error);
    }
  }

  /// Maneja cambios en el estado de autenticación
  void _onAuthStateChanged(AuthState authState) async {
    print('🔐 [SESSION] Auth state changed: ${authState.event}');
    
    // Prevent processing if already handling a session change
    if (_isProcessingSessionChange) {
      print('⚠️ [SESSION] Ignoring auth change - already processing session change');
      return;
    }
    
    switch (authState.event) {
      case AuthChangeEvent.signedIn:
        if (authState.session?.user != null) {
          await _loadUserSession(authState.session!.user);
        }
        break;
        
      case AuthChangeEvent.signedOut:
        await _endSession('User signed out');
        break;
        
      case AuthChangeEvent.userUpdated:
        if (authState.session?.user != null && hasActiveSession) {
          await _updateUserSession(authState.session!.user);
        }
        break;
        
      default:
        print('ℹ️ [SESSION] Unhandled auth event: ${authState.event}');
    }
  }

  /// Carga una sesión de usuario completa
  Future<void> _loadUserSession(User user) async {
    print('🔄 [SESSION] Loading user session: ${user.email}');
    
    // Prevent infinite loops
    if (_isProcessingSessionChange) {
      print('⚠️ [SESSION] Already processing session change - ignoring load request');
      return;
    }
    
    try {
      _isProcessingSessionChange = true;
      _setState(SessionState.initializing);
      
      // Si hay una sesión activa diferente, cambiar directamente
      if (hasActiveSession && _currentSession.userId != user.id) {
        print('🔄 [SESSION] Different user detected - switching session directly');
        
        final oldSession = _currentSession;
        
        // Limpiar servicios del usuario anterior
        if (oldSession.isValid) {
          await _serviceRegistry.clearUserServices(oldSession.userId);
        }
        
        // Continuar con la carga de la nueva sesión
        print('✅ [SESSION] Previous session cleaned - loading new user');
      }
      
      // Obtener datos del usuario (tolerante a ausencia inicial)
      Map<String, dynamic>? userData = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // Si el perfil no existe (caso raro: OAuth o fallo en trigger), crearlo con RPC
      if (userData == null) {
        print('⚠️ [SESSION] No user profile found in public.users for ${user.email}. Creating via RPC...');
        try {
          // Llamar al RPC único ensure_user_profile_public con todos los parámetros necesarios
          await _supabase.rpc('ensure_user_profile_public', params: {
            'p_user_id': user.id,
            'p_email': user.email ?? '',
            'p_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? user.email?.split('@')[0] ?? '',
            'p_role': 'cliente', // Default role for OAuth users
            'p_phone': user.userMetadata?['phone'],
            'p_address': user.userMetadata?['address'],
            'p_lat': user.userMetadata?['lat'] != null ? double.tryParse(user.userMetadata!['lat'].toString()) : null,
            'p_lon': user.userMetadata?['lon'] != null ? double.tryParse(user.userMetadata!['lon'].toString()) : null,
            'p_address_structured': user.userMetadata?['address_structured'],
          });
          print('✅ [SESSION] User profile created via ensure_user_profile_public()');

          // Reintentar obtener el perfil
          userData = await _supabase
              .from('users')
              .select()
              .eq('id', user.id)
              .maybeSingle();
        } catch (e) {
          print('⚠️ [SESSION] Could not create user profile via RPC: $e');
        }
      }

      // Si aún no existe, crear un objeto mínimo en memoria para no romper la UI
      userData ??= {
        'id': user.id,
        'email': user.email ?? '',
        'role': 'cliente',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };
      // Normalize role using tolerant parser (supports 'restaurant'/'restaurante', etc.)
      final role = UserRole.fromString((userData['role'] ?? 'cliente').toString());
      
      print('👤 [SESSION] User role: ${role.name}');
      
      // Cargar datos específicos del rol
      DoaRestaurant? restaurant;
      DoaUser? deliveryAgent;
      DoaUser? clientData;
      
      switch (role) {
        case UserRole.restaurant:
          restaurant = await _loadRestaurantData(user.id);
          break;
        case UserRole.delivery_agent:
          deliveryAgent = await _loadDeliveryAgentData(user.id);
          break;
        case UserRole.client:
          clientData = DoaUser.fromJson(userData);
          // Asegurar perfil y cuenta financiera del cliente (RPC SECURITY DEFINER)
          try {
            // Importa extensión y usa nombre de extensión para método estático
            await SupabaseClientProfileExtensions.ensureClientProfileAndAccount(userId: user.id);
          } catch (e) {
            print('⚠️ [SESSION] No se pudo asegurar client_profiles+account: $e');
          }
          // Asegurar también user_preferences para clientes nuevos (idempotente y no-bloqueante)
          try {
            await SupabaseConfig.client
                .from('user_preferences')
                .upsert({
                  'user_id': user.id,
                  // No marcamos onboarding como visto; solo inicializar el registro
                  'has_seen_onboarding': false,
                  'updated_at': DateTime.now().toIso8601String(),
                }, onConflict: 'user_id');
            print('✅ [SESSION] user_preferences inicializado/upsert para ${user.id}');
          } catch (e) {
            print('⚠️ [SESSION] No se pudo inicializar user_preferences (no-fatal): $e');
          }
          break;
        case UserRole.admin:
          // Admin no necesita datos específicos adicionales
          break;
      }

      // Fallback: asegurar cuenta financiera si falta (solo para roles con cuenta)
      try {
        await _ensureFinancialAccountIfMissing(user.id, role);
      } catch (e) {
        print('⚠️ [SESSION] No se pudo asegurar cuenta financiera: $e');
      }
      
      // Crear sesión
      final session = UserSession(
        userId: user.id,
        email: user.email ?? '',
        role: role,
        loginTime: DateTime.now(),
        userData: userData,
        restaurant: restaurant,
        deliveryAgent: deliveryAgent,
        clientData: clientData,
      );
      
      await _startSession(session);
      
    } catch (e) {
      print('❌ [SESSION] Error loading user session: $e');
      _setState(SessionState.error);
      _eventBus.publish(ErrorEvent(
        error: 'Failed to load user session',
        context: 'SessionManager._loadUserSession',
        details: e,
        timestamp: DateTime.now(),
      ));
    } finally {
      _isProcessingSessionChange = false;
    }
  }

  /// Inicia una nueva sesión
  Future<void> _startSession(UserSession session) async {
    print('🔥*-*-*-*-*-*-*-*-START SESSION*-*-*-*-*-*-*-*🔥');
    print('🎉 [SESSION] Starting session for: ${session.email} (${session.role.name})');
    print('📧 [SESSION] User ID: ${session.userId}');
    
    final oldSession = _currentSession;
    _currentSession = session;
    _setState(SessionState.active);
    
    // Emitir evento de sesión iniciada
    _sessionController.add(session);
    _eventBus.publish(SessionStartedEvent(
      session: session,
      timestamp: DateTime.now(),
    ));
    
    // Emitir evento de cambio de sesión para activar servicios
    _eventBus.publish(SessionChangedEvent(
      newSession: session,
      previousSession: oldSession.isValid ? oldSession : null,
    ));
    
    print('✅ [SESSION] Session started successfully');

    // Actualizar el rol del servicio de alertas de sonido
    AlertSoundService.instance.setCurrentRole(session.role);
    // Hacer warmup del audio (especialmente en web) para evitar bloqueos por política de autoplay
    // No afecta a móvil; es silencioso
    unawaited(AlertSoundService.instance.warmup());

    // Iniciar PollingService como respaldo global para el usuario actual
    try {
      unawaited(PollingService().initialize(session.userId, session.role));
      print('✅ [SESSION] PollingService iniciado como respaldo para ${session.userId}');
    } catch (e) {
      print('⚠️ [SESSION] No se pudo iniciar PollingService: $e');
    }

    print('🔥*-*-*-*-*-*-*-*-END SESSION*-*-*-*-*-*-*-*🔥');
  }


  /// Actualiza los datos de la sesión actual
  Future<void> _updateUserSession(User user) async {
    print('🔄 [SESSION] Updating user session');
    
    if (!hasActiveSession) return;
    
      try {
        // Recargar datos del usuario (tolerante)
        Map<String, dynamic>? userData = await _supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        // Si no existe por alguna razón, no fallemos: mantener userData previo
        userData ??= _currentSession.userData ?? {
          'id': user.id,
          'email': user.email ?? '',
          'role': 'cliente',
          'updated_at': DateTime.now().toIso8601String(),
        };
      
      _currentSession = _currentSession.copyWith(
        email: user.email,
        userData: userData,
      );
      
      _sessionController.add(_currentSession);
      
      print('✅ [SESSION] Session updated successfully');
    } catch (e) {
      print('❌ [SESSION] Error updating session: $e');
    }
  }

  /// Termina la sesión actual
  Future<void> _endSession(String reason) async {
    print('🛑 [SESSION] Ending session: $reason');
    
    _setState(SessionState.terminating);
    
    final oldSession = _currentSession;
    
    // Emitir evento de cambio de sesión para desactivar servicios
    _eventBus.publish(SessionChangedEvent(
      newSession: null,
      previousSession: oldSession.isValid ? oldSession : null,
    ));
    
    // Limpiar servicios
    if (oldSession.isValid) {
      await _serviceRegistry.clearUserServices(oldSession.userId);
    }
    
    // Limpiar eventos
    _eventBus.clear();
    
    // Resetear sesión
    _currentSession = UserSession.empty();
    _setState(SessionState.idle);
    
    // Emitir eventos
    _sessionController.add(_currentSession);
    _eventBus.publish(SessionEndedEvent(
      reason: reason,
      timestamp: DateTime.now(),
      userId: oldSession.userId,
    ));
    
    // Limpiar rol del servicio de alertas
    AlertSoundService.instance.setCurrentRole(null);

    // Detener PollingService de forma segura
    try {
      PollingService().stop();
      print('✅ [SESSION] PollingService detenido');
    } catch (e) {
      print('⚠️ [SESSION] Error deteniendo PollingService: $e');
    }

    print('✅ [SESSION] Session ended successfully');
  }

  /// Carga datos del restaurante
  Future<DoaRestaurant?> _loadRestaurantData(String userId) async {
    try {
      final response = await _supabase
          .from('restaurants')
          .select()
          .eq('user_id', userId)
          .single();
      
      return DoaRestaurant.fromJson(response);
    } catch (e) {
      print('⚠️ [SESSION] No restaurant data found for user: $userId');
      return null;
    }
  }

  /// Carga datos del repartidor
  Future<DoaUser?> _loadDeliveryAgentData(String userId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .eq('role', 'repartidor')
          .single();
      
      return DoaUser.fromJson(response);
    } catch (e) {
      print('⚠️ [SESSION] No delivery agent data found for user: $userId');
      return null;
    }
  }

  /// Actualiza el estado y emite evento
  void _setState(SessionState newState) {
    if (_state == newState) return;
    
    print('🔄 [SESSION] State: ${_state.name} → ${newState.name}');
    _state = newState;
    _stateController.add(newState);
  }

  /// Cierra sesión manualmente
  Future<void> signOut() async {
    print('👋 [SESSION] Manual sign out requested');
    
    try {
      await _supabase.auth.signOut();
      // _endSession será llamado automáticamente por el listener
    } catch (e) {
      print('❌ [SESSION] Error signing out: $e');
      await _endSession('Sign out error');
    }
  }

  /// Limpia el Session Manager
  Future<void> dispose() async {
    print('🗑️ [SESSION] Disposing Session Manager');
    
    await _authSubscription?.cancel();
    await _serviceRegistry.clearAll();
    _eventBus.clear();
    
    await _sessionController.close();
    await _stateController.close();
    
    _instance = null;
    print('✅ [SESSION] Session Manager disposed');
  }

  /// Asegura que exista una cuenta financiera para el usuario dado su rol
  Future<void> _ensureFinancialAccountIfMissing(String userId, UserRole role) async {
    // Solo aplica a restaurante y repartidor
    final String? accountType = switch (role) {
      UserRole.restaurant => 'restaurant',
      UserRole.delivery_agent => 'delivery_agent',
      _ => null,
    };

    if (accountType == null) {
      return;
    }

    try {
      print('🔎 [SESSION] Verificando cuenta financiera para $userId (type=$accountType)');
      final existing = await _supabase
          .from('accounts')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        print('ℹ️ [SESSION] Cuenta financiera ya existe para $userId');
        return;
      }

      await _supabase.from('accounts').insert({
        'user_id': userId,
        'account_type': accountType,
        'balance': 0.00,
      });
      print('✅ [SESSION] Cuenta financiera creada para $userId (type=$accountType)');
    } on PostgrestException catch (e) {
      // 23505 unique_violation (accounts.user_id unique): otro proceso pudo crearla en paralelo
      if (e.code == '23505') {
        print('ℹ️ [SESSION] Cuenta ya creada concurrentemente para $userId');
        return;
      }
      print('⚠️ [SESSION] PostgREST al crear cuenta: code=${e.code}, message=${e.message}, hint=${e.hint}');
    } catch (e) {
      print('⚠️ [SESSION] Error creando cuenta financiera: $e');
    }
  }
}