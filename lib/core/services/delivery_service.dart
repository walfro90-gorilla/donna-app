import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:doa_repartos/core/services/base_service.dart';
import 'package:doa_repartos/core/events/event_bus.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// 🚚 DeliveryService - Servicio para usuarios tipo Repartidor
class DeliveryService extends BaseService {
  
  // Stream Controllers
  final StreamController<List<DoaOrder>> _availableOrdersController = StreamController<List<DoaOrder>>.broadcast();
  final StreamController<List<DoaOrder>> _myDeliveriesController = StreamController<List<DoaOrder>>.broadcast();
  final StreamController<DoaOrder?> _activeDeliveryController = StreamController<DoaOrder?>.broadcast();
  final StreamController<Map<String, dynamic>> _earningsController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Timers
  Timer? _refreshTimer;
  
  @override
  String get serviceName => 'DELIVERY';
  
  @override
  @override
  String get requiredRole => 'delivery_agent';

  // Streams públicos
  Stream<List<DoaOrder>> get availableOrdersStream => _availableOrdersController.stream;
  Stream<List<DoaOrder>> get myDeliveriesStream => _myDeliveriesController.stream;
  Stream<DoaOrder?> get activeDeliveryStream => _activeDeliveryController.stream;
  Stream<Map<String, dynamic>> get earningsStream => _earningsController.stream;

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
    _availableOrdersController.add([]);
    _myDeliveriesController.add([]);
    _activeDeliveryController.add(null);
    _earningsController.add({});
  }

  /// 📊 Cargar datos iniciales
  void _loadInitialData() async {
    if (!hasAccess()) return;
    
    try {
      // Cargar órdenes disponibles
      await loadAvailableOrders();
      
      // Cargar mis entregas
      await loadMyDeliveries();
      
      // Verificar entrega activa
      await checkActiveDelivery();
      
      // Cargar ganancias
      await loadEarnings();
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error cargando datos iniciales: $e');
    }
  }

  /// 📋 Cargar órdenes disponibles para entrega
  Future<void> loadAvailableOrders() async {
    if (!hasAccess()) return;
    
    try {
      final response = await DoaRepartosService.getAvailableOrdersForDelivery();
      _availableOrdersController.add(response.map((json) => DoaOrder.fromJson(json)).toList());
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error cargando órdenes disponibles: $e');
      _availableOrdersController.add([]);
    }
  }

  /// 🚚 Cargar mis entregas
  Future<void> loadMyDeliveries() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('orders')
          .select('id, status, total_amount, delivery_address, delivery_fee, created_at, updated_at, delivery_time, restaurant_id, user_id, delivery_agent_id, order_notes, payment_method, restaurants(id, name, address, phone)')
          .eq('delivery_agent_id', currentSession!.userId!)
          .order('created_at', ascending: false)
          .limit(30);
      _myDeliveriesController.add((response as List).map((json) => DoaOrder.fromJson(json)).toList());
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error cargando mis entregas: $e');
      _myDeliveriesController.add([]);
    }
  }

  /// 🎯 Verificar entrega activa
  Future<void> checkActiveDelivery() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    try {
      final response = await SupabaseConfig.client
          .from('orders')
          .select('id, status, total_amount, delivery_address, delivery_fee, created_at, restaurant_id, user_id, delivery_agent_id, restaurants(id, name, address, phone)')
          .eq('delivery_agent_id', currentSession!.userId!)
          .inFilter('status', ['in_delivery'])
          .order('created_at', ascending: false)
          .limit(1);
      if (response.isNotEmpty) {
        _activeDeliveryController.add(DoaOrder.fromJson(response.first));
      } else {
        _activeDeliveryController.add(null);
      }
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error verificando entrega activa: $e');
      _activeDeliveryController.add(null);
    }
  }

  /// 💰 Cargar ganancias
  Future<void> loadEarnings() async {
    if (!hasAccess() || currentSession?.userId == null) return;
    
    try {
      
      // Ganancias de hoy
      final todayStart = DateTime.now().copyWith(hour: 0, minute: 0, second: 0);
      final todayEnd = DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
      
      final todayDeliveries = await SupabaseConfig.client
          .from('orders')
          .select('delivery_fee')
          .eq('delivery_agent_id', currentSession!.userId!)
          .eq('status', 'delivered')
          .gte('created_at', todayStart.toIso8601String())
          .lte('created_at', todayEnd.toIso8601String());
      
      // Ganancias del mes
      final monthStart = DateTime.now().copyWith(day: 1, hour: 0, minute: 0, second: 0);
      final monthEnd = DateTime.now().copyWith(
        month: DateTime.now().month + 1, 
        day: 1, 
        hour: 0, 
        minute: 0, 
        second: 0
      ).subtract(const Duration(seconds: 1));
      
      final monthDeliveries = await SupabaseConfig.client
          .from('orders')
          .select('delivery_fee')
          .eq('delivery_agent_id', currentSession!.userId!)
          .eq('status', 'delivered')
          .gte('created_at', monthStart.toIso8601String())
          .lte('created_at', monthEnd.toIso8601String());
      
      // Calcular ganancias
      final earnings = {
        'today_deliveries': todayDeliveries.length,
        'today_earnings': todayDeliveries.fold<double>(0, (sum, order) => sum + (order['delivery_fee'] ?? 0)),
        'month_deliveries': monthDeliveries.length,
        'month_earnings': monthDeliveries.fold<double>(0, (sum, order) => sum + (order['delivery_fee'] ?? 0)),
        'last_updated': DateTime.now().toIso8601String(),
      };
      
      _earningsController.add(earnings);
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error cargando ganancias: $e');
      _earningsController.add({});
    }
  }

  /// ✋ Tomar orden para entrega
  Future<bool> takeOrder(String orderId) async {
    if (!hasAccess() || currentSession?.userId == null) return false;
    
    try {
      final ok = await DoaRepartosService.acceptOrder(orderId);
      if (!ok) {
        debugPrint('❌ [DELIVERY] Orden no pudo ser asignada: $orderId');
        return false;
      }
      
      // Actualizar streams
      await loadAvailableOrders();
      await loadMyDeliveries();
      await checkActiveDelivery();
      
      return true;
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error tomando orden: $e');
      return false;
    }
  }

  /// ✅ Marcar como entregada
  Future<bool> markAsDelivered(String orderId) async {
    if (!hasAccess()) return false;
    
    try {
      await OrderStatusHelper.updateOrderStatus(orderId, 'delivered', currentSession?.userId);
      
      // Actualizar streams
      await loadMyDeliveries();
      await checkActiveDelivery();
      await loadEarnings();
      
      return true;
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error marcando como entregada: $e');
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
      
      loadAvailableOrders();
      checkActiveDelivery();
    });
  }

  /// 👂 Escuchar eventos del sistema
  void _listenToEvents() {
    // Escuchar órdenes listas para entrega
    on<OrderReadyEvent>().listen((event) {
      if (hasAccess()) loadAvailableOrders();
    });
  }

  /// 🧹 Limpiar recursos
  @override
  void dispose() {
    super.dispose();
    _refreshTimer?.cancel();
    _availableOrdersController.close();
    _myDeliveriesController.close();
    _activeDeliveryController.close();
    _earningsController.close();
  }
}

/// 📡 Eventos específicos del repartidor
class OrderReadyEvent extends AppEvent {
  final String orderId;
  
  OrderReadyEvent({required this.orderId}) : super(timestamp: DateTime.now());
}