import 'dart:async';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
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

  // ==========================================================================
  // 💰 Modelo de cobro dual (commission vs subscription)
  // ==========================================================================

  /// Lee la configuración actual del modo de cobro global.
  Future<BillingModeConfig> getBillingMode() async {
    final res = await SupabaseConfig.client.rpc(RpcNames.getBillingMode);
    return BillingModeConfig.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// Cambia el modo global. Solo admin.
  Future<void> setBillingMode(String mode) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminSetBillingMode,
      params: {'p_mode': mode},
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'Failed to set billing mode');
    }
  }

  /// Crea suscripciones para todas las cuentas que aún no tienen.
  /// Llamar una vez al activar modo subscription por primera vez.
  Future<int> bootstrapSubscriptions() async {
    final res = await SupabaseConfig.client.rpc(RpcNames.adminBootstrapSubscriptions);
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'Bootstrap failed');
    }
    return (map['created'] as num?)?.toInt() ?? 0;
  }

  /// Lista paginada de suscripciones con filtros.
  Future<List<DoaSubscription>> listSubscriptions({
    String? role,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminListSubscriptions,
      params: {
        'p_role': role,
        'p_status': status,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'List failed');
    }
    final rows = (map['subscriptions'] as List?) ?? const [];
    return rows
        .map((e) => DoaSubscription.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Lista invoices de una suscripción, más reciente primero.
  Future<List<DoaSubscriptionInvoice>> listInvoicesForSubscription(String subscriptionId) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminListInvoicesForSubscription,
      params: {'p_subscription_id': subscriptionId},
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'List invoices failed');
    }
    final rows = (map['invoices'] as List?) ?? const [];
    return rows
        .map((e) => DoaSubscriptionInvoice.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Marca una invoice como pagada (SPEI manual u origen externo).
  Future<void> markInvoicePaid({
    required String invoiceId,
    String method = 'spei',
    String? reference,
    String? notes,
  }) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminMarkInvoicePaid,
      params: {
        'p_invoice_id': invoiceId,
        'p_method': method,
        'p_reference': reference,
        'p_notes': notes,
      },
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'Mark paid failed');
    }
  }

  /// Perdona la invoice (no toca ledger, reactiva la suscripción si aplica).
  Future<void> waiveInvoice({required String invoiceId, String? notes}) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminWaiveInvoice,
      params: {'p_invoice_id': invoiceId, 'p_notes': notes},
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'Waive failed');
    }
  }

  /// Extiende el due_date de la invoice activa de una suscripción.
  Future<void> extendGrace({
    required String subscriptionId,
    required int extraDays,
    String? notes,
  }) async {
    final res = await SupabaseConfig.client.rpc(
      RpcNames.adminExtendGrace,
      params: {
        'p_subscription_id': subscriptionId,
        'p_extra_days': extraDays,
        'p_notes': notes,
      },
    );
    final map = Map<String, dynamic>.from(res as Map);
    if (map['success'] != true) {
      throw Exception(map['error'] ?? 'Extend grace failed');
    }
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