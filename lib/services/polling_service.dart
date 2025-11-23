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
    debugPrint('🎯 [POLLING] ===== INICIALIZANDO POLLING INTELIGENTE =====');
    
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
    
    debugPrint('✅ [POLLING] Servicio inteligente inicializado');
    debugPrint('👤 [POLLING] Usuario: $userId, Rol: $userRole');
    debugPrint('⏱️ [POLLING] Intervalo inicial: ${_currentInterval}s');
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
    
    debugPrint('🎯 [POLLING] Timer iniciado con intervalo ${_currentInterval}s');
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
      
      if (_isBackupMode) {
        debugPrint('🆘 [POLLING] ===== MODO RESPALDO ACTIVADO =====');
        debugPrint('🔄 [POLLING] Realtime inactivo - Polling tomará control');
      } else {
        debugPrint('✅ [POLLING] ===== VOLVIENDO A MODO NORMAL =====');
        debugPrint('📡 [POLLING] Realtime funcionando - Polling en modo pasivo');
      }
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
      debugPrint('⏱️ [POLLING] Ajustando intervalo: ${_currentInterval}s → ${newInterval}s');
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
    debugPrint('🔄 [POLLING] Reiniciando timer con intervalo ${_currentInterval}s');
    _pollingTimer?.cancel();
    _startIntelligentPolling();
  }
  
  /// Registrar evento de realtime para controlar el respaldo
  void notifyRealtimeActivity() {
    _lastRealtimeEvent = DateTime.now();
    
    // Si estábamos en modo respaldo, volver a normal
    if (_isBackupMode) {
      debugPrint('📡 [POLLING] Realtime activo detectado - Desactivando respaldo');
      _isBackupMode = false;
    }
  }
  
  /// Verificar todos los cambios (método unificado)
  Future<void> _checkForChanges() async {
    try {
      final stopwatch = Stopwatch()..start();
      
      if (_isBackupMode) {
        debugPrint('🆘 [POLLING] Verificando cambios (MODO RESPALDO)');
      } else {
        debugPrint('🔍 [POLLING] Verificando cambios (modo normal)');
      }
      
      // Verificar órdenes
      await _checkForOrderChanges();
      
      // Verificar restaurantes
      await _checkForRestaurantChanges();
      
      stopwatch.stop();
      debugPrint('⏱️ [POLLING] Verificación completada en ${stopwatch.elapsedMilliseconds}ms');
      
    } catch (e) {
      debugPrint('❌ [POLLING] Error en verificación: $e');
    }
  }

  /// Cargar órdenes iniciales para establecer baseline
  Future<void> _loadInitialOrders() async {
    try {
      debugPrint('📊 [POLLING] Cargando órdenes iniciales...');
      
      final orders = await _fetchOrdersForUser();
      _cachedOrders = orders;
      _cachedOrderStatuses = {
        for (var order in orders) order.id: order.status
      };
      
      debugPrint('✅ [POLLING] ${orders.length} órdenes cargadas en cache inicial');
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

        // Notificar refresh si hay cambios
        if (_hasOrderChanges(currentOrders)) {
          debugPrint('🔄 [POLLING] Cambios detectados - Enviando refresh');
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
      debugPrint('🆕 [POLLING] NUEVA ORDEN DETECTADA: ${newOrder.id.substring(0, 8)}');
      debugPrint('🏪 [POLLING] Restaurante: ${newOrder.restaurantId}');
      debugPrint('👤 [POLLING] Cliente: ${newOrder.user?.name}');
      debugPrint('💰 [POLLING] Total: \$${newOrder.totalAmount}');
      
      // Enviar notificación de nueva orden
      _newOrdersController.add(newOrder);
      
      // Si es para restaurantes y la orden está pendiente
      if (_currentUserRole == UserRole.restaurant && newOrder.status == OrderStatus.pending) {
        debugPrint('🔔 [POLLING] Enviando notificación de nuevo pedido a restaurante');
        // Sonido de alerta para restaurante
        unawaited(AlertSoundService.instance.playRestaurantNewOrder());
      }
      
      // Si es para repartidores y la orden está confirmada
      if (_currentUserRole == UserRole.delivery_agent && newOrder.status == OrderStatus.confirmed) {
        debugPrint('🚚 [POLLING] Enviando notificación de orden confirmada a repartidor');
        _confirmedOrdersController.add(newOrder);
        // Sonido de alerta para repartidor
        unawaited(AlertSoundService.instance.playDeliveryNewOrder());
      }
    }
  }

  /// Detectar actualizaciones de estado
  Future<void> _detectOrderUpdates(List<DoaOrder> currentOrders) async {
    for (var currentOrder in currentOrders) {
      final previousStatus = _cachedOrderStatuses[currentOrder.id];
      
      if (previousStatus != null && previousStatus != currentOrder.status) {
        debugPrint('🔄 [POLLING] CAMBIO DE ESTADO DETECTADO: ${currentOrder.id.substring(0, 8)}');
        debugPrint('📊 [POLLING] Status: $previousStatus -> ${currentOrder.status}');
        
        // Enviar notificación de actualización
        _orderUpdatesController.add(currentOrder);
        
        // Si cambió de pending a confirmed, notificar a repartidores
        if (previousStatus == OrderStatus.pending && 
            currentOrder.status == OrderStatus.confirmed) {
          debugPrint('🚚 [POLLING] Orden confirmada, notificando a repartidores');
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
      debugPrint('🏪 [POLLING] Cargando restaurantes iniciales...');
      
      // CRÍTICO: Obtener TODOS los restaurantes aprobados (online Y offline)
      // para poder detectar cambios de estado correctamente
      final restaurants = await DoaRepartosService.getRestaurants(status: 'approved');
      _cachedRestaurants = restaurants;
      _cachedRestaurantOnlineStatus = {
        for (var restaurant in restaurants) restaurant.id: restaurant.online
      };
      
      debugPrint('✅ [POLLING] ${restaurants.length} restaurantes cargados en cache inicial');
      debugPrint('📊 [POLLING] Online: ${restaurants.where((r) => r.online).length}, Offline: ${restaurants.where((r) => !r.online).length}');
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

      // Solo procesar cambios si estamos en modo respaldo o es verificación inicial
      if (_isBackupMode || _cachedRestaurants.isEmpty) {
        debugPrint('🏪 [POLLING] Verificando restaurantes (${_isBackupMode ? 'RESPALDO' : 'inicial'})');
        debugPrint('📊 [POLLING] Total: ${currentRestaurants.length}, Online: ${currentRestaurants.where((r) => r.online).length}');

        // Detectar cambios de estado
        final hasChanges = await _detectRestaurantStatusChanges(currentRestaurants);

        // Notificar solo si hay cambios
        if (hasChanges) {
          debugPrint('🔔 [POLLING] Cambios en restaurantes - Enviando notificación');
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
        debugPrint('🔄 [POLLING] ===== CAMBIO CRÍTICO DETECTADO =====');
        debugPrint('🏪 [POLLING] Restaurante: ${currentRestaurant.name}');
        debugPrint('📊 [POLLING] Estado: $previousStatus → ${currentRestaurant.online}');
        
        hasChanges = true;
        
        if (currentRestaurant.online) {
          debugPrint('✅ [POLLING] 🟢 ${currentRestaurant.name} → ONLINE');
        } else {
          debugPrint('❌ [POLLING] 🔴 ${currentRestaurant.name} → OFFLINE');
        }
      }
    }
    
    if (!hasChanges && _isBackupMode) {
      debugPrint('🔍 [POLLING] Sin cambios en restaurantes (${currentRestaurants.length} verificados)');
    }
    
    return hasChanges;
  }

  /// Detener el servicio de polling
  void stop() {
    debugPrint('🛑 [POLLING] Deteniendo servicio inteligente...');
    _isActive = false;
    _isBackupMode = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _lastRealtimeEvent = null;
    
    // Limpiar cache
    _cachedOrders.clear();
    _cachedOrderStatuses.clear();
    _cachedRestaurants.clear();
    _cachedRestaurantOnlineStatus.clear();
    
    debugPrint('✅ [POLLING] Servicio inteligente detenido');
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