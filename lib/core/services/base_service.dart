import 'package:doa_repartos/core/session/session_manager.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/session/user_session.dart';

/// 🎯 BaseService - Clase base para todos los servicios por rol
abstract class BaseService {
  final SessionManager _sessionManager;
  final EventBus _eventBus;
  
  bool _isActive = false;
  UserSession? _currentSession;

  BaseService() : 
    _sessionManager = SessionManager.instance,
    _eventBus = EventBus.instance {
    _init();
  }

  /// 🔥 Inicialización del servicio
  void _init() {
    print('🎯 [${serviceName.toUpperCase()}] Inicializando servicio...');
    
    // Escuchar cambios de sesión
    _eventBus.on<SessionChangedEvent>().listen(_onSessionChanged);
    
    // Verificar sesión actual
    _currentSession = _sessionManager.currentSession;
    if (_currentSession != null && _currentSession!.role == requiredRole) {
      _activate();
    }
  }

  /// 📋 Nombre del servicio (para logs)
  String get serviceName;
  
  /// 👤 Rol requerido para este servicio
  String get requiredRole;
  
  /// ✅ Estado del servicio
  bool get isActive => _isActive;
  
  /// 👤 Sesión actual
  UserSession? get currentSession => _currentSession;

  /// 🎯 Activar servicio
  void _activate() {
    if (_isActive) return;
    
    print('🚀 [${serviceName.toUpperCase()}] Activando servicio para ${_currentSession?.email}');
    _isActive = true;
    onActivate();
  }

  /// 🛑 Desactivar servicio
  void _deactivate() {
    if (!_isActive) return;
    
    print('🛑 [${serviceName.toUpperCase()}] Desactivando servicio...');
    _isActive = false;
    onDeactivate();
  }

  /// 📡 Manejar cambios de sesión
  void _onSessionChanged(SessionChangedEvent event) {
    print('📡 [${serviceName.toUpperCase()}] Cambio de sesión detectado: ${event.newSession?.role ?? 'null'}');
    
    _currentSession = event.newSession;
    
    if (_currentSession?.role == requiredRole) {
      _activate();
    } else {
      _deactivate();
    }
  }

  /// 🎯 Implementar en servicios específicos - Activación
  void onActivate();
  
  /// 🛑 Implementar en servicios específicos - Desactivación  
  void onDeactivate();
  
  /// 🧹 Limpiar recursos
  void dispose() {
    print('🧹 [${serviceName.toUpperCase()}] Limpiando recursos...');
    _deactivate();
  }

  /// 🔒 Verificar si el usuario tiene acceso
  bool hasAccess() {
    return _isActive && _currentSession?.role == requiredRole;
  }

  /// 📤 Emitir evento
  void emit<T extends AppEvent>(T event) {
    _eventBus.emit<T>(event);
  }

  /// 📥 Escuchar eventos
  Stream<T> on<T extends AppEvent>() {
    return _eventBus.on<T>();
  }
}

/// 📡 Eventos del sistema
class ServiceActivatedEvent extends AppEvent {
  final String serviceName;
  final String role;
  
  ServiceActivatedEvent({
    required this.serviceName, 
    required this.role,
  }) : super(timestamp: DateTime.now());
}

class ServiceDeactivatedEvent extends AppEvent {
  final String serviceName;
  final String role;
  
  ServiceDeactivatedEvent({
    required this.serviceName, 
    required this.role,
  }) : super(timestamp: DateTime.now());
}