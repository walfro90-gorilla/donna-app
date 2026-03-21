import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';

/// 🛍️ ClientService - Servicio para usuarios tipo Cliente
class ClientService extends BaseService {
  
  // Stream Controllers
  final StreamController<List<DoaRestaurant>> _restaurantsController = StreamController<List<DoaRestaurant>>.broadcast();
  final StreamController<List<DoaOrder>> _ordersController = StreamController<List<DoaOrder>>.broadcast();
  final StreamController<DoaOrder?> _activeOrderController = StreamController<DoaOrder?>.broadcast();
  
  // Timers
  Timer? _refreshTimer;
  
  @override
  String get serviceName => 'CLIENT';
  
  @override
  String get requiredRole => 'client';

  // Streams públicos
  Stream<List<DoaRestaurant>> get restaurantsStream => _restaurantsController.stream;
  Stream<List<DoaOrder>> get ordersStream => _ordersController.stream;
  Stream<DoaOrder?> get activeOrderStream => _activeOrderController.stream;

  @override
  void onActivate() {
    
    // Emitir evento de activación
    emit(ServiceActivatedEvent(serviceName: serviceName, role: requiredRole));
    
    // Cargar datos iniciales
    _loadInitialData();
    
    // Iniciar refresh automático
    _startAutoRefresh();
    
    // Escuchar eventos relevantes
    _listenToEvents();
  }

  @override
  void onDeactivate() {
    
    // Emitir evento de desactivación
    emit(ServiceDeactivatedEvent(serviceName: serviceName, role: requiredRole));
    
    // Limpiar timers
    _refreshTimer?.cancel();
    _refreshTimer = null;
    
    // Limpiar streams (pero no cerrarlos)
    _restaurantsController.add([]);
    _ordersController.add([]);
    _activeOrderController.add(null);
  }

  /// 📊 Cargar datos iniciales
  void _loadInitialData() async {
    if (!hasAccess()) return;
    
    try {
      await loadRestaurants();
      await loadUserOrders();
      await checkActiveOrder();
    } catch (e) {
      debugPrint('❌ [CLIENT] Error cargando datos iniciales: $e');
    }
  }


  /// 🏪 Cargar restaurantes disponibles (Legacy / Fallback)
  Future<void> loadRestaurants() async {
    if (!hasAccess()) return;
    
    try {
      final response = await SupabaseConfig.client
          .from('restaurants')
          .select('id, name, description, logo_url, cover_image_url, cuisine_type, address, phone, online, status, average_rating, total_reviews, estimated_delivery_time_minutes, delivery_fee, location_lat, location_lon')
          .eq('is_active', true);
      _restaurantsController.add((response as List).map((json) => DoaRestaurant.fromJson(json)).toList());
    } catch (e) {
      debugPrint('❌ [CLIENT] Error cargando restaurantes: $e');
      _restaurantsController.add([]);
    }
  }

  /// 🔍 Buscar restaurantes cercanos (usando PostGIS + RPC Optimizado)
  Future<List<DoaRestaurant>> searchRestaurants({
    required double lat,
    required double lon,
    String? query,
    int radiusMeters = 5000,
  }) async {
    if (!hasAccess()) return [];

    try {
      
      final params = {
        'p_lat': lat,
        'p_lon': lon,
        'p_radius_meters': radiusMeters,
        'p_search_text': query,
      };

      final response = await SupabaseConfig.client
          .rpc(RpcNames.findNearbyRestaurants, params: params);

      final restaurants = (response as List)
          .map((json) => DoaRestaurant.fromJson(json))
          .toList();
      
      // Actualizar el stream principal si es una búsqueda general
      if (query == null || query.isEmpty) {
        _restaurantsController.add(restaurants);
      }
      
      return restaurants;
      
    } catch (e) {
      debugPrint('❌ [CLIENT] Error buscando restaurantes: $e');
      return [];
    }
  }

