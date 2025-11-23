import 'package:doa_repartos/models/doa_models.dart';

/// Servicio mock - ahora retorna datos vacíos
/// Se usa únicamente la conexión real de Supabase
class MockDoaService {
  
  // Simular delay de red
  static Future<void> _simulateDelay() async {
    await Future.delayed(const Duration(milliseconds: 500));
  }
  
  // === USUARIOS ===
  
  /// Obtener usuario por ID
  static Future<DoaUser?> getUserById(String userId) async {
    await _simulateDelay();
    // Retorna null ya que no usamos datos de prueba
    return null;
  }
  
  /// Obtener usuarios por rol
  static Future<List<DoaUser>> getUsersByRole(UserRole role) async {
    await _simulateDelay();
    // Retorna lista vacía ya que no usamos datos de prueba
    return [];
  }
  
  /// Actualizar perfil de usuario
  static Future<bool> updateUserProfile(String userId, Map<String, dynamic> updates) async {
    await _simulateDelay();
    try {
      // Simula actualización sin datos de prueba
      print('✅ Mock: Usuario $userId actualizado con $updates');
      return true;
    } catch (e) {
      print('❌ Error actualizando usuario: $e');
      return false;
    }
  }
  
  // === RESTAURANTES ===
  
  /// Obtener todos los restaurantes
  static Future<List<DoaRestaurant>> getRestaurants({RestaurantStatus? status}) async {
    await _simulateDelay();
    List<DoaRestaurant> restaurants = [];
    
    if (status != null) {
      restaurants = restaurants.where((r) => r.status == status).toList();
    }
    
    return restaurants;
  }
  
  /// Obtener restaurantes abiertos solamente
  static Future<List<DoaRestaurant>> getOpenRestaurants() async {
    await _simulateDelay();
    // Retorna lista vacía ya que no usamos datos de prueba
    return [];
  }
  
  /// Obtener restaurantes por usuario
  static Future<List<DoaRestaurant>> getRestaurantsByUser(String userId) async {
    await _simulateDelay();
    // Retorna lista vacía ya que no usamos datos de prueba
    return [];
  }
  
  /// Crear nuevo restaurante
  static Future<DoaRestaurant?> createRestaurant(Map<String, dynamic> restaurantData) async {
    await _simulateDelay();
    try {
      final newRestaurant = DoaRestaurant(
        id: 'rest_new_${DateTime.now().millisecondsSinceEpoch}',
        userId: restaurantData['userId'] ?? '',
        name: restaurantData['name'] ?? '',
        description: restaurantData['description'] ?? '',
        logoUrl: restaurantData['logoUrl'] ?? '',
        status: RestaurantStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        imageUrl: restaurantData['imageUrl'] ?? '',
        rating: 0.0,
        deliveryTime: 35,
        deliveryFee: 3000.0,
        isOpen: false,
      );
      
      print('✅ Mock: Restaurante creado: ${newRestaurant.name}');
      return newRestaurant;
    } catch (e) {
      print('❌ Error creando restaurante: $e');
      return null;
    }
  }
  
  /// Actualizar estado del restaurante
  static Future<bool> updateRestaurantStatus(String restaurantId, RestaurantStatus status) async {
    await _simulateDelay();
    try {
      // Simula encontrar restaurante sin datos de prueba
      DoaRestaurant? restaurant;
      
      print('✅ Mock: Restaurante $restaurantId cambiado a estado: $status');
      return true;
    } catch (e) {
      print('❌ Error actualizando estado del restaurante: $e');
      return false;
    }
  }
  
  // === PRODUCTOS ===
  
  /// Obtener productos de un restaurante
  static Future<List<DoaProduct>> getProductsByRestaurant(String restaurantId, {bool? onlyAvailable}) async {
    await _simulateDelay();
    List<DoaProduct> products = [];
    
    if (onlyAvailable == true) {
      products = products.where((p) => p.isAvailable).toList();
    }
    
    return products;
  }
  
