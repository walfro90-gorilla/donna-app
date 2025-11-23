import 'dart:async';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

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
  String get requiredRole => 'cliente';

  // Streams públicos
  Stream<List<DoaRestaurant>> get restaurantsStream => _restaurantsController.stream;
  Stream<List<DoaOrder>> get ordersStream => _ordersController.stream;
  Stream<DoaOrder?> get activeOrderStream => _activeOrderController.stream;

  @override
  void onActivate() {
    print('🛍️ [CLIENT] Cliente activado: ${currentSession?.email}');
    
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
    print('🛑 [CLIENT] Cliente desactivado');
    
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
    
    print('📊 [CLIENT] Cargando datos iniciales...');
    
    try {
      // Cargar restaurantes
      await loadRestaurants();
      
      // Cargar órdenes del cliente
      await loadUserOrders();
      
      // Verificar orden activa
      await checkActiveOrder();
      
    } catch (e) {
      print('❌ [CLIENT] Error cargando datos iniciales: $e');
    }
  }

  /// 🏪 Cargar restaurantes disponibles
  Future<void> loadRestaurants() async {
    if (!hasAccess()) return;
    
    try {
      print('🏪 [CLIENT] Cargando restaurantes...');
      
      final response = await SupabaseConfig.client
          .from('restaurants')
          .select('*')
          .eq('is_active', true);
      
      final restaurants = (response as List)
          .map((json) => DoaRestaurant.fromJson(json))
          .toList();
      
      print('✅ [CLIENT] ${restaurants.length} restaurantes cargados');
      _restaurantsController.add(restaurants);
      
    } catch (e) {
      print('❌ [CLIENT] Error cargando restaurantes: $e');
      _restaurantsController.add([]);
    }
  }

  /// 📝 Cargar órdenes del usuario
  Future<void> loadUserOrders() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      print('📝 [CLIENT] Cargando órdenes del usuario...');
      
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            user:users!orders_user_id_fkey(*, client_profiles(*)),
            restaurant:restaurants(*),
            delivery_agent:users!orders_delivery_agent_id_fkey(*)
          ''')
          .eq('user_id', currentSession!.userId!)
          .order('created_at', ascending: false)
          .limit(20);
      
      final orders = (response as List)
          .map((json) => DoaOrder.fromJson(json))
          .toList();
      
      print('✅ [CLIENT] ${orders.length} órdenes cargadas');
      _ordersController.add(orders);
      
    } catch (e) {
      print('❌ [CLIENT] Error cargando órdenes: $e');
      _ordersController.add([]);
    }
  }

  /// 🚚 Verificar orden activa
  Future<void> checkActiveOrder() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      print('🚚 [CLIENT] Verificando orden activa...');
      
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            user:users!orders_user_id_fkey(*, client_profiles(*)),
            restaurant:restaurants(*),
            delivery_agent:users!orders_delivery_agent_id_fkey(*)
          ''')
          .eq('user_id', currentSession!.userId!)
          .inFilter('status', ['pending', 'confirmed', 'in_preparation', 'ready_for_pickup', 'assigned', 'on_the_way'])
          .order('created_at', ascending: false)
          .limit(1);
      
      if (response.isNotEmpty) {
        final activeOrder = DoaOrder.fromJson(response.first);
        print('🎯 [CLIENT] Orden activa encontrada: ${activeOrder.id}');
        _activeOrderController.add(activeOrder);
      } else {
        print('📭 [CLIENT] No hay órdenes activas');
        _activeOrderController.add(null);
      }
      
    } catch (e) {
      print('❌ [CLIENT] Error verificando orden activa: $e');
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
      print('🛒 [CLIENT] Creando nueva orden...');
      
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
      print('✅ [CLIENT] Orden creada: ${newOrder.id}');
      
      // Actualizar streams
      await loadUserOrders();
      await checkActiveOrder();
      
      return newOrder;
      
    } catch (e) {
      print('❌ [CLIENT] Error creando orden: $e');
      return null;
    }
  }

  /// ❌ Cancelar orden
  Future<bool> cancelOrder(String orderId) async {
    if (!hasAccess()) return false;
    
    try {
      print('❌ [CLIENT] Cancelando orden: $orderId');
      
      // 🎯 Usar helper estático (con tracking automático)
      await OrderStatusHelper.updateOrderStatus(orderId, 'cancelled', currentSession?.userId);
      
      print('✅ [CLIENT] Orden cancelada exitosamente');
      
      // Actualizar streams
      await loadUserOrders();
      await checkActiveOrder();
      
      return true;
      
    } catch (e) {
      print('❌ [CLIENT] Error cancelando orden: $e');
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
      
      print('🔄 [CLIENT] Auto-refresh ejecutándose...');
      _loadInitialData();
    });
  }

  /// 👂 Escuchar eventos del sistema
  void _listenToEvents() {
    // Escuchar cambios de órdenes en tiempo real
    on<OrderStatusChangedEvent>().listen((event) {
      if (hasAccess() && event.orderUserId == currentSession?.userId) {
        print('📡 [CLIENT] Orden actualizada: ${event.orderId} -> ${event.newStatus}');
        loadUserOrders();
        checkActiveOrder();
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