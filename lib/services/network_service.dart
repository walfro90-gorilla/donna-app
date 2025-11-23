import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';

/// Servicio para detectar y monitorear el estado de la conexión de red
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  // Stream para cambios de conectividad
  final StreamController<NetworkStatus> _networkStatusController = 
      StreamController<NetworkStatus>.broadcast();
  
  Stream<NetworkStatus> get networkStatusStream => _networkStatusController.stream;
  
  // Estado actual de la red
  NetworkStatus _currentStatus = NetworkStatus.unknown;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _pingTimer;
  
  NetworkStatus get currentStatus => _currentStatus;
  bool get isConnected => _currentStatus == NetworkStatus.connected;
  bool get isDisconnected => _currentStatus == NetworkStatus.disconnected;

  /// Inicializar el servicio de monitoreo de red
  Future<void> initialize() async {
    debugPrint('🌐 [NETWORK] Inicializando servicio de red...');
    
    try {
      // Verificar estado inicial
      await _checkInitialConnectivity();
      
      // Escuchar cambios de conectividad
      _connectivitySubscription = Connectivity()
          .onConnectivityChanged
          .listen(_handleConnectivityChange);
      
      // Iniciar ping periódico para verificación real de internet (no en web)
      if (!kIsWeb) {
        _startPeriodicPing();
      }
      
      debugPrint('✅ [NETWORK] Servicio de red inicializado - Estado: $_currentStatus');
      
    } catch (e) {
      debugPrint('❌ [NETWORK] Error inicializando servicio: $e');
      _updateStatus(NetworkStatus.unknown);
    }
  }

  /// Verificar conectividad inicial
  Future<void> _checkInitialConnectivity() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    await _validateConnection(connectivityResults);
  }

  /// Manejar cambios de conectividad
  void _handleConnectivityChange(List<ConnectivityResult> results) async {
    debugPrint('🌐 [NETWORK] Cambio de conectividad detectado: $results');
    await _validateConnection(results);
  }

  /// Validar conexión real con ping
  Future<void> _validateConnection(List<ConnectivityResult> connectivityResults) async {
    if (connectivityResults.contains(ConnectivityResult.none) || connectivityResults.isEmpty) {
      _updateStatus(NetworkStatus.disconnected);
      return;
    }
    
    // Verificar conexión real con ping
    final hasRealConnection = await _pingTest();
    
    if (hasRealConnection) {
      _updateStatus(NetworkStatus.connected);
    } else {
      _updateStatus(NetworkStatus.limited); // Conexión local pero sin internet
    }
  }

  /// Hacer ping para verificar conexión real a internet
  Future<bool> _pingTest() async {
    try {
      // En web evitamos usar InternetAddress.lookup (no soportado) y confiamos en connectivity_plus
      if (kIsWeb) {
        debugPrint('🌐 [NETWORK] Web detected: omitiendo ping real y confiando en conectividad del navegador');
        return true; // tratar como conectado si hay conectividad a nivel dispositivo
      }

      // Intentar múltiples servidores para mejor confiabilidad (solo mobile/desktop)
      final List<String> testServers = [
        'google.com',
        'cloudflare.com', 
        '8.8.8.8',
      ];
      
      for (String server in testServers) {
        try {
          final result = await InternetAddress.lookup(server)
              .timeout(const Duration(seconds: 5));
          
          if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
            debugPrint('✅ [NETWORK] Ping exitoso a $server');
            return true;
          }
        } catch (e) {
          debugPrint('⚠️ [NETWORK] Ping falló a $server: $e');
          continue;
        }
      }
      
      debugPrint('❌ [NETWORK] Todos los pings fallaron');
      return false;
      
    } catch (e) {
      debugPrint('❌ [NETWORK] Error en ping test: $e');
      return false;
    }
  }

  /// Iniciar ping periódico cada 30 segundos
  void _startPeriodicPing() {
    _pingTimer?.cancel();
    
    _pingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (timer) async {
        if (_currentStatus != NetworkStatus.disconnected) {
          final connectivityResults = await Connectivity().checkConnectivity();
          await _validateConnection(connectivityResults);
        }
      },
    );
    
    debugPrint('🔄 [NETWORK] Ping periódico iniciado (cada 30 segundos)');
  }

  /// Actualizar estado y notificar cambios
  void _updateStatus(NetworkStatus newStatus) {
    if (_currentStatus != newStatus) {
      final previousStatus = _currentStatus;
      _currentStatus = newStatus;
      
      debugPrint('🌐 [NETWORK] ===== CAMBIO DE ESTADO DE RED =====');
      debugPrint('🔄 [NETWORK] Estado: $previousStatus → $newStatus');
      
      // Notificar cambio
      _networkStatusController.add(newStatus);
      
      // Log específico para cambios importantes
      switch (newStatus) {
        case NetworkStatus.connected:
          debugPrint('✅ [NETWORK] 🌐 INTERNET DISPONIBLE - Servicios en tiempo real pueden funcionar');
          break;
        case NetworkStatus.disconnected:
          debugPrint('❌ [NETWORK] 📵 SIN CONEXIÓN - Cambiando a modo offline');
          break;
        case NetworkStatus.limited:
          debugPrint('⚠️ [NETWORK] 📶 CONEXIÓN LIMITADA - WiFi/datos conectados pero sin internet');
          break;
        case NetworkStatus.unknown:
          debugPrint('❓ [NETWORK] ❔ ESTADO DESCONOCIDO - Verificando...');
          break;
      }
    }
  }

  /// Verificar conexión manual (para usar en la app)
  Future<bool> checkConnection() async {
    debugPrint('🔍 [NETWORK] Verificación manual de conexión iniciada...');
    
    final connectivityResults = await Connectivity().checkConnectivity();
    await _validateConnection(connectivityResults);
    
    debugPrint('🔍 [NETWORK] Verificación completada - Estado: $_currentStatus');
    return isConnected;
  }

  /// Obtener detalles del estado de conexión
  Future<NetworkDetails> getConnectionDetails() async {
    final connectivityResults = await Connectivity().checkConnectivity();
    final hasInternet = await _pingTest();
    
    return NetworkDetails(
      connectivityResults: connectivityResults,
      hasInternet: hasInternet,
      status: _currentStatus,
      timestamp: DateTime.now(),
    );
  }

  /// Cerrar el servicio
  void dispose() {
    debugPrint('🔄 [NETWORK] Cerrando servicio de red...');
    
    _connectivitySubscription?.cancel();
    _pingTimer?.cancel();
    _networkStatusController.close();
    
    debugPrint('✅ [NETWORK] Servicio de red cerrado');
  }
}

/// Estados posibles de la conexión de red
enum NetworkStatus {
  connected,    // Internet disponible
  disconnected, // Sin conexión
  limited,      // Conectado a WiFi/datos pero sin internet
  unknown,      // Estado desconocido
}

/// Detalles completos del estado de red
class NetworkDetails {
  final List<ConnectivityResult> connectivityResults;
  final bool hasInternet;
  final NetworkStatus status;
  final DateTime timestamp;

  NetworkDetails({
    required this.connectivityResults,
    required this.hasInternet,
    required this.status,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'NetworkDetails(connectivity: $connectivityResults, '
           'hasInternet: $hasInternet, status: $status, time: $timestamp)';
  }
}

/// Widget para mostrar el estado de la conexión
class NetworkStatusIndicator extends StatelessWidget {
  final NetworkStatus status;
  final VoidCallback? onTap;

  const NetworkStatusIndicator({
    super.key,
    required this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    String text;

    switch (status) {
      case NetworkStatus.connected:
        color = Colors.green;
        icon = Icons.wifi;
        text = 'Online';
        break;
      case NetworkStatus.limited:
        color = Colors.orange;
        icon = Icons.wifi_off;
        text = 'Limited';
        break;
      case NetworkStatus.disconnected:
        color = Colors.red;
        icon = Icons.signal_wifi_off;
        text = 'Offline';
        break;
      case NetworkStatus.unknown:
        color = Colors.grey;
        icon = Icons.help_outline;
        text = 'Unknown';
        break;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}