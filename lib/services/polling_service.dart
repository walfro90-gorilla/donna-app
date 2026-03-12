import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/network_service.dart';
import 'package:doa_repartos/services/alert_sound_service.dart';

/// Servicio de polling inteligente como respaldo del tiempo real
class PollingService {
  static final PollingService _instance = PollingService._internal();
  factory PollingService() => _instance;
  PollingService._internal();

  // Stream controllers para notificaciones
  final StreamController<DoaOrder> _newOrdersController = StreamController<DoaOrder>.broadcast();
  final StreamController<DoaOrder> _orderUpdatesController = StreamController<DoaOrder>.broadcast();
  final StreamController<DoaOrder> _confirmedOrdersController = StreamController<DoaOrder>.broadcast();
  final StreamController<void> _refreshDataController = StreamController<void>.broadcast();
  final StreamController<void> _restaurantsUpdatedController = StreamController<void>.broadcast();

  // Streams públicos
  Stream<DoaOrder> get newOrders => _newOrdersController.stream;
  Stream<DoaOrder> get orderUpdates => _orderUpdatesController.stream;
  Stream<DoaOrder> get confirmedOrders => _confirmedOrdersController.stream;
  Stream<void> get refreshData => _refreshDataController.stream;
  Stream<void> get restaurantsUpdated => _restaurantsUpdatedController.stream;

  // Control de polling
  Timer? _pollingTimer;
  bool _isActive = false;
  String? _currentUserId;
  UserRole? _currentUserRole;
  
  // Control inteligente de polling
  bool _isBackupMode = false; // Si está en modo respaldo por falla de realtime
  DateTime? _lastRealtimeEvent;
  int _currentInterval = 30; // Intervalo dinámico en segundos
  
  // Cache de órdenes para detectar cambios
  List<DoaOrder> _cachedOrders = [];
  Map<String, OrderStatus> _cachedOrderStatuses = {};
  
  // Cache de restaurantes para detectar cambios
  List<DoaRestaurant> _cachedRestaurants = [];
  Map<String, bool> _cachedRestaurantOnlineStatus = {};

  /// Inicializar servicio de polling inteligente
  Future<void> initialize(String userId, UserRole userRole) async {
    _currentUserId = userId;
    _currentUserRole = userRole;
    _isActive = true;
    _isBackupMode = false;
    _currentInterval = 30; // Iniciar conservador
    
    // Limpiar cache
    _cachedOrders.clear();
    _cachedOrderStatuses.clear();
    _cachedRestaurants.clear();
    _cachedRestaurantOnlineStatus.clear();
    
    // Cargar datos iniciales
    await _loadInitialOrders();
    await _loadInitialRestaurants();
    
    // Iniciar polling con estrategia inteligente
    _startIntelligentPolling();
    
  }
  
  /// Iniciar polling con estrategia inteligente
  void _startIntelligentPolling() {
    _pollingTimer?.cancel();
    
    _pollingTimer = Timer.periodic(Duration(seconds: _currentInterval), (_) async {
      if (!_isActive) return;
      
      // Determinar si necesitamos activar modo respaldo
      _evaluateBackupMode();
      
      // Ajustar intervalo dinámicamente
      _adjustPollingInterval();
      
      // Ejecutar verificaciones
      await _checkForChanges();
      
      // Reiniciar timer si el intervalo cambió
      if (_shouldRestartTimer()) {
        _restartPollingTimer();
      }
    });
    
  }
  
  /// Evaluar si necesitamos activar modo respaldo
  void _evaluateBackupMode() {
    final now = DateTime.now();
    final networkService = NetworkService();
    
    // Activar modo respaldo si:
    // 1. No hay internet (usar datos locales)
    // 2. No hay eventos de realtime por más de 2 minutos
    // 3. Red está limitada
    
    final shouldActivateBackup = !networkService.isConnected || 
        networkService.currentStatus == NetworkStatus.limited ||
        (_lastRealtimeEvent != null && 
         now.difference(_lastRealtimeEvent!).inMinutes > 2);
    
    if (shouldActivateBackup != _isBackupMode) {
      _isBackupMode = shouldActivateBackup;
      debugPrint(_isBackupMode ? '🆘 [POLLING] Modo respaldo activado' : '✅ [POLLING] Modo normal restaurado');
    }
  }
  