  /// Crear nuevo producto
  static Future<DoaProduct?> createProduct(Map<String, dynamic> productData) async {
    await _simulateDelay();
    try {
      final newProduct = DoaProduct(
        id: 'prod_new_${DateTime.now().millisecondsSinceEpoch}',
        restaurantId: productData['restaurantId'] ?? '',
        name: productData['name'] ?? '',
        description: productData['description'] ?? '',
        price: (productData['price'] ?? 0).toDouble(),
        imageUrl: productData['imageUrl'] ?? '',
        isAvailable: productData['isAvailable'] ?? true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      print('✅ Mock: Producto creado: ${newProduct.name}');
      return newProduct;
    } catch (e) {
      print('❌ Error creando producto: $e');
      return null;
    }
  }
  
  /// Actualizar disponibilidad del producto
  static Future<bool> updateProductAvailability(String productId, bool isAvailable) async {
    await _simulateDelay();
    try {
      // Simula encontrar producto sin datos de prueba
      DoaProduct? product;
      
      print('✅ Mock: Producto $productId disponibilidad: $isAvailable');
      return true;
    } catch (e) {
      print('❌ Error actualizando disponibilidad del producto: $e');
      return false;
    }
  }
  
  // === PEDIDOS ===
  
  /// Obtener pedidos con detalles
  static Future<List<Map<String, dynamic>>> getOrdersWithDetails({
    String? userId,
    String? restaurantId,
    OrderStatus? status,
  }) async {
    await _simulateDelay();
    
    List<DoaOrder> orders = [];
    
    // Filtrar por usuario si se especifica
    if (userId != null) {
      orders = orders.where((o) => o.userId == userId).toList();
    }
    
    // Filtrar por restaurante si se especifica
    if (restaurantId != null) {
      orders = orders.where((o) => o.restaurantId == restaurantId).toList();
    }
    
    // Filtrar por estado si se especifica
    if (status != null) {
      orders = orders.where((o) => o.status == status).toList();
    }
    
    // Convertir a detalles completos
    List<Map<String, dynamic>> ordersWithDetails = [];
    
    for (final order in orders) {
      // Simula datos sin usar TestData
      DoaUser? user;
      DoaRestaurant? restaurant;
      List<DoaOrderItem> orderItems = [];
      DoaPayment? payment;
      
      // Obtener detalles de productos para cada item
      List<Map<String, dynamic>> itemsWithDetails = [];
      for (final item in orderItems) {
        // Simula producto sin datos de prueba
        DoaProduct? product;
        
        if (product != null) {
          itemsWithDetails.add({
            'orderItem': item,
            'product': product,
            'subtotal': item.quantity * item.priceAtTimeOfOrder,
          });
        }
      }
      
      ordersWithDetails.add({
        'order': order,
        'user': user,
        'restaurant': restaurant,
        'items': itemsWithDetails,
        'payment': payment,
        'itemsCount': orderItems.length,
        'totalItems': orderItems.fold<int>(0, (sum, item) => sum + item.quantity),
      });
    }
    
    return ordersWithDetails;
  }
  
  /// Crear pedido con items
  static Future<Map<String, dynamic>?> createOrderWithItems(
    Map<String, dynamic> orderData,
    List<Map<String, dynamic>> orderItems,
  ) async {
    await _simulateDelay();
    
    try {
      final orderId = 'order_new_${DateTime.now().millisecondsSinceEpoch}';
      
      final newOrder = DoaOrder(
        id: orderId,
        userId: orderData['userId'] ?? '',
        restaurantId: orderData['restaurantId'] ?? '',
        status: OrderStatus.pending,
        totalAmount: (orderData['totalAmount'] ?? 0).toDouble(),
        paymentMethod: PaymentMethod.values.firstWhere(
          (method) => method.name == orderData['paymentMethod'],
          orElse: () => PaymentMethod.card,
        ),
        deliveryAddress: orderData['deliveryAddress'] ?? '',
        deliveryLatlng: orderData['deliveryLatlng'] ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      // Crear items del pedido
      List<DoaOrderItem> createdItems = [];
      for (int i = 0; i < orderItems.length; i++) {
        final itemData = orderItems[i];
        final newItem = DoaOrderItem(
          id: '${orderId}_item_$i',
          orderId: orderId,
          productId: itemData['productId'] ?? '',
          quantity: itemData['quantity'] ?? 1,
          priceAtTimeOfOrder: (itemData['priceAtTimeOfOrder'] ?? 0).toDouble(),
          createdAt: DateTime.now(),
        );
        createdItems.add(newItem);
      }
      
      print('✅ Mock: Pedido creado con ${createdItems.length} items');
      
      return {
        'order': newOrder,
        'items': createdItems,
      };
    } catch (e) {
      print('❌ Error creando pedido: $e');
      return null;
    }
  }
  
  /// Actualizar estado del pedido
  static Future<bool> updateOrderStatus(String orderId, OrderStatus status, {String? deliveryAgentId}) async {
    await _simulateDelay();
    
    try {
      // Simula encontrar orden sin datos de prueba
      DoaOrder? order;
      
      print('✅ Mock: Pedido $orderId cambiado a estado: $status');
      if (deliveryAgentId != null) {
        print('✅ Mock: Repartidor asignado: $deliveryAgentId');
      }
      return true;
    } catch (e) {
      print('❌ Error actualizando estado del pedido: $e');
      return false;
    }
  }
  
  /// Obtener pedidos disponibles para delivery
  static Future<List<Map<String, dynamic>>> getAvailableOrdersForDelivery() async {
    await _simulateDelay();
    
    return await getOrdersWithDetails(status: OrderStatus.inPreparation);
  }
  
  // === PAGOS ===
  
  /// Crear pago
  static Future<DoaPayment?> createPayment(Map<String, dynamic> paymentData) async {
    await _simulateDelay();
    
    try {
      final newPayment = DoaPayment(
        id: 'pay_new_${DateTime.now().millisecondsSinceEpoch}',
        orderId: paymentData['orderId'] ?? '',
        stripePaymentId: paymentData['stripePaymentId'],
        amount: (paymentData['amount'] ?? 0).toDouble(),
        status: PaymentStatus.pending,
        createdAt: DateTime.now(),
      );
      
      print('✅ Mock: Pago creado por \$${newPayment.amount}');
      return newPayment;
    } catch (e) {
      print('❌ Error creando pago: $e');
      return null;
    }
  }
  
  /// Actualizar estado del pago
  static Future<bool> updatePaymentStatus(String paymentId, PaymentStatus status) async {
    await _simulateDelay();
    
    try {
      // Simula encontrar pago sin datos de prueba
      DoaPayment? payment;
      
      print('✅ Mock: Pago $paymentId cambiado a estado: $status');
      return true;
    } catch (e) {
      print('❌ Error actualizando estado del pago: $e');
      return false;
    }
  }
  
  /// Obtener pago por pedido
  static Future<DoaPayment?> getPaymentByOrderId(String orderId) async {
    await _simulateDelay();
    
    try {
      // Retorna null ya que no usamos datos de prueba
      return null;
    } catch (e) {
      return null;
    }
  }
  
  // === ANALYTICS ===
  
  /// Obtener analíticas del restaurante
  static Future<Map<String, dynamic>> getRestaurantAnalytics(String restaurantId) async {
    await _simulateDelay();
    
    List<DoaOrder> restaurantOrders = [];
    
    final totalOrders = restaurantOrders.length;
    final totalRevenue = restaurantOrders
        .where((o) => o.status == OrderStatus.delivered)
        .fold(0.0, (sum, order) => sum + order.totalAmount);
    
    final deliveredOrders = restaurantOrders
        .where((o) => o.status == OrderStatus.delivered)
        .length;
    
    return {
      'restaurantId': restaurantId,
      'totalOrders': totalOrders,
      'deliveredOrders': deliveredOrders,
      'totalRevenue': totalRevenue,
      'averageOrderValue': deliveredOrders > 0 ? totalRevenue / deliveredOrders : 0.0,
      'completionRate': totalOrders > 0 ? (deliveredOrders / totalOrders) * 100 : 0.0,
    };
  }
  
  // === MÉTODOS DE UTILIDAD ===
  
  /// Simular búsqueda de restaurantes por texto
  static Future<List<DoaRestaurant>> searchRestaurants(String query) async {
    await _simulateDelay();
    
    final searchQuery = query.toLowerCase();
    // Retorna lista vacía ya que no usamos datos de prueba
    return [];
  }
  
  /// Obtener estadísticas generales de la plataforma
  static Future<Map<String, dynamic>> getPlatformStats() async {
    await _simulateDelay();
    
    // Retorna estadísticas vacías ya que no usamos datos de prueba
    final totalUsers = 0;
    final totalRestaurants = 0;
    final totalOrders = 0;
    final totalRevenue = 0.0;
    
    return {
      'totalUsers': totalUsers,
      'totalRestaurants': totalRestaurants,
      'totalOrders': totalOrders,
      'totalRevenue': totalRevenue,
      'activeDeliveryAgents': 0,
    };
  }
}