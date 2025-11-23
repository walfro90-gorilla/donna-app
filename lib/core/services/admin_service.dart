import 'dart:async';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// 👑 AdminService - Servicio para usuarios tipo Admin
class AdminService extends BaseService {
  
  // Stream Controllers
  final StreamController<List<dynamic>> _usersController = StreamController<List<dynamic>>.broadcast();
  final StreamController<List<DoaRestaurant>> _restaurantsController = StreamController<List<DoaRestaurant>>.broadcast();
  final StreamController<List<DoaOrder>> _ordersController = StreamController<List<DoaOrder>>.broadcast();
  final StreamController<Map<String, dynamic>> _dashboardController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Timers
  Timer? _refreshTimer;
  
  @override
  String get serviceName => 'ADMIN';
  
  @override
  String get requiredRole => 'admin';

  // Streams públicos
  Stream<List<dynamic>> get usersStream => _usersController.stream;
  Stream<List<DoaRestaurant>> get restaurantsStream => _restaurantsController.stream;
  Stream<List<DoaOrder>> get ordersStream => _ordersController.stream;
  Stream<Map<String, dynamic>> get dashboardStream => _dashboardController.stream;

  @override
  void onActivate() {
    print('👑 [ADMIN] Admin activado: ${currentSession?.email}');
    
    // Emitir evento de activación
    emit(ServiceActivatedEvent(serviceName: serviceName, role: requiredRole));
    
    // Cargar datos iniciales
    _loadInitialData();
    
    // Iniciar refresh automático
    _startAutoRefresh();
  }

  @override
  void onDeactivate() {
    print('🛑 [ADMIN] Admin desactivado');
    
    // Emitir evento de desactivación
    emit(ServiceDeactivatedEvent(serviceName: serviceName, role: requiredRole));
    
    // Limpiar timers
    _refreshTimer?.cancel();
    _refreshTimer = null;
    
    // Limpiar streams (pero no cerrarlos)
    _usersController.add([]);
    _restaurantsController.add([]);
    _ordersController.add([]);
    _dashboardController.add({});
  }

  /// 📊 Cargar datos iniciales
  void _loadInitialData() async {
    if (!hasAccess()) return;
    
    print('📊 [ADMIN] Cargando datos iniciales...');
    
    try {
      // Cargar usuarios
      await loadUsers();
      
      // Cargar restaurantes
      await loadRestaurants();
      
      // Cargar órdenes
      await loadOrders();
      
      // Cargar dashboard stats
      await loadDashboardStats();
      
    } catch (e) {
      print('❌ [ADMIN] Error cargando datos iniciales: $e');
    }
  }

  /// 👥 Cargar usuarios
  Future<void> loadUsers() async {
    if (!hasAccess()) return;
    
    try {
      print('👥 [ADMIN] Cargando usuarios...');
      
      final response = await SupabaseConfig.client
          .from('user_profiles')
          .select('*')
          .order('created_at', ascending: false);
      
      print('✅ [ADMIN] ${response.length} usuarios cargados');
      _usersController.add(response);
      
    } catch (e) {
      print('❌ [ADMIN] Error cargando usuarios: $e');
      _usersController.add([]);
    }
  }

  /// 🏪 Cargar restaurantes
  Future<void> loadRestaurants() async {
    if (!hasAccess()) return;
    
    try {
      print('🏪 [ADMIN] Cargando restaurantes...');
      
      final response = await SupabaseConfig.client
          .from('restaurants')
          .select('*')
          .order('created_at', ascending: false);
      
      final restaurants = (response as List)
          .map((json) => DoaRestaurant.fromJson(json))
          .toList();
      
      print('✅ [ADMIN] ${restaurants.length} restaurantes cargados');
      _restaurantsController.add(restaurants);
      
    } catch (e) {
      print('❌ [ADMIN] Error cargando restaurantes: $e');
      _restaurantsController.add([]);
    }
  }

  /// 📝 Cargar órdenes
  Future<void> loadOrders() async {
    if (!hasAccess()) return;
    
    try {
      print('📝 [ADMIN] Cargando órdenes...');
      
      final response = await SupabaseConfig.client
          .from('orders')
          .select('*, restaurants(*), user_profiles(*)')
          .order('created_at', ascending: false)
          .limit(100);
      
      final orders = (response as List)
          .map((json) => DoaOrder.fromJson(json))
          .toList();
      
      print('✅ [ADMIN] ${orders.length} órdenes cargadas');
      _ordersController.add(orders);
      
    } catch (e) {
      print('❌ [ADMIN] Error cargando órdenes: $e');
      _ordersController.add([]);
    }
  }