  /// Ajustar intervalo de polling dinámicamente
  void _adjustPollingInterval() {
    final networkService = NetworkService();
    int newInterval;
    
    if (!networkService.isConnected) {
      // Sin internet: polling muy lento para ahorrar batería
      newInterval = 60;
    } else if (_isBackupMode) {
      // Modo respaldo: más agresivo
      newInterval = 10;
    } else if (networkService.currentStatus == NetworkStatus.limited) {
      // Conexión limitada: moderado
      newInterval = 20;
    } else {
      // Red buena y realtime funcionando: conservador
      newInterval = 30;
    }
    
    if (newInterval != _currentInterval) {
      _currentInterval = newInterval;
    }
  }
  
  /// Verificar si necesitamos reiniciar el timer
  bool _shouldRestartTimer() {
    // Solo reiniciar si el cambio de intervalo es significativo
    final currentTimerInterval = _pollingTimer?.tick != null 
        ? Duration(seconds: _currentInterval) 
        : null;
    return currentTimerInterval == null;
  }
  
  /// Reiniciar el timer con nuevo intervalo
  void _restartPollingTimer() {
    _pollingTimer?.cancel();
    _startIntelligentPolling();
  }
  
  /// Registrar evento de realtime para controlar el respaldo
  void notifyRealtimeActivity() {
    _lastRealtimeEvent = DateTime.now();
    
    if (_isBackupMode) {
      _isBackupMode = false;
    }
  }
  
  /// Verificar todos los cambios (método unificado)
  Future<void> _checkForChanges() async {
    try {
      await _checkForOrderChanges();
      await _checkForRestaurantChanges();
    } catch (e) {
      debugPrint('❌ [POLLING] Error en verificación: $e');
    }
  }

  /// Cargar órdenes iniciales para establecer baseline
  Future<void> _loadInitialOrders() async {
    try {
        
      final orders = await _fetchOrdersForUser();
      _cachedOrders = orders;
      _cachedOrderStatuses = {
        for (var order in orders) order.id: order.status
      };
      
    } catch (e) {
      debugPrint('❌ [POLLING] Error cargando órdenes iniciales: $e');
    }
  }

  /// Verificar cambios en las órdenes con control de respaldo
  Future<void> _checkForOrderChanges() async {
    try {
      // Evitar consultas innecesarias cuando Realtime está saludable
      if (!_isBackupMode && _cachedOrders.isNotEmpty) {
        return;
      }

      final currentOrders = await _fetchOrdersForUser();

      // Solo detectar cambios si estamos en modo respaldo o es verificación inicial
      if (_isBackupMode || _cachedOrders.isEmpty) {
        // Detectar nuevas órdenes
        await _detectNewOrders(currentOrders);

        // Detectar actualizaciones de estado
        await _detectOrderUpdates(currentOrders);

        if (_hasOrderChanges(currentOrders)) {
          _refreshDataController.add(null);
        }

        // Actualizar cache cuando se usa en respaldo o bootstrap inicial
        _cachedOrders = currentOrders;
        _cachedOrderStatuses = {
          for (var order in currentOrders) order.id: order.status
        };
      }
    } catch (e) {
      debugPrint('❌ [POLLING] Error verificando órdenes: $e');
    }
  }
  
  /// Verificar si hay cambios reales en las órdenes
  bool _hasOrderChanges(List<DoaOrder> currentOrders) {
    if (_cachedOrders.length != currentOrders.length) return true;
    
    final currentIds = currentOrders.map((o) => o.id).toSet();
    final cachedIds = _cachedOrders.map((o) => o.id).toSet();
    
    if (!currentIds.containsAll(cachedIds) || !cachedIds.containsAll(currentIds)) {
      return true;
    }
    
    // Verificar cambios de estado
    for (var order in currentOrders) {
      final cachedStatus = _cachedOrderStatuses[order.id];
      if (cachedStatus != order.status) return true;
    }
    
    return false;
  }

  /// Detectar nuevas órdenes
  Future<void> _detectNewOrders(List<DoaOrder> currentOrders) async {
    final cachedIds = _cachedOrders.map((o) => o.id).toSet();
    final newOrders = currentOrders.where((order) => !cachedIds.contains(order.id)).toList();
    
    for (var newOrder in newOrders) {
      _newOrdersController.add(newOrder);
      
      // Si es para restaurantes y la orden está pendiente
      if (_currentUserRole == UserRole.restaurant && newOrder.status == OrderStatus.pending) {
        unawaited(AlertSoundService.instance.playRestaurantNewOrder());
      }
      if (_currentUserRole == UserRole.delivery_agent && newOrder.status == OrderStatus.confirmed) {
        _confirmedOrdersController.add(newOrder);
        unawaited(AlertSoundService.instance.playDeliveryNewOrder());
      }
    }
  }

