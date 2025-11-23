import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/core/registry/service_registry.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Servicio específico para funcionalidades de Restaurante
class RestaurantService extends BaseService implements RealtimeService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // Stream controllers
  final StreamController<List<DoaRestaurant>> _restaurantsController = StreamController.broadcast();
  final StreamController<List<DoaOrder>> _ordersController = StreamController.broadcast();
  final StreamController<List<DoaProduct>> _productsController = StreamController.broadcast();
  
  // Estado interno
  DoaRestaurant? _currentRestaurant;
  List<DoaOrder> _currentOrders = [];
  List<DoaProduct> _currentProducts = [];
  
  // Suscripciones de tiempo real
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _productsSubscription;
  
  RestaurantService({required String userId, required UserRole role}) 
      : super(userId: userId, role: role) {
    print('🏪 [RESTAURANT_SERVICE] Creating service for user: $userId');
  }

  // ===== GETTERS =====
  DoaRestaurant? get currentRestaurant => _currentRestaurant;
  List<DoaOrder> get currentOrders => _currentOrders;
  List<DoaProduct> get currentProducts => _currentProducts;
  
  @override
  Stream<List<DoaRestaurant>> get dataStream => _restaurantsController.stream;
  Stream<List<DoaOrder>> get ordersStream => _ordersController.stream;
  Stream<List<DoaProduct>> get productsStream => _productsController.stream;

  // ===== INICIALIZACIÓN =====
  @override
  Future<void> startListening() async {
    print('🎯 [RESTAURANT_SERVICE] Starting realtime listening for user: $userId');
    
    try {
      // Cargar datos iniciales
      await _loadRestaurantData();
      await _loadOrders();
      await _loadProducts();
      
      // Configurar suscripciones en tiempo real
      await _setupRealtimeSubscriptions();
      
      print('✅ [RESTAURANT_SERVICE] Realtime listening started successfully');
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error starting realtime: $e');
      publishError('Failed to start restaurant service', 'RestaurantService.startListening', e);
    }
  }

  @override
  Future<void> stopListening() async {
    print('🛑 [RESTAURANT_SERVICE] Stopping realtime listening for user: $userId');
    
    await _ordersSubscription?.cancel();
    await _productsSubscription?.cancel();
    
    _ordersSubscription = null;
    _productsSubscription = null;
    
    print('✅ [RESTAURANT_SERVICE] Realtime listening stopped');
  }

  // ===== CARGA DE DATOS =====
  Future<void> _loadRestaurantData() async {
    print('🔄 [RESTAURANT_SERVICE] Loading restaurant data for owner: $userId');
    
    try {
      final response = await _supabase
          .from('restaurants')
          .select()
          .eq('owner_id', userId)
          .single();
      
      _currentRestaurant = DoaRestaurant.fromJson(response);
      print('✅ [RESTAURANT_SERVICE] Restaurant loaded: ${_currentRestaurant?.name}');
      
    } catch (e) {
      print('⚠️ [RESTAURANT_SERVICE] No restaurant found for user: $userId');
      _currentRestaurant = null;
    }
  }

  Future<void> _loadOrders() async {
    if (_currentRestaurant == null) return;
    
    print('🔄 [RESTAURANT_SERVICE] Loading orders for restaurant: ${_currentRestaurant!.id}');
    
    try {
      final response = await _supabase
          .from('orders')
          .select('*, order_items(*)')
          .eq('restaurant_id', _currentRestaurant!.id)
          .order('created_at', ascending: false);
      
      _currentOrders = response.map((data) => DoaOrder.fromJson(data)).toList();
      _ordersController.add(_currentOrders);
      
      publishDataUpdate('orders', {'count': _currentOrders.length});
      print('✅ [RESTAURANT_SERVICE] Loaded ${_currentOrders.length} orders');
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error loading orders: $e');
      publishError('Failed to load orders', 'RestaurantService._loadOrders', e);
    }
  }

  Future<void> _loadProducts() async {
    if (_currentRestaurant == null) return;
    
    print('🔄 [RESTAURANT_SERVICE] Loading products for restaurant: ${_currentRestaurant!.id}');
    
    try {
      final response = await _supabase
          .from('products')
          .select()
          .eq('restaurant_id', _currentRestaurant!.id)
          .eq('is_active', true)
          .order('name', ascending: true);
      
      _currentProducts = response.map((data) => DoaProduct.fromJson(data)).toList();
      _productsController.add(_currentProducts);
      
      publishDataUpdate('products', {'count': _currentProducts.length});
      print('✅ [RESTAURANT_SERVICE] Loaded ${_currentProducts.length} products');
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error loading products: $e');
      publishError('Failed to load products', 'RestaurantService._loadProducts', e);
    }
  }

  // ===== TIEMPO REAL =====
  Future<void> _setupRealtimeSubscriptions() async {
    if (_currentRestaurant == null) return;
    
    print('📡 [RESTAURANT_SERVICE] Setting up realtime subscriptions...');
    
    // Suscripción a órdenes
    _ordersSubscription = _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', _currentRestaurant!.id)
        .listen(_onOrdersChanged);
    
    // Suscripción a productos
    _productsSubscription = _supabase
        .from('products')
        .stream(primaryKey: ['id'])
        .eq('restaurant_id', _currentRestaurant!.id)
        .listen(_onProductsChanged);
    
    print('✅ [RESTAURANT_SERVICE] Realtime subscriptions configured');
  }

  void _onOrdersChanged(List<Map<String, dynamic>> data) {
    print('📨 [RESTAURANT_SERVICE] Orders updated - ${data.length} records');
    
    try {
      _currentOrders = data.map((item) => DoaOrder.fromJson(item)).toList();
      _ordersController.add(_currentOrders);
      
      publishDataUpdate('orders', {
        'count': _currentOrders.length,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error processing orders update: $e');
    }
  }

  void _onProductsChanged(List<Map<String, dynamic>> data) {
    print('📦 [RESTAURANT_SERVICE] Products updated - ${data.length} records');
    
    try {
      _currentProducts = data.map((item) => DoaProduct.fromJson(item)).toList();
      _productsController.add(_currentProducts);
      
      publishDataUpdate('products', {
        'count': _currentProducts.length,
        'timestamp': DateTime.now().toIso8601String(),
      });
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error processing products update: $e');
    }
  }

  // ===== OPERACIONES CRUD =====
  Future<bool> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    print('🔄 [RESTAURANT_SERVICE] Updating order $orderId to ${newStatus.toString()}');
    
    try {
      // 🎯 Usar helper estático (con tracking automático)
      final success = await OrderStatusHelper.updateOrderStatus(
        orderId, 
        newStatus.toString(), 
        userId
      );
      
      if (success) {
        print('✅ [RESTAURANT_SERVICE] Order status updated successfully');
        return true;
      } else {
        print('❌ [RESTAURANT_SERVICE] Failed to update order status');
        return false;
      }
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error updating order status: $e');
      publishError('Failed to update order status', 'RestaurantService.updateOrderStatus', e);
      return false;
    }
  }

  Future<bool> createProduct(DoaProduct product) async {
    print('🔄 [RESTAURANT_SERVICE] Creating new product: ${product.name}');
    
    try {
      await _supabase
          .from('products')
          .insert(product.toJson());
      
      print('✅ [RESTAURANT_SERVICE] Product created successfully');
      return true;
      
    } catch (e) {
      print('❌ [RESTAURANT_SERVICE] Error creating product: $e');
      publishError('Failed to create product', 'RestaurantService.createProduct', e);
      return false;
    }
  }

  // ===== CLEANUP =====
  @override
  Future<void> dispose() async {
    print('🗑️ [RESTAURANT_SERVICE] Disposing restaurant service for user: $userId');
    
    await stopListening();
    
    await _restaurantsController.close();
    await _ordersController.close();
    await _productsController.close();
    
    _currentRestaurant = null;
    _currentOrders.clear();
    _currentProducts.clear();
    
    await super.dispose();
    print('✅ [RESTAURANT_SERVICE] Restaurant service disposed');
  }
}

/// Factory para crear RestaurantService
class RestaurantServiceFactory extends ServiceFactory<RestaurantService> {
  @override
  RestaurantService create({required String userId, required UserRole role}) {
    if (role != UserRole.restaurant) {
      throw ArgumentError('RestaurantService can only be created for restaurant users');
    }
    
    return RestaurantService(userId: userId, role: role);
  }
}