  /// 📊 Cargar estadísticas del dashboard
  Future<void> loadDashboardStats() async {
    if (!hasAccess()) return;
    
    try {
      print('📊 [ADMIN] Cargando estadísticas del dashboard...');
      
      // Estadísticas de hoy
      final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0);
      final todayEnd = DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
      
      // Usuarios totales
      final totalUsers = await SupabaseConfig.client
          .from('user_profiles')
          .select('id')
          .count();
      
      // Restaurantes activos
      final activeRestaurants = await SupabaseConfig.client
          .from('restaurants')
          .select('id')
          .eq('is_active', true)
          .count();
      
      // Órdenes de hoy
      final todayOrders = await SupabaseConfig.client
          .from('orders')
          .select('total_amount')
          .gte('created_at', todayStart.toIso8601String())
          .lte('created_at', todayEnd.toIso8601String());
      
      // Órdenes pendientes
      final pendingOrders = await SupabaseConfig.client
          .from('orders')
          .select('*')
          .inFilter('status', ['pending', 'confirmed', 'preparing', 'ready', 'in_delivery']);
      
      // Calcular estadísticas
      final stats = {
        'total_users': totalUsers.count,
        'active_restaurants': activeRestaurants.count,
        'today_orders': todayOrders.length,
        'today_revenue': todayOrders.fold<double>(0, (sum, order) => sum + (order['total_amount'] ?? 0)),
        'pending_orders': pendingOrders.length,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      print('✅ [ADMIN] Dashboard stats cargadas: ${stats['today_orders']} órdenes hoy');
      _dashboardController.add(stats);
      
    } catch (e) {
      print('❌ [ADMIN] Error cargando dashboard stats: $e');
      _dashboardController.add({});
    }
  }

  /// 🔧 Actualizar estado de usuario
  Future<bool> updateUserStatus(String userId, bool isActive) async {
    if (!hasAccess()) return false;
    
    try {
      print('🔧 [ADMIN] Actualizando estado de usuario: $userId -> ${isActive ? 'activo' : 'inactivo'}');
      
      await SupabaseConfig.client
          .from('user_profiles')
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      
      print('✅ [ADMIN] Estado de usuario actualizado');
      
      // Recargar usuarios
      await loadUsers();
      
      return true;
      
    } catch (e) {
      print('❌ [ADMIN] Error actualizando estado de usuario: $e');
      return false;
    }
  }

  /// 🏪 Aprobar/Rechazar restaurante
  Future<bool> updateRestaurantStatus(String restaurantId, bool isActive) async {
    if (!hasAccess()) return false;
    
    try {
      print('🏪 [ADMIN] Actualizando estado de restaurante: $restaurantId -> ${isActive ? 'activo' : 'inactivo'}');
      
      await SupabaseConfig.client
          .from('restaurants')
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', restaurantId);
      
      print('✅ [ADMIN] Estado de restaurante actualizado');
      
      // Recargar restaurantes
      await loadRestaurants();
      
      return true;
      
    } catch (e) {
      print('❌ [ADMIN] Error actualizando estado de restaurante: $e');
      return false;
    }
  }

  /// 📝 Cancelar orden (admin)
  Future<bool> cancelOrder(String orderId, String reason) async {
    if (!hasAccess()) return false;
    
    try {
      print('📝 [ADMIN] Cancelando orden: $orderId');
      
      await SupabaseConfig.client
          .from('orders')
          .update({
            'status': 'cancelled',
            'cancellation_reason': reason,
            'cancelled_by': 'admin',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', orderId);
      
      print('✅ [ADMIN] Orden cancelada exitosamente');
      
      // Recargar órdenes y stats
      await loadOrders();
      await loadDashboardStats();
      
      return true;
      
    } catch (e) {
      print('❌ [ADMIN] Error cancelando orden: $e');
      return false;
    }
  }

  /// 🔄 Auto-refresh de datos
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!hasAccess()) {
        timer.cancel();
        return;
      }
      
      print('🔄 [ADMIN] Auto-refresh ejecutándose...');
      loadDashboardStats();
      loadOrders();
    });
  }

  /// 🧹 Limpiar recursos
  @override
  void dispose() {
    super.dispose();
    _refreshTimer?.cancel();
    _usersController.close();
    _restaurantsController.close();
    _ordersController.close();
    _dashboardController.close();
  }
}