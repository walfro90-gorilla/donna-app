import 'dart:async';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// 🏪 RestaurantService - Servicio para usuarios tipo Restaurante  
class RestaurantService extends BaseService {
  
  final StreamController<DoaRestaurant?> _restaurantController = StreamController<DoaRestaurant?>.broadcast();
  final StreamController<List<DoaOrder>> _ordersController = StreamController<List<DoaOrder>>.broadcast();
  final StreamController<Map<String, dynamic>> _statsController = StreamController<Map<String, dynamic>>.broadcast();
  
  Timer? _refreshTimer;
  DoaRestaurant? _cachedRestaurant;
  
  @override
  String get serviceName => 'RESTAURANT';
  
  @override
  String get requiredRole => 'restaurante';

  Stream<DoaRestaurant?> get restaurantStream => _restaurantController.stream;
  Stream<List<DoaOrder>> get ordersStream => _ordersController.stream;
  Stream<Map<String, dynamic>> get statsStream => _statsController.stream;
  
  DoaRestaurant? get restaurant => _cachedRestaurant;

  @override
  void onActivate() {
    print('🏪 [RESTAURANT] Restaurante activado: ${currentSession?.email}');
    emit(ServiceActivatedEvent(serviceName: serviceName, role: requiredRole));
    _loadInitialData();
    _startAutoRefresh();
  }

  @override
  void onDeactivate() {
    print('🛑 [RESTAURANT] Restaurante desactivado');
    emit(ServiceDeactivatedEvent(serviceName: serviceName, role: requiredRole));
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _cachedRestaurant = null;
    _restaurantController.add(null);
    _ordersController.add([]);
    _statsController.add({});
  }

  void _loadInitialData() async {
    if (!hasAccess()) return;
    print('📊 [RESTAURANT] Cargando datos iniciales...');
    
    try {
      await loadRestaurantData();
      if (_cachedRestaurant != null) {
        await loadOrders();
        await loadStats();
      }
    } catch (e) {
      print('❌ [RESTAURANT] Error cargando datos iniciales: $e');
    }
  }

  Future<void> loadRestaurantData() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      print('🏪 [RESTAURANT] Cargando datos del restaurante...');
      
      final response = await SupabaseConfig.client
          .from('restaurants')
          .select('*')
          .eq('owner_id', currentSession!.userId!)
          .maybeSingle();
      
      if (response != null) {
        _cachedRestaurant = DoaRestaurant.fromJson(response);
        print('✅ [RESTAURANT] Restaurante cargado: ${_cachedRestaurant?.name}');
        _restaurantController.add(_cachedRestaurant);
      } else {
        print('❌ [RESTAURANT] No se encontró restaurante para el usuario');
        _cachedRestaurant = null;
        _restaurantController.add(null);
      }
    } catch (e) {
      print('❌ [RESTAURANT] Error cargando restaurante: $e');
      _cachedRestaurant = null;
      _restaurantController.add(null);
    }
  }

  Future<void> loadOrders() async {
    if (!hasAccess() || _cachedRestaurant == null) return;
    
    try {
      print('📝 [RESTAURANT] Cargando órdenes...');
      
      final response = await SupabaseConfig.client
          .from('orders')
          .select('*')
          .eq('restaurant_id', _cachedRestaurant!.id!)
          .order('created_at', ascending: false)
          .limit(50);
      
      final orders = (response as List)
          .map((json) => DoaOrder.fromJson(json))
          .toList();
      
      print('✅ [RESTAURANT] ${orders.length} órdenes cargadas');
      _ordersController.add(orders);
    } catch (e) {
      print('❌ [RESTAURANT] Error cargando órdenes: $e');
      _ordersController.add([]);
    }
  }

  Future<void> loadStats() async {
    if (!hasAccess() || _cachedRestaurant == null) return;
    
    try {
      print('📊 [RESTAURANT] Cargando estadísticas...');
      
      final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0);
      final todayEnd = DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
      
      final todayOrders = await SupabaseConfig.client
          .from('orders')
          .select('total_amount')
          .eq('restaurant_id', _cachedRestaurant!.id!)
          .gte('created_at', todayStart.toIso8601String())
          .lte('created_at', todayEnd.toIso8601String());
      
      final pendingOrders = await SupabaseConfig.client
          .from('orders')
          .select('*')
          .eq('restaurant_id', _cachedRestaurant!.id!)
          .inFilter('status', ['pending', 'confirmed', 'preparing']);
      
      final stats = {
        'today_orders': todayOrders.length,
        'today_revenue': todayOrders.fold<double>(0, (sum, order) => sum + (order['total_amount'] ?? 0)),
        'pending_orders': pendingOrders.length,
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      print('✅ [RESTAURANT] Estadísticas cargadas: ${stats['today_orders']} órdenes hoy');
      _statsController.add(stats);
    } catch (e) {
      print('❌ [RESTAURANT] Error cargando estadísticas: $e');
      _statsController.add({});
    }
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!hasAccess()) {
        timer.cancel();
        return;
      }
      print('🔄 [RESTAURANT] Auto-refresh ejecutándose...');
      loadOrders();
      loadStats();
    });
  }

  @override
  void dispose() {
    super.dispose();
    _refreshTimer?.cancel();
    _restaurantController.close();
    _ordersController.close();
    _statsController.close();
  }
}