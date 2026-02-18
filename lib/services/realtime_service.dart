import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/alert_sound_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:doa_repartos/services/polling_service.dart';

/// Servicio robusto de notificaciones en tiempo real para la app
class RealtimeNotificationService {
  // ✅ SINGLETON ELIMINADO - Cada usuario tiene su propia instancia
  static final Map<String, RealtimeNotificationService> _instances = {};
  
  factory RealtimeNotificationService.forUser(String userId) {
    debugPrint('🎯 [REALTIME] Obteniendo instancia para usuario: $userId');
    if (!_instances.containsKey(userId)) {
      debugPrint('🆕 [REALTIME] Creando nueva instancia para usuario: $userId');
      _instances[userId] = RealtimeNotificationService._internal(userId);
    }
    return _instances[userId]!;
  }
  
  // Método para compatibilidad hacia atrás - detecta usuario actual automáticamente
  factory RealtimeNotificationService() {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('⚠️ [REALTIME] Sin usuario autenticado, creando instancia temporal');
      return RealtimeNotificationService._internal('guest-${DateTime.now().millisecondsSinceEpoch}');
    }
    return RealtimeNotificationService.forUser(user!.id);
  }
  
  RealtimeNotificationService._internal(this._userId);

  // ✅ ID del usuario dueño de esta instancia
  final String _userId;
  
  // Stream controllers ÚNICOS para cada usuario
  StreamController<DoaOrder> _newOrdersController = StreamController<DoaOrder>.broadcast();
  StreamController<DoaOrder> _orderUpdatesController = StreamController<DoaOrder>.broadcast();
  final StreamController<DoaOrder> _confirmedOrdersController = StreamController<DoaOrder>.broadcast();
  StreamController<void> _refreshDataController = StreamController<void>.broadcast();
  StreamController<void> _restaurantsUpdatedController = StreamController<void>.broadcast();
  // Nuevo: cambios en repartidores (online/offline)
  StreamController<void> _couriersUpdatedController = StreamController<void>.broadcast();
  StreamController<List<DoaOrder>> _clientActiveOrdersController = StreamController<List<DoaOrder>>.broadcast();

  // Streams públicos con validación de apertura
  Stream<DoaOrder> get newOrders {
    _ensureStreamControllersOpen();
    return _newOrdersController.stream;
  }
  
  Stream<DoaOrder> get orderUpdates {
    _ensureStreamControllersOpen();
    return _orderUpdatesController.stream;
  }
  
  Stream<DoaOrder> get confirmedOrders {
    _ensureStreamControllersOpen();
    return _confirmedOrdersController.stream;
  }
  
  Stream<void> get refreshData {
    _ensureStreamControllersOpen();
    return _refreshDataController.stream;
  }
  
  Stream<void> get restaurantsUpdated {
    _ensureStreamControllersOpen();
    return _restaurantsUpdatedController.stream;
  }
  
  // Nuevo: stream público para cambios de repartidores
  Stream<void> get couriersUpdated {
    _ensureStreamControllersOpen();
    return _couriersUpdatedController.stream;
  }
  
  Stream<List<DoaOrder>> get clientActiveOrders {
    _ensureStreamControllersOpen();
    return _clientActiveOrdersController.stream;
  }

  // Estado del servicio
  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _restaurantsChannel;
  // Nuevo: canal para perfiles de repartidores
  RealtimeChannel? _couriersChannel;
  bool _isInitialized = false;
  
  // Control de conexión y reconexión
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  DateTime? _lastHeartbeat;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 5;
  
  // Estado de conexión de red
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _hasInternetConnection = true;
  
  // Estado del WebSocket
  bool _isWebSocketConnected = false;
  DateTime? _lastRealtimeEvent;
  
  /// Detecta si el WebSocket está funcionando correctamente
  bool get isRealtimeHealthy => 
      _isInitialized && 
      _isWebSocketConnected && 
      (_lastRealtimeEvent == null || 
       DateTime.now().difference(_lastRealtimeEvent!).inMinutes < 5);

  /// Inicializar el servicio de notificaciones en tiempo real robusto
  Future<void> initialize() async {
    // debugPrint('🚀 [REALTIME] ===== INICIALIZANDO SERVICIO PARA USUARIO $_userId =====');
    
    try {
      // ✅ VERIFICAR que este servicio corresponde al usuario actual
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [REALTIME] Usuario no autenticado, no inicializando');
        return;
      }
      
      if (user!.id != _userId) {
        debugPrint('⚠️ [REALTIME] ADVERTENCIA: Usuario cambió de $_userId a ${user.id}');
        debugPrint('⚠️ [REALTIME] Esta instancia ya no es válida para el usuario actual');
        return;
      }
      
      // debugPrint('👤 [REALTIME] Usuario autenticado: ${user.email}');
      
      // Inicializar monitoreo de conectividad
      await _initializeConnectivityMonitoring();
      
      // ✅ Solo limpiar conexiones de ESTA instancia (no globales)
      await _disposeChannels();
      
      // Crear conexiones WebSocket
      await _createRealtimeChannels();
      
      // Inicializar heartbeat para monitoreo de conexión
      _startHeartbeatMonitoring();
      
      _isInitialized = true;
      _reconnectAttempts = 0;
      
      // Recrear stream controllers si están cerrados
      _ensureStreamControllersOpen();
      
      // Cargar órdenes activas iniciales
      await _updateClientActiveOrders();
      
      // debugPrint('✅ [REALTIME] ===== SERVICIO INICIALIZADO EXITOSAMENTE =====');
      
    } catch (e) {
      debugPrint('❌ [REALTIME] Error crítico al inicializar: $e');
      _isInitialized = false;
      _scheduleReconnect();
    }
  }
  
  /// Inicializar monitoreo de conectividad de red
  Future<void> _initializeConnectivityMonitoring() async {
    // Verificar estado inicial de conectividad
    final connectivityResults = await Connectivity().checkConnectivity();
    _hasInternetConnection = !connectivityResults.contains(ConnectivityResult.none);
    
    // debugPrint('🌐 [REALTIME] Estado inicial de red: $_hasInternetConnection');
    
    // Escuchar cambios de conectividad
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        final wasConnected = _hasInternetConnection;
        _hasInternetConnection = !results.contains(ConnectivityResult.none);
        
        // debugPrint('🌐 [REALTIME] Cambio de conectividad: $wasConnected -> $_hasInternetConnection');
        
        if (!wasConnected && _hasInternetConnection) {
          // Reconectarse cuando se recupera la conexión
          debugPrint('🔄 [REALTIME] Internet recuperado, reconectando...');
          _scheduleReconnect();
        } else if (wasConnected && !_hasInternetConnection) {
          // Marcar WebSocket como desconectado
          _isWebSocketConnected = false;
          debugPrint('❌ [REALTIME] Internet perdido, WebSocket desconectado');
        }
      },
    );
  }
  
  /// Crear canales de tiempo real con configuración robusta
  Future<void> _createRealtimeChannels() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // ✅ Canales únicos por usuario para evitar interferencia
    final ordersChannelName = 'orders-realtime-$_userId-$timestamp';
    final restaurantsChannelName = 'restaurants-realtime-$_userId-$timestamp';
    final couriersChannelName = 'couriers-realtime-$_userId-$timestamp';
    
    // debugPrint('📡 [REALTIME] Creando canales: $ordersChannelName y $restaurantsChannelName');
    
    // Canal para órdenes con manejo robusto
    _ordersChannel = SupabaseConfig.client
        .channel(ordersChannelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'orders',
          callback: _handleNewOrder,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          callback: _handleOrderUpdate,
        );
    
    // Canal para restaurantes
    _restaurantsChannel = SupabaseConfig.client
        .channel(restaurantsChannelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'restaurants',
          callback: _handleRestaurantUpdate,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'restaurants',
          callback: _handleRestaurantUpdate,
        );
    
    // Canal para repartidores (escuchar cambios de status en delivery_agent_profiles)
    _couriersChannel = SupabaseConfig.client
        .channel(couriersChannelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'delivery_agent_profiles',
          callback: _handleCourierUpdate,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'delivery_agent_profiles',
          callback: _handleCourierUpdate,
        );
    
    // Suscribirse con manejo de errores
    try {
      // debugPrint('📡 [REALTIME] Suscribiendo canales...');
      
      await _ordersChannel?.subscribe();
      await _restaurantsChannel?.subscribe();
      await _couriersChannel?.subscribe();
      
      // Marcar WebSocket como conectado
      _isWebSocketConnected = true;
      _lastHeartbeat = DateTime.now();
      // Notificar actividad a PollingService para que se mantenga en modo normal
      try {
        PollingService().notifyRealtimeActivity();
      } catch (_) {}
      
      // debugPrint('✅ [REALTIME] Canales suscritos exitosamente');
      
    } catch (e) {
      debugPrint('❌ [REALTIME] Error suscribiendo canales: $e');
      _isWebSocketConnected = false;
      rethrow;
    }
  }
  
  /// Inicializar monitoreo de heartbeat para detectar desconexiones
  void _startHeartbeatMonitoring() {
    _heartbeatTimer?.cancel();
    
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30), // Check cada 30 segundos
      (timer) {
        _checkConnectionHealth();
      },
    );
    
    // debugPrint('💓 [REALTIME] Heartbeat iniciado - verificación cada 30 segundos');
  }
  
  /// Verificar salud de la conexión
  void _checkConnectionHealth() {
    final now = DateTime.now();
    
    // Verificar si han llegado eventos recientes
    final timeSinceLastEvent = _lastRealtimeEvent != null 
        ? now.difference(_lastRealtimeEvent!).inMinutes 
        : 999;
    
    // Verificar si la conexión está "zombie" (sin eventos por mucho tiempo)
    if (_isWebSocketConnected && timeSinceLastEvent > 10) {
      debugPrint('⚠️ [REALTIME] Posible conexión zombie - Sin eventos por $timeSinceLastEvent minutos');
      
      // Forzar reconexión si parece desconectado
      if (timeSinceLastEvent > 15) {
        debugPrint('🔄 [REALTIME] Conexión parece muerta, forzando reconexión...');
        _isWebSocketConnected = false;
        _scheduleReconnect();
        return;
      }
    }
    // Informar actividad a PollingService cuando el WebSocket está saludable
    if (_isWebSocketConnected) {
      try {
        PollingService().notifyRealtimeActivity();
      } catch (_) {}
    }
    
    // Log de estado
    // debugPrint('💓 [REALTIME] Health check - WebSocket: $_isWebSocketConnected, '
    //            'Último evento: ${timeSinceLastEvent}min atrás, Internet: $_hasInternetConnection');
  }
  
  /// Programar reconexión inteligente
  void _scheduleReconnect() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('❌ [REALTIME] Máximo de intentos de reconexión alcanzado ($maxReconnectAttempts)');
      return;
    }
    
    _reconnectTimer?.cancel();
    
    // Delay exponencial: 2^attempt segundos (2, 4, 8, 16, 32 segundos)
    final delaySeconds = (2 * (_reconnectAttempts + 1)).clamp(2, 60);
    _reconnectAttempts++;
    
    debugPrint('🔄 [REALTIME] Programando reconexión #$_reconnectAttempts en ${delaySeconds}s...');
    
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      if (_hasInternetConnection && !_isWebSocketConnected) {
        debugPrint('🔄 [REALTIME] Ejecutando reconexión #$_reconnectAttempts...');
        await _attemptReconnection();
      } else {
        debugPrint('⏭️ [REALTIME] Saltando reconexión - Internet: $_hasInternetConnection, WS: $_isWebSocketConnected');
      }
    });
  }
  
  /// Intentar reconexión
  Future<void> _attemptReconnection() async {
    try {
      debugPrint('🔄 [REALTIME] Iniciando proceso de reconexión...');
      
      // Limpiar conexiones actuales
      await _disposeChannels();
      
      // Recrear canales
      await _createRealtimeChannels();
      
      // Reiniciar heartbeat
      _startHeartbeatMonitoring();
      
      // Reset contador de intentos en caso de éxito
      _reconnectAttempts = 0;
      
      debugPrint('✅ [REALTIME] Reconexión exitosa');
      
    } catch (e) {
      debugPrint('❌ [REALTIME] Error en reconexión: $e');
      _isWebSocketConnected = false;
      
      // Programar otro intento si no hemos llegado al máximo
      if (_reconnectAttempts < maxReconnectAttempts) {
        _scheduleReconnect();
      }
    }
  }

  /// Manejar nuevas órdenes con registro de actividad
  void _handleNewOrder(PostgresChangePayload payload) async {
    // Registrar actividad de tiempo real
    _lastRealtimeEvent = DateTime.now();
    _isWebSocketConnected = true;
    
    try {
      // debugPrint('🆕 [REALTIME] ===== NUEVA ORDEN DETECTADA =====');
      // debugPrint('📱 [REALTIME] Datos: ${payload.newRecord}');
      
      final orderId = payload.newRecord['id'];
      final restaurantId = payload.newRecord['restaurant_id'];
      final status = payload.newRecord['status'];
      
      // debugPrint('🆔 [REALTIME] Order ID: $orderId, Restaurant: $restaurantId, Status: $status');
      
      if (orderId != null) {
        // Obtener orden completa con reintentos inteligentes
        DoaOrder? order = await _fetchCompleteOrderWithRetries(orderId);
        
        if (order != null) {
          // debugPrint('✅ [REALTIME] ===== ENVIANDO NOTIFICACIÓN =====');
          // debugPrint('📤 [REALTIME] Order: ID=${order.id}, RestaurantID=${order.restaurantId}');
          
          _newOrdersController.add(order);
          _refreshDataController.add(null);
          
          // Sonidos de alerta (gobernados por el rol actual)
          try {
            final statusStr = payload.newRecord['status']?.toString();
            final deliveryAgentId = payload.newRecord['delivery_agent_id'];
            if (statusStr == 'pending') {
              unawaited(AlertSoundService.instance.playRestaurantNewOrder());
            } else if (statusStr == 'confirmed' && deliveryAgentId == null) {
              unawaited(AlertSoundService.instance.playDeliveryNewOrder());
            }
          } catch (_) {}
          
          // Actualizar órdenes activas del cliente
          await _updateClientActiveOrders();
          
          // debugPrint('🔔 [REALTIME] Notificación de nueva orden enviada exitosamente');
          // Señalar actividad de realtime al PollingService
          try { PollingService().notifyRealtimeActivity(); } catch (_) {}
        } else {
          debugPrint('❌ [REALTIME] FALLO: No se pudo obtener la orden después de varios intentos');
        }
      }
    } catch (e) {
      debugPrint('❌ [REALTIME] Error procesando nueva orden: $e');
    }
  }

  /// Manejar actualizaciones de órdenes
  void _handleOrderUpdate(PostgresChangePayload payload) async {
    // Registrar actividad de tiempo real
    _lastRealtimeEvent = DateTime.now();
    _isWebSocketConnected = true;
    
    try {
      final oldRecord = payload.oldRecord;
      final newRecord = payload.newRecord;
      
      // debugPrint('🔄 [REALTIME] ===== ORDEN ACTUALIZADA =====');
      // debugPrint('📱 [REALTIME] Orden ID: ${newRecord['id']}');
      // debugPrint('🔄 [REALTIME] Status: ${oldRecord?['status']} -> ${newRecord['status']}');
      
      final orderId = newRecord['id'];
      if (orderId != null) {
        // Pequeño delay para consistencia de base de datos
        await Future.delayed(const Duration(milliseconds: 300));
        
        // Obtener orden completa con reintentos
        final order = await _fetchCompleteOrderWithRetries(orderId);
        if (order != null) {
          // debugPrint('✅ [REALTIME] Orden actualizada obtenida: ${order.id}');
          
          _orderUpdatesController.add(order);
          _refreshDataController.add(null);
          
          // Sonido de confirmación para repartidores si aplica
          try {
            if (oldRecord?['status'] == 'pending' && newRecord['status'] == 'confirmed') {
              _confirmedOrdersController.add(order);
              unawaited(AlertSoundService.instance.playDeliveryNewOrder());
              debugPrint('🚚 [REALTIME] Orden confirmada notificada a repartidores');
            }
          } catch (_) {}
          
          // Actualizar órdenes activas del cliente
          await _updateClientActiveOrders();
          
          // debugPrint('🔔 [REALTIME] Notificación de actualización enviada');
          // Señalar actividad de realtime al PollingService
          try { PollingService().notifyRealtimeActivity(); } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('❌ [REALTIME] Error procesando actualización de orden: $e');
    }
  }

  /// Manejar actualizaciones de restaurantes (online/offline)
  void _handleRestaurantUpdate(PostgresChangePayload payload) async {
    // Registrar actividad de tiempo real
    _lastRealtimeEvent = DateTime.now();
    _isWebSocketConnected = true;
    
    try {
      final oldRecord = payload.oldRecord;
      final newRecord = payload.newRecord;
      
      // debugPrint('🏪 [REALTIME] ===== RESTAURANTE ACTUALIZADO =====');
      // debugPrint('📱 [REALTIME] Restaurante ID: ${newRecord['id']}');
      // debugPrint('🔄 [REALTIME] Online: ${oldRecord?['online']} -> ${newRecord['online']}');
      // debugPrint('🔄 [REALTIME] Status: ${oldRecord?['status']} -> ${newRecord['status']}');
      
      // Detectar cambios significativos
      final onlineChanged = oldRecord?['online'] != newRecord['online'];
      final statusChanged = oldRecord?['status'] != newRecord['status'];
      
      if (onlineChanged || statusChanged) {
        // debugPrint('✅ [REALTIME] Cambio crítico detectado - Notificando dashboards');
        
        // Notificar inmediatamente para actualización de listas
        _restaurantsUpdatedController.add(null);
        _refreshDataController.add(null);
        
        // debugPrint('🔔 [REALTIME] 🎯 NOTIFICACIÓN CRÍTICA: Restaurantes actualizados');
        // Señalar actividad de realtime al PollingService
        try { PollingService().notifyRealtimeActivity(); } catch (_) {}
      } else {
        debugPrint('ℹ️ [REALTIME] Cambio menor en restaurante - no crítico');
      }
      
    } catch (e) {
      debugPrint('❌ [REALTIME] Error procesando actualización de restaurante: $e');
    }
  }
  
  /// Manejar actualizaciones de repartidores (online/offline)
  void _handleCourierUpdate(PostgresChangePayload payload) async {
    // Registrar actividad de tiempo real
    _lastRealtimeEvent = DateTime.now();
    _isWebSocketConnected = true;
    
    try {
      final oldRecord = payload.oldRecord;
      final newRecord = payload.newRecord;
      
      // debugPrint('🚚 [REALTIME] ===== REPARTIDOR ACTUALIZADO =====');
      // debugPrint('👤 [REALTIME] user_id: ${newRecord['user_id']}');
      // debugPrint('🔄 [REALTIME] status: ${oldRecord?['status']} -> ${newRecord['status']}');
      // debugPrint('🔄 [REALTIME] account_state: ${oldRecord?['account_state']} -> ${newRecord['account_state']}');
      
      final statusChanged = oldRecord?['status'] != newRecord['status'];
      final stateChanged = oldRecord?['account_state'] != newRecord['account_state'];
      
      if (statusChanged || stateChanged) {
        // Notificar a dashboards de cliente para reevaluar disponibilidad (RPC hasActiveCouriers)
        _couriersUpdatedController.add(null);
        _refreshDataController.add(null);
        
        // debugPrint('🔔 [REALTIME] 🎯 NOTIFICACIÓN CRÍTICA: Repartidores actualizados');
        try { PollingService().notifyRealtimeActivity(); } catch (_) {}
      } else {
        debugPrint('ℹ️ [REALTIME] Cambio menor en repartidor - no crítico');
      }
    } catch (e) {
      debugPrint('❌ [REALTIME] Error procesando actualización de repartidor: $e');
    }
  }

  /// Obtener orden completa con reintentos inteligentes usando RPC optimizado
  Future<DoaOrder?> _fetchCompleteOrderWithRetries(String orderId) async {
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint('🔄 [REALTIME] Obteniendo orden completa via RPC (intento $attempt/3)...');
        
        // Delay progresivo para dar tiempo a la base de datos
        if (attempt > 1) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
        
        // ✅ Usar RPC optimizado que devuelve JSON completo
        final response = await SupabaseConfig.client
            .rpc('get_order_full_details', params: {'order_id_param': orderId});

        if (response == null) {
          debugPrint('⚠️ [REALTIME] RPC devolvió null para orden $orderId');
          continue;
        }

        // La nueva función devuelve directamente jsonb, convertir a Map
        final jsonData = Map<String, dynamic>.from(response as Map);
        final order = DoaOrder.fromJson(jsonData);
        
        debugPrint('✅ [REALTIME] Orden completa obtenida exitosamente via RPC en intento $attempt');
        debugPrint('✅ [REALTIME] Delivery agent: ${order.deliveryAgent?.name ?? 'N/A'}');
        return order;
        
      } catch (e) {
        debugPrint('⚠️ [REALTIME] Error en intento $attempt: $e');
        
        if (attempt == 3) {
          debugPrint('❌ [REALTIME] FALLO FINAL: No se pudo obtener orden después de 3 intentos');
          return null;
        }
      }
    }
    return null;
  }

  /// Actualizar órdenes activas del cliente en tiempo real
  Future<void> _updateClientActiveOrders() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [REALTIME] Usuario no autenticado para órdenes activas');
        return;
      }
      
      // ✅ VERIFICAR que este servicio pertenece al usuario actual
      if (user!.id != _userId) {
        debugPrint('⚠️ [REALTIME] Esta instancia es para $_userId pero usuario actual es ${user.id}');
        debugPrint('⚠️ [REALTIME] No actualizando órdenes - instancia no válida');
        return;
      }
      
      // ✅ Usar RPC optimizado que devuelve array JSON completo
      final response = await SupabaseConfig.client
          .rpc('get_client_active_orders', params: {'client_id_param': user.id});

      if (response == null) {
        debugPrint('⚠️ [TRACKER] RPC devolvió null');
        _clientActiveOrdersController.add([]);
        return;
      }

      // La nueva función devuelve jsonb (array de objetos completos)
      final ordersJson = response as List;
      final orders = ordersJson
          .map((json) => DoaOrder.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('📊 [TRACKER] ✅ ${orders.length} órdenes activas encontradas via RPC');
      
      // Log delivery agents
      for (final order in orders) {
        if (order.deliveryAgentId != null) {
          debugPrint('📋 [TRACKER] Orden ${order.id.substring(0, 8)}: Delivery=${order.deliveryAgent?.name ?? 'NULL'}');
        }
      }
      
      // Verificar que el stream controller esté abierto antes de emitir
      if (_clientActiveOrdersController.isClosed) {
        debugPrint('❌ [TRACKER] CRÍTICO: Stream controller está cerrado, recreando...');
        _ensureStreamControllersOpen();
      }
      
      // Verificar de nuevo después de intentar recrear
      if (_clientActiveOrdersController.isClosed) {
        debugPrint('🚨 [TRACKER] STREAM SIGUE CERRADO - NO SE PUEDEN EMITIR DATOS');
        return;
      }
      
      // Emitir las órdenes al stream con manejo de errores
      try {
        _clientActiveOrdersController.add(orders);
      } catch (e) {
        debugPrint('❌ [TRACKER] ERROR EMITIENDO AL STREAM: $e');
      }
      
    } catch (e) {
      debugPrint('❌ [TRACKER] ERROR CRÍTICO actualizando órdenes activas: $e');
      debugPrint('❌ [TRACKER] Stack trace: ${StackTrace.current}');
    }
  }

  /// Método público para forzar actualización de órdenes del cliente
  Future<void> refreshClientActiveOrders() async {
    debugPrint('🔄 [TRACKER] ===== REFRESH MANUAL INICIADO PARA USUARIO $_userId =====');
    debugPrint('🔄 [TRACKER] Service inicializado: $_isInitialized');
    debugPrint('🔄 [TRACKER] WebSocket conectado: $_isWebSocketConnected');
    debugPrint('🔄 [TRACKER] Stream controller abierto: ${!_clientActiveOrdersController.isClosed}');
    
    // Asegurar que los stream controllers estén abiertos
    _ensureStreamControllersOpen();
    
    // Si el servicio no está inicializado, inicializarlo
    if (!_isInitialized) {
      debugPrint('⚠️ [TRACKER] Servicio no inicializado, inicializando...');
      await initialize();
    }
    
    await _updateClientActiveOrders();
    
    debugPrint('✅ [TRACKER] ===== REFRESH MANUAL COMPLETADO =====');
  }

  /// Limpiar solo los canales WebSocket
  Future<void> _disposeChannels() async {
    try {
      if (_ordersChannel != null) {
        await _ordersChannel?.unsubscribe();
        _ordersChannel = null;
      }
      
      if (_restaurantsChannel != null) {
        await _restaurantsChannel?.unsubscribe();
        _restaurantsChannel = null;
      }
      
      if (_couriersChannel != null) {
        await _couriersChannel?.unsubscribe();
        _couriersChannel = null;
      }
      
      _isWebSocketConnected = false;
      debugPrint('✅ [REALTIME] Canales WebSocket cerrados');
    } catch (e) {
      debugPrint('⚠️ [REALTIME] Error cerrando canales: $e');
      _ordersChannel = null;
      _restaurantsChannel = null;
      _couriersChannel = null;
      _isWebSocketConnected = false;
    }
  }
  
  /// Limpiar y cerrar el servicio completo
  Future<void> dispose() async {
    debugPrint('🔄 [REALTIME] Cerrando servicio completo...');
    
    // Cancelar timers
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
    
    // Cerrar suscripción de conectividad
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    
    // Cerrar canales WebSocket
    await _disposeChannels();
    
    // ✅ NO CERRAR STREAM CONTROLLERS - Los necesitamos para el tiempo real
    // await _clientActiveOrdersController.close();
    debugPrint('🔧 [REALTIME] Stream controllers mantenidos abiertos para tiempo real');
    debugPrint('🔧 [REALTIME] Instancia para usuario $_userId cerrada sin afectar otras instancias');
    
    // Reset estado
    _isInitialized = false;
    _reconnectAttempts = 0;
    _lastHeartbeat = null;
    _lastRealtimeEvent = null;
    
    debugPrint('✅ [REALTIME] Servicio cerrado completamente');
  }
  
  /// Asegurar que los stream controllers estén abiertos
  void _ensureStreamControllersOpen() {
    if (_clientActiveOrdersController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de órdenes activas del cliente...');
      _clientActiveOrdersController = StreamController<List<DoaOrder>>.broadcast();
    }
    
    if (_newOrdersController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de nuevas órdenes...');
      _newOrdersController = StreamController<DoaOrder>.broadcast();
    }
    
    if (_orderUpdatesController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de actualizaciones...');
      _orderUpdatesController = StreamController<DoaOrder>.broadcast();
    }
    
    if (_refreshDataController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de refresh...');
      _refreshDataController = StreamController<void>.broadcast();
    }
    
    if (_restaurantsUpdatedController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de restaurantes...');
      _restaurantsUpdatedController = StreamController<void>.broadcast();
    }
    
    if (_couriersUpdatedController.isClosed) {
      debugPrint('🔧 [REALTIME] Recreando stream controller de repartidores...');
      _couriersUpdatedController = StreamController<void>.broadcast();
    }
    
    debugPrint('✅ [REALTIME] Todos los stream controllers están abiertos');
  }
  
  /// Verificar si el servicio está activo
  bool get isInitialized => _isInitialized;
  
  /// Obtener el ID del usuario dueño de esta instancia
  String get userId => _userId;
  
  /// Limpiar instancia específica cuando el usuario hace logout
  static void clearUserInstance(String userId) {
    debugPrint('🗑️ [REALTIME] Eliminando instancia para usuario: $userId');
    final instance = _instances.remove(userId);
    if (instance != null) {
      instance.dispose();
      debugPrint('✅ [REALTIME] Instancia de $userId eliminada correctamente');
    }
  }
  
  /// Limpiar todas las instancias (logout global)
  static void clearAllInstances() {
    debugPrint('🗑️ [REALTIME] Eliminando todas las instancias');
    for (final instance in _instances.values) {
      instance.dispose();
    }
    _instances.clear();
    debugPrint('✅ [REALTIME] Todas las instancias eliminadas');
  }
}

/// Widget para mostrar notificaciones toast
class NotificationToast {
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: backgroundColor ?? Theme.of(context).colorScheme.primary,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => overlayEntry.remove(),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Remover automáticamente después del tiempo especificado
    Timer(duration, () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }
}