  /// 📝 Cargar órdenes del usuario
  Future<void> loadUserOrders() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            id, status, total_amount, delivery_address, delivery_fee, created_at, updated_at, delivery_time, order_notes, payment_method, restaurant_id, user_id, delivery_agent_id,
            restaurant:restaurants(id, name, logo_url, address, phone),
            delivery_agent:users!orders_delivery_agent_id_fkey(id, name, phone)
          ''')
          .eq('user_id', currentSession!.userId!)
          .order('created_at', ascending: false)
          .limit(20);
      _ordersController.add((response as List).map((json) => DoaOrder.fromJson(json)).toList());
    } catch (e) {
      debugPrint('❌ [CLIENT] Error cargando órdenes: $e');
      _ordersController.add([]);
    }
  }

  /// 🚚 Verificar orden activa
  Future<void> checkActiveOrder() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            id, status, total_amount, delivery_address, delivery_fee, created_at, order_notes, payment_method, restaurant_id, user_id, delivery_agent_id,
            restaurant:restaurants(id, name, logo_url, address, phone),
            delivery_agent:users!orders_delivery_agent_id_fkey(id, name, phone)
          ''')
          .eq('user_id', currentSession!.userId!)
          .inFilter('status', ['pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'arrived_at_restaurant', 'on_the_way', 'arrived_at_client'])
          .order('created_at', ascending: false)
          .limit(1);
      _activeOrderController.add(response.isNotEmpty ? DoaOrder.fromJson(response.first) : null);
    } catch (e) {
      debugPrint('❌ [CLIENT] Error verificando orden activa: $e');
      _activeOrderController.add(null);
    }
  }

  /// 🛒 Crear nueva orden
  Future<DoaOrder?> createOrder({
    required String restaurantId,
    required List<DoaOrderItem> items,
    required double total,
    String? deliveryAddress,
    String? notes,
  }) async {
    if (!hasAccess() || currentSession?.userId == null) return null;
    
    try {
      
      final orderData = {
        'user_id': currentSession!.userId,
        'restaurant_id': restaurantId,
        'items': items.map((item) => item.toJson()).toList(),
        'total_amount': total,
        'delivery_address': deliveryAddress,
        'notes': notes,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      final response = await SupabaseConfig.client
          .from('orders')
          .insert(orderData)
          .select('*, restaurants(*)')
          .single();
      
      final newOrder = DoaOrder.fromJson(response);
      
      // Actualizar streams
      await loadUserOrders();
      await checkActiveOrder();
      
      return newOrder;
      
    } catch (e) {
      debugPrint('❌ [CLIENT] Error creando orden: $e');
      return null;
    }
  }

  /// ❌ Cancelar orden
  Future<bool> cancelOrder(String orderId) async {
    if (!hasAccess()) return false;
    
    try {
      await OrderStatusHelper.updateOrderStatus(orderId, 'cancelled', currentSession?.userId);
      await loadUserOrders();
      await checkActiveOrder();
      return true;
    } catch (e) {
      debugPrint('❌ [CLIENT] Error cancelando orden: $e');
      return false;
    }
  }

  /// 🔄 Auto-refresh de datos
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!hasAccess()) {
        timer.cancel();
        return;
      }
      
      _loadInitialData();
    });
  }

  /// 👂 Escuchar eventos del sistema
  void _listenToEvents() {
    // Escuchar cambios de órdenes en tiempo real
    on<OrderStatusChangedEvent>().listen((event) {
      if (hasAccess() && event.orderUserId == currentSession?.userId) {
        // Una sola query consolida tanto las órdenes del historial como la activa
        checkActiveOrder();
        loadUserOrders();
      }
    });
  }

  /// 🧹 Limpiar recursos
  @override
  void dispose() {
    super.dispose();
    _refreshTimer?.cancel();
    _restaurantsController.close();
    _ordersController.close();
    _activeOrderController.close();
  }
}

/// 📡 Eventos específicos del cliente
class OrderStatusChangedEvent extends AppEvent {
  final String orderId;
  final String newStatus;
  final String orderUserId;
  
  OrderStatusChangedEvent({
    required this.orderId, 
    required this.newStatus,
    required this.orderUserId,
  }) : super(timestamp: DateTime.now(), userId: orderUserId);
}