  /// Detectar actualizaciones de estado
  Future<void> _detectOrderUpdates(List<DoaOrder> currentOrders) async {
    for (var currentOrder in currentOrders) {
      final previousStatus = _cachedOrderStatuses[currentOrder.id];
      
      if (previousStatus != null && previousStatus != currentOrder.status) {
        _orderUpdatesController.add(currentOrder);
        
        // Si cambió de pending a confirmed, notificar a repartidores
        if (previousStatus == OrderStatus.pending &&
            currentOrder.status == OrderStatus.confirmed) {
          _confirmedOrdersController.add(currentOrder);
        }
      }
    }
  }

  /// Obtener órdenes según el rol del usuario
  Future<List<DoaOrder>> _fetchOrdersForUser() async {
    try {
      if (_currentUserId == null || _currentUserRole == null) {
        return [];
      }

      List<DoaOrder> orders = [];

      switch (_currentUserRole!) {
        case UserRole.restaurant:
          orders = await _fetchRestaurantOrders();
          break;
        case UserRole.delivery_agent:
          orders = await _fetchDeliveryAgentOrders();
          break;
        case UserRole.client:
          orders = await _fetchClientOrders();
          break;
        case UserRole.admin:
          orders = await _fetchAllOrders();
          break;
      }

      return orders;
    } catch (e) {
      debugPrint('❌ [POLLING] Error obteniendo órdenes: $e');
      return [];
    }
  }

  /// Obtener órdenes para restaurante
  Future<List<DoaOrder>> _fetchRestaurantOrders() async {
    // Primero obtener el restaurante del usuario
    final restaurantResponse = await SupabaseConfig.client
        .from('restaurants')
        .select('id')
        .eq('user_id', _currentUserId!)
        .maybeSingle();
    
    if (restaurantResponse == null) return [];
    
    final restaurantId = restaurantResponse['id'];
    
    // Obtener órdenes del restaurante
    final ordersResponse = await SupabaseConfig.client
        .from('orders')
        .select('''
          *,
          users!orders_user_id_fkey(id, name, email, phone),
          delivery_agents:users!orders_delivery_agent_id_fkey(id, name, phone, email),
          order_items(
            *,
            products(name, price)
          )
        ''')
        .eq('restaurant_id', restaurantId)
        .order('created_at', ascending: false);

    return ordersResponse.map((json) => DoaOrder.fromJson(json)).toList();
  }

  /// Obtener órdenes para repartidor
  Future<List<DoaOrder>> _fetchDeliveryAgentOrders() async {
    // Órdenes confirmadas sin repartidor asignado (disponibles)
    final availableOrdersResponse = await SupabaseConfig.client
        .from('orders')
        .select('''
          *,
          users!orders_user_id_fkey(id, name, email, phone),
          restaurants(name, logo_url),
          order_items(
            *,
            products(name, price)
          )
        ''')
        .eq('status', OrderStatus.confirmed.toString())
        .isFilter('delivery_agent_id', null)
        .order('created_at', ascending: false);

    // Órdenes asignadas a este repartidor
    final assignedOrdersResponse = await SupabaseConfig.client
        .from('orders')
        .select('''
          *,
          users!orders_user_id_fkey(id, name, email, phone),
          restaurants(name, logo_url),
          order_items(
            *,
            products(name, price)
          )
        ''')
        .eq('delivery_agent_id', _currentUserId!)
        .order('created_at', ascending: false);

    final availableOrders = availableOrdersResponse.map((json) => DoaOrder.fromJson(json)).toList();
    final assignedOrders = assignedOrdersResponse.map((json) => DoaOrder.fromJson(json)).toList();
    
    return [...availableOrders, ...assignedOrders];
  }

  /// Obtener órdenes para cliente
  Future<List<DoaOrder>> _fetchClientOrders() async {
    final ordersResponse = await SupabaseConfig.client
        .from('orders')
        .select('''
          *,
          restaurants(name, logo_url),
          delivery_agents:users!orders_delivery_agent_id_fkey(id, name, phone, email),
          order_items(
            *,
            products(name, price)
          )
        ''')
        .eq('user_id', _currentUserId!)
        .order('created_at', ascending: false);

    return ordersResponse.map((json) => DoaOrder.fromJson(json)).toList();
  }

  /// Obtener todas las órdenes (admin)
  Future<List<DoaOrder>> _fetchAllOrders() async {
    final ordersResponse = await SupabaseConfig.client
        .from('orders')
        .select('''
          *,
          users!orders_user_id_fkey(id, name, email, phone),
          restaurants(name, logo_url),
          delivery_agents:users!orders_delivery_agent_id_fkey(id, name, phone, email),
          order_items(
            *,
            products(name, price)
          )
        ''')
        .order('created_at', ascending: false);

    return ordersResponse.map((json) => DoaOrder.fromJson(json)).toList();
  }
  
  /// Cargar restaurantes iniciales para establecer baseline
  Future<void> _loadInitialRestaurants() async {
    try {
      // CRÍTICO: Obtener TODOS los restaurantes aprobados (online Y offline)
      // para poder detectar cambios de estado correctamente
      final restaurants = await DoaRepartosService.getRestaurants(status: 'approved');
      _cachedRestaurants = restaurants;
      _cachedRestaurantOnlineStatus = {
        for (var restaurant in restaurants) restaurant.id: restaurant.online
      };
    } catch (e) {
      debugPrint('❌ [POLLING] Error cargando restaurantes iniciales: $e');
    }
  }
  
  /// Verificar cambios en restaurantes con control de respaldo
  Future<void> _checkForRestaurantChanges() async {
    try {
      // Evitar consultas innecesarias cuando Realtime está saludable
      if (!_isBackupMode && _cachedRestaurants.isNotEmpty) {
        return;
      }

      // CRÍTICO: Obtener TODOS los restaurantes aprobados (online Y offline)
      final currentRestaurants = await DoaRepartosService.getRestaurants(status: 'approved');

      if (_isBackupMode || _cachedRestaurants.isEmpty) {
        final hasChanges = await _detectRestaurantStatusChanges(currentRestaurants);

        if (hasChanges) {
          _restaurantsUpdatedController.add(null);
        }

        // Actualizar cache cuando se usa en respaldo o bootstrap inicial
        _cachedRestaurants = currentRestaurants;
        _cachedRestaurantOnlineStatus = {
          for (var restaurant in currentRestaurants) restaurant.id: restaurant.online
        };
      }
    } catch (e) {
      debugPrint('❌ [POLLING] Error verificando restaurantes: $e');
    }
  }
  
  /// Detectar cambios de estado online en restaurantes (retorna si hubo cambios)
  Future<bool> _detectRestaurantStatusChanges(List<DoaRestaurant> currentRestaurants) async {
    bool hasChanges = false;
    
    for (var currentRestaurant in currentRestaurants) {
      final previousStatus = _cachedRestaurantOnlineStatus[currentRestaurant.id];
      
      if (previousStatus != null && previousStatus != currentRestaurant.online) {
        hasChanges = true;
      }
    }

    return hasChanges;
  }

  /// Detener el servicio de polling
  void stop() {
    _isActive = false;
    _isBackupMode = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _lastRealtimeEvent = null;
    _cachedOrders.clear();
    _cachedOrderStatuses.clear();
    _cachedRestaurants.clear();
    _cachedRestaurantOnlineStatus.clear();
  }

  /// Verificar si el servicio está activo
  bool get isActive => _isActive;
  
  /// Verificar si está en modo respaldo
  bool get isInBackupMode => _isBackupMode;
  
  /// Obtener intervalo actual
  int get currentInterval => _currentInterval;
  
  /// Obtener usuario actual
  String? get currentUserId => _currentUserId;
  
  /// Obtener rol actual
  UserRole? get currentUserRole => _currentUserRole;
  
  /// Obtener estado del servicio
  Map<String, dynamic> get status => {
    'isActive': _isActive,
    'isBackupMode': _isBackupMode,
    'currentInterval': _currentInterval,
    'lastRealtimeEvent': _lastRealtimeEvent?.toString(),
    'cachedOrdersCount': _cachedOrders.length,
    'cachedRestaurantsCount': _cachedRestaurants.length,
  };
}