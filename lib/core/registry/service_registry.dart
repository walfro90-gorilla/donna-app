import 'dart:async';
import 'package:doa_repartos/core/session/user_session.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/core/services/client_service.dart';
import 'package:doa_repartos/core/services/delivery_service.dart';
import 'package:doa_repartos/core/services/restaurant_service_simple.dart';
import 'package:doa_repartos/core/services/admin_service.dart';
import 'package:doa_repartos/core/services/financial_service.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Registry profesional de servicios con cleanup automático y auto-registro
class ServiceRegistry {
  static ServiceRegistry? _instance;
  static ServiceRegistry get instance => _instance ??= ServiceRegistry._();
  
  ServiceRegistry._() {
    _registerDefaultServices();
  }

  final Map<String, Map<Type, dynamic>> _userServices = {};
  final Map<Type, ServiceFactory> _factories = {};
  final EventBus _eventBus = EventBus.instance;

  /// Auto-registro de servicios por defecto
  void _registerDefaultServices() {
    print('🚀 [REGISTRY] Auto-registrando servicios por defecto...');
    
    // Registrar factory para ClientService
    registerFactory<ClientService>(ClientServiceFactory());
    
    // Registrar factory para RestaurantService 
    registerFactory<RestaurantService>(RestaurantServiceFactory());
    
    // Registrar factory para DeliveryService
    registerFactory<DeliveryService>(DeliveryServiceFactory());
    
    // Registrar factory para AdminService
    registerFactory<AdminService>(AdminServiceFactory());
    
    // Registrar factory para FinancialService
    registerFactory<FinancialService>(FinancialServiceFactory());
    
    print('✅ [REGISTRY] ${_factories.length} servicios registrados');
  }

  /// Registra una factory para un tipo de servicio
  void registerFactory<T>(ServiceFactory<T> factory) {
    print('🏭 [REGISTRY] Registering factory for: ${T.toString()}');
    _factories[T] = factory;
  }

  /// Obtiene un servicio para un usuario específico
  T getService<T>({required String userId, required UserRole role}) {
    print('🎯 [REGISTRY] Getting service ${T.toString()} for user: $userId ($role)');
    
    final userServices = _userServices.putIfAbsent(userId, () => {});
    
    if (userServices.containsKey(T)) {
      print('♻️ [REGISTRY] Service ${T.toString()} found in cache');
      return userServices[T] as T;
    }

    // Crear nuevo servicio
    final factory = _factories[T] as ServiceFactory<T>?;
    if (factory == null) {
      throw Exception('No factory registered for service: ${T.toString()}');
    }

    print('🆕 [REGISTRY] Creating new service ${T.toString()}');
    final service = factory.create(userId: userId, role: role);
    userServices[T] = service;
    
    return service;
  }

  /// Verifica si un servicio existe para un usuario
  bool hasService<T>(String userId) {
    return _userServices[userId]?.containsKey(T) ?? false;
  }

  /// Limpia todos los servicios de un usuario
  Future<void> clearUserServices(String userId) async {
    print('🧹 [REGISTRY] Clearing all services for user: $userId');
    final userServices = _userServices[userId];
    
    if (userServices == null) {
      print('ℹ️ [REGISTRY] No services found for user: $userId');
      return;
    }

    // Cleanup de cada servicio
    for (final entry in userServices.entries) {
      final service = entry.value;
      print('🗑️ [REGISTRY] Cleaning up service: ${entry.key.toString()}');
      
      if (service is DisposableService) {
        try {
          await service.dispose();
          print('✅ [REGISTRY] Service ${entry.key.toString()} disposed successfully');
        } catch (e) {
          print('❌ [REGISTRY] Error disposing service ${entry.key.toString()}: $e');
        }
      }
    }

    _userServices.remove(userId);
    print('✅ [REGISTRY] All services cleared for user: $userId');
  }

  /// Limpia todos los servicios de todos los usuarios
  Future<void> clearAll() async {
    print('🧹 [REGISTRY] Clearing ALL services');
    final userIds = _userServices.keys.toList();
    
    for (final userId in userIds) {
      await clearUserServices(userId);
    }
    
    _userServices.clear();
    print('✅ [REGISTRY] Registry completely cleared');
  }

  /// Obtiene estadísticas del registry
  Map<String, dynamic> getStats() {
    final stats = <String, dynamic>{
      'totalUsers': _userServices.length,
      'totalFactories': _factories.length,
      'userServices': <String, dynamic>{},
    };

    for (final entry in _userServices.entries) {
      stats['userServices'][entry.key] = entry.value.keys.map((t) => t.toString()).toList();
    }

    return stats;
  }
}

/// Factory base para crear servicios
abstract class ServiceFactory<T> {
  T create({required String userId, required UserRole role});
}

/// Interface para servicios que necesitan cleanup
abstract class DisposableService {
  Future<void> dispose();
}

/// Interface para servicios con tiempo real
abstract class RealtimeService {
  Stream get dataStream;
  Future<void> startListening();
  Future<void> stopListening();
}

/// Servicio base con funcionalidades comunes
abstract class BaseService implements DisposableService {
  final String userId;
  final UserRole role;
  final EventBus eventBus;
  
  BaseService({
    required this.userId,
    required this.role,
  }) : eventBus = EventBus.instance;
  
  @override
  Future<void> dispose() async {
    print('🗑️ [SERVICE] Disposing ${runtimeType.toString()} for user: $userId');
  }
  
  /// Publica un evento de error
  void publishError(String error, String context, [dynamic details]) {
    eventBus.publish(ErrorEvent(
      error: error,
      context: context,
      details: details,
      timestamp: DateTime.now(),
      userId: userId,
    ));
  }
  
  /// Publica actualización de datos
  void publishDataUpdate(String dataType, Map<String, dynamic> data) {
    eventBus.publish(DataUpdatedEvent(
      dataType: dataType,
      data: data,
      timestamp: DateTime.now(),
      userId: userId,
    ));
  }
}

/// 🛍️ Factory para ClientService
class ClientServiceFactory extends ServiceFactory<ClientService> {
  @override
  ClientService create({required String userId, required UserRole role}) {
    print('🛍️ [FACTORY] Creando ClientService para usuario: $userId');
    return ClientService();
  }
}

/// 🚚 Factory para DeliveryService
class DeliveryServiceFactory extends ServiceFactory<DeliveryService> {
  @override
  DeliveryService create({required String userId, required UserRole role}) {
    print('🚚 [FACTORY] Creando DeliveryService para usuario: $userId');
    return DeliveryService();
  }
}

/// 🏪 Factory para RestaurantService
class RestaurantServiceFactory extends ServiceFactory<RestaurantService> {
  @override
  RestaurantService create({required String userId, required UserRole role}) {
    print('🏪 [FACTORY] Creando RestaurantService para usuario: $userId');
    return RestaurantService();
  }
}

/// 👑 Factory para AdminService
class AdminServiceFactory extends ServiceFactory<AdminService> {
  @override
  AdminService create({required String userId, required UserRole role}) {
    print('👑 [FACTORY] Creando AdminService para usuario: $userId');
    return AdminService();
  }
}

/// 💰 Factory para FinancialService
class FinancialServiceFactory extends ServiceFactory<FinancialService> {
  @override
  FinancialService create({required String userId, required UserRole role}) {
    print('💰 [FACTORY] Creando FinancialService para usuario: $userId');
    return FinancialService();
  }
}