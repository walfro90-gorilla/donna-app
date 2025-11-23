import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/screens/delivery/delivery_order_detail_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_balance_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class MyDeliveriesScreen extends StatefulWidget {
  const MyDeliveriesScreen({super.key});

  @override
  State<MyDeliveriesScreen> createState() => _MyDeliveriesScreenState();
}

class _MyDeliveriesScreenState extends State<MyDeliveriesScreen> {
  List<Map<String, dynamic>> myDeliveries = [];
  bool isLoading = true;
  String? errorMessage;
  RealtimeNotificationService? _realtimeService;
  StreamSubscription<List<DoaOrder>>? _ordersSubscription;
  Timer? _refreshTimer;
  bool _isServiceInitialized = false;
  bool _isUpdatingStatus = false;

  @override
  void initState() {
    super.initState();
    debugPrint('🔥*-*-*-*-*-*-*-*-START DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-*-*🔥');
    debugPrint('🚚 [DELIVERY DASHBOARD] ===== INICIALIZANDO DASHBOARD REPARTIDOR =====');
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol del usuario ANTES de inicializar CUALQUIER COSA
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldContinue = await _verifyUserRole();
      if (shouldContinue) {
        debugPrint('✅ [DELIVERY] Usuario verificado, iniciando servicios...');
        await _initializeRealtimeService();
        await _loadMyDeliveries();
        _startPeriodicRefresh();
      } else {
        debugPrint('❌ [DELIVERY] Usuario NO verificado, NO iniciando servicios');
      }
    });
  }
  
  @override
  void dispose() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START DELIVERY DISPOSE*-*-*-*-*-*-*-*🔥');
    debugPrint('🧹 [DELIVERY DASHBOARD] ===== LIMPIANDO DASHBOARD REPARTIDOR =====');
    
    _refreshTimer?.cancel();
    _cleanupRealtimeService();
    
    debugPrint('✅ [DELIVERY] Dashboard del repartidor limpiado exitosamente');
    debugPrint('🔥*-*-*-*-*-*-END DELIVERY DISPOSE*-*-*-*-*-*-🔥');
    super.dispose();
  }
  
  /// Verificar que el usuario actual sea un repartidor
  Future<bool> _verifyUserRole() async {
    try {
      debugPrint('🔍 [DELIVERY] ===== VERIFICANDO TIPO DE USUARIO =====');
      
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [DELIVERY] Usuario no autenticado');
        debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('👤 [DELIVERY] Usuario ID: ${user!.id}');
      debugPrint('📧 [DELIVERY] Usuario Email: ${user.email}');
      
      // Verificar rol del usuario en la BD (normalizado a enum)
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();
          
      final userRole = userData['role'] as String?;
      final enumRole = UserRole.fromString(userRole ?? '');
      debugPrint('👑 [DELIVERY] Usuario Role: $userRole -> enum=${enumRole.name}');
      
      if (enumRole != UserRole.delivery_agent) {
        debugPrint('❌ [DELIVERY] ===== ERROR CRÍTICO: USUARIO NO ES REPARTIDOR =====');
        debugPrint('❌ [DELIVERY] Usuario role(raw): $userRole, role(normalizado): ${enumRole.name}, pero dashboard es para repartidor');
        debugPrint('❌ [DELIVERY] ⚠️ CANCELANDO TODA INICIALIZACIÓN DE DASHBOARD ⚠️');
        debugPrint('❌ [DELIVERY] NO se ejecutarán timers, servicios ni cargas de datos');
        
        // Mostrar error al usuario
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: Dashboard incorrecto para tu rol: ${userRole ?? 'desconocido'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        
        debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
        return false;
      }
      
      debugPrint('✅ [DELIVERY] ===== USUARIO REPARTIDOR VERIFICADO =====');
      debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return true;
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error verificando rol de usuario: $e');
      debugPrint('🔥*-*-*-*-*-*-END DELIVERY DASHBOARD DEBUG*-*-*-*-*-*-🔥');
      return false;
    }
  }
  
  /// Inicializar servicio de tiempo real por usuario
  Future<void> _initializeRealtimeService() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        debugPrint('❌ [DELIVERY REALTIME] Usuario no autenticado');
        return;
      }
      
      debugPrint('🎯 [DELIVERY REALTIME] ===== INICIALIZANDO SERVICIO TIEMPO REAL =====');
      debugPrint('👤 [DELIVERY REALTIME] Usuario: ${user.email} (${user.id})');
      
      // Crear instancia del servicio por usuario
      _realtimeService = RealtimeNotificationService.forUser(user.id);
      
      // Inicializar el servicio
      await _realtimeService!.initialize();
      _isServiceInitialized = true;
      
      // Suscribirse a las órdenes del repartidor usando clientActiveOrders
      _ordersSubscription = _realtimeService!.clientActiveOrders.listen(
        (orders) {
          debugPrint('📡 [DELIVERY REALTIME] Órdenes recibidas: ${orders.length}');
          if (mounted) {
            _loadMyDeliveries();
          }
        },
        onError: (error) {
          debugPrint('❌ [DELIVERY REALTIME] Error en stream: $error');
        },
      );
      
      debugPrint('✅ [DELIVERY REALTIME] Servicio inicializado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY REALTIME] Error inicializando servicio: $e');
    }
  }
  
  /// Limpiar servicio de tiempo real
  Future<void> _cleanupRealtimeService() async {
    try {
      debugPrint('🧹 [DELIVERY REALTIME] ===== LIMPIANDO SERVICIO =====');
      
      await _ordersSubscription?.cancel();
      _ordersSubscription = null;
      
      if (_realtimeService != null) {
        await _realtimeService!.dispose();
        _realtimeService = null;
      }
      
      _isServiceInitialized = false;
      debugPrint('✅ [DELIVERY REALTIME] Servicio limpiado exitosamente');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY REALTIME] Error limpiando servicio: $e');
    }
  }

  // ====== DIRECCIONES Y MAPAS ======
  List<double>? _tryParseLatLng(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final matches = RegExp(r'(-?\d+(?:\.\d+)?)').allMatches(raw);
    if (matches.length < 2) return null;
    try {
      final lat = double.parse(matches.elementAt(0).group(0)!);
      final lng = double.parse(matches.elementAt(1).group(0)!);
      return [lat, lng];
    } catch (_) {
      return null;
    }
  }

  Uri _buildGoogleMapsDirectionsUri({String? address, double? lat, double? lng}) {
    String destination;
    if (lat != null && lng != null) {
      destination = '$lat,$lng';
    } else if (address != null && address.trim().isNotEmpty) {
      destination = Uri.encodeComponent(address);
    } else {
      destination = '';
    }
    final params = {
      'api': '1',
      'destination': destination,
      'travelmode': 'driving',
    };
    final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
    return Uri.parse('https://www.google.com/maps/dir/?$query');
  }

  Future<void> _openDirectionsToRestaurant(Map<String, dynamic> delivery) async {
    final restaurant = delivery['restaurants'] as Map<String, dynamic>?;
    final address = restaurant != null ? (restaurant['address']?.toString() ?? '') : '';
    final uri = _buildGoogleMapsDirectionsUri(address: address);
    await _launchUriExternal(uri);
  }

  Future<void> _openDirectionsToClient(Map<String, dynamic> delivery) async {
    // Prefer explicit numeric columns if present
    final dLat = (delivery['delivery_lat'] as num?)?.toDouble();
    final dLon = (delivery['delivery_lon'] as num?)?.toDouble();
    if (dLat != null && dLon != null) {
      final uri = _buildGoogleMapsDirectionsUri(lat: dLat, lng: dLon);
      await _launchUriExternal(uri);
      return;
    }
    // Fallback: parse legacy delivery_latlng string or address text
    final raw = delivery['delivery_latlng']?.toString();
    final parsed = _tryParseLatLng(raw);
    final address = delivery['delivery_address']?.toString();
    final uri = parsed != null
        ? _buildGoogleMapsDirectionsUri(lat: parsed[0], lng: parsed[1])
        : _buildGoogleMapsDirectionsUri(address: address);
    await _launchUriExternal(uri);
  }

  Future<void> _launchUriExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        // fallback: open in browser tab
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir Google Maps: $e')),
        );
      }
    }
  }
  
  /// Iniciar refresh periódico cada 30 segundos
  void _startPeriodicRefresh() {
    debugPrint('🔥*-*-*-*-*-*-*-*-START PERIODIC REFRESH SETUP*-*-*-*-*-*-*-*🔥');
    
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && _isServiceInitialized) {
        debugPrint('🔄 [DELIVERY] Auto-refresh periódico...');
        _loadMyDeliveries();
      }
    });
    
    debugPrint('✅ [DELIVERY] Timer de refresh periódico configurado exitosamente');
    debugPrint('🔥*-*-*-*-*-*-END PERIODIC REFRESH SETUP*-*-*-*-*-*-🔥');
  }

  Future<void> _loadMyDeliveries() async {
    debugPrint('🔥*-*-*-*-*-*-*-*-START LOAD DELIVERIES*-*-*-*-*-*-*-*🔥');
    
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      debugPrint('🚚 [DELIVERY] ===== CARGANDO ENTREGAS DEL REPARTIDOR =====');
      
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ [DELIVERY] Usuario no autenticado');
        throw Exception('Usuario no autenticado');
      }
      
      debugPrint('👤 [DELIVERY] Cargando entregas para usuario: ${currentUser.email} (${currentUser.id})');

      // ✅ VERIFICACIÓN DE SEGURIDAD: Solo si el usuario es repartidor (normalizado)
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', currentUser.id)
          .single();
          
      final userRole = userData['role'] as String?;
      final enumRole = UserRole.fromString(userRole ?? '');
      debugPrint('🔍 [DELIVERY] Verificando rol: $userRole -> enum=${enumRole.name}');
      
      if (enumRole != UserRole.delivery_agent) {
        debugPrint('❌ [DELIVERY] ACCESO DENEGADO: Usuario no es repartidor');
        throw Exception('Acceso denegado: Este dashboard es solo para repartidores');
      }
      
      // Debugging: ver todas las órdenes del usuario actual
      final debugResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status, delivery_agent_id')
          .eq('delivery_agent_id', currentUser.id);
      
      debugPrint('🔍 [DELIVERY] All orders for user ${currentUser.id}: $debugResponse');
      
      // Obtener todos los pedidos asignados a este repartidor (cualquier estado)
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            restaurants (
              name,
              address,
              phone
            )
          ''')
          .eq('delivery_agent_id', currentUser.id)
          .order('created_at', ascending: false);

      debugPrint('📦 [DELIVERY] My deliveries response: $response');

      if (response is List) {
        setState(() {
          myDeliveries = List<Map<String, dynamic>>.from(response);
          isLoading = false;
        });
        debugPrint('✅ [DELIVERY] Loaded ${myDeliveries.length} my deliveries');
        
        // Mostrar detalles de las entregas cargadas
        for (var delivery in myDeliveries) {
          debugPrint('📦 [DELIVERY] - Entrega #${delivery['id'].toString().substring(0, 8)}: ${delivery['status']}');
        }
      }
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error loading my deliveries: $e');
      setState(() {
        errorMessage = 'Error al cargar entregas: $e';
        isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error cargando entregas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      debugPrint('🔥*-*-*-*-*-*-END LOAD DELIVERIES*-*-*-*-*-*-🔥');
    }
  }

  Future<void> _updateDeliveryStatus(String orderId, String newStatus) async {
    // Evitar dobles taps / llamadas concurrentes
    if (_isUpdatingStatus) {
      print('⏳ [DELIVERY] Ignorando tap duplicado, update en curso...');
      return;
    }
    _isUpdatingStatus = true;
    try {
      print('📝 [DELIVERY] Updating delivery status: $orderId -> $newStatus');
      
      // Usar OrderStatusHelper para tracking automático
      final user = SupabaseConfig.client.auth.currentUser;
      final success = await OrderStatusHelper.updateOrderStatus(
        orderId, 
        newStatus, 
        user?.id
      );
      
      if (!success) {
        throw Exception('Failed to update order status');
      }

      print('✅ [DELIVERY] Status updated successfully with tracking');
      
      if (mounted) {
        String message;
        switch (newStatus) {
          case 'delivered':
          case 'entregado':
            message = '¡Pedido entregado correctamente!';
            break;
          case 'on_the_way':
          case 'en_camino':
            message = '¡Pedido recogido del restaurante, en camino al cliente!';
            break;
          default:
            message = 'Estado actualizado';
        }
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
        
        // Recargar la lista
        _loadMyDeliveries();
      }
    } catch (e) {
      print('❌ [DELIVERY] Error updating delivery status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar estado: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isUpdatingStatus = false;
    }
  }

  /// Mostrar diálogo para confirmar código antes de marcar como entregado
  Future<void> _showConfirmCodeDialog(Map<String, dynamic> delivery) async {
    final TextEditingController codeController = TextEditingController();
    bool isValidating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.pin, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Código de Confirmación'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Solicita al cliente el código de 3 dígitos para confirmar la entrega:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                    ),
                    decoration: InputDecoration(
                      hintText: '000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterText: '',
                    ),
                    maxLength: 3,
                    enabled: !isValidating,
                  ),
                  if (isValidating) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text('Validando código...'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isValidating ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isValidating ? null : () async {
                    final code = codeController.text.trim();
                    if (code.length != 3) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('El código debe tener 3 dígitos'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    setState(() => isValidating = true);

                    try {
                      final isValid = await OrderStatusHelper.validateConfirmCode(
                        delivery['id'], 
                        code
                      );

                      if (isValid) {
                        // Código correcto, marcar como entregado
                        Navigator.of(context).pop();
                        await _updateDeliveryStatus(delivery['id'], 'delivered');
                      } else {
                        setState(() => isValidating = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Código incorrecto. Verifica con el cliente.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        codeController.clear();
                      }
                    } catch (e) {
                      setState(() => isValidating = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error validando código: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Confirmar Entrega'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Entregas activas: todas las que no están completadas, canceladas o entregadas
    final activeDeliveries = myDeliveries.where((order) => 
      !['delivered', 'entregado', 'canceled', 'cancelado'].contains(order['status'])
    ).toList();
    
    // Entregas completadas: solo las entregadas
    final completedDeliveries = myDeliveries.where((order) => 
      ['delivered', 'entregado'].contains(order['status'])
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Entregas'),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // No mostrar botón de navegación hacia atrás
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMyDeliveries,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header con estadísticas
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.1),
            child: Row(
              children: [
                _buildStatCard('En Camino', activeDeliveries.length, Colors.orange),
                const SizedBox(width: 16),
                _buildStatCard('Completadas', completedDeliveries.length, Colors.green),
              ],
            ),
          ),
          
          // Contenido principal
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(
                              'Error al cargar entregas',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              errorMessage!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.red,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadMyDeliveries,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : myDeliveries.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.local_shipping, size: 48, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No tienes entregas asignadas',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Ve a "Pedidos Disponibles" para tomar un pedido',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : DefaultTabController(
                            length: 2,
                            child: Column(
                              children: [
                                const TabBar(
                                  tabs: [
                                    Tab(text: 'En Camino', icon: Icon(Icons.local_shipping)),
                                    Tab(text: 'Completadas', icon: Icon(Icons.check_circle)),
                                  ],
                                ),
                                Expanded(
                                  child: TabBarView(
                                    children: [
                                      _buildDeliveryList(activeDeliveries, isActive: true),
                                      _buildDeliveryList(completedDeliveries, isActive: false),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color.withValues(alpha: 0.8),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryList(List<Map<String, dynamic>> deliveries, {required bool isActive}) {
    if (deliveries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.local_shipping : Icons.check_circle,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isActive ? 'No hay entregas en camino' : 'No hay entregas completadas',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMyDeliveries,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: deliveries.length,
        itemBuilder: (context, index) {
          final delivery = deliveries[index];
          return _buildDeliveryCard(delivery, isActive: isActive);
        },
      ),
    );
  }

  Widget _buildDeliveryCard(Map<String, dynamic> delivery, {required bool isActive}) {
    final restaurant = delivery['restaurants'] ?? {};
    final orderItems = delivery['items'] as List? ?? [];
    final totalAmount = (delivery['total_amount'] ?? 0.0).toDouble();
    final createdAt = DateTime.parse(delivery['created_at']);
    final status = delivery['status'] as String;
    
    // Determinar color y texto del estado basado en el estado real
    Color statusColor;
    String statusText;
    
    switch (status) {
      case 'ready_for_pickup':
        statusColor = Colors.blue;
        statusText = 'LISTO PARA RECOGER';
        break;
      case 'assigned':
        statusColor = Colors.amber;
        statusText = 'ASIGNADO - IR AL RESTAURANTE';
        break;
      case 'on_the_way':
      case 'en_camino':
        statusColor = Colors.orange;
        statusText = 'EN CAMINO';
        break;
      case 'delivered':
      case 'entregado':
        statusColor = Colors.green;
        statusText = 'ENTREGADO';
        break;
      default:
        statusColor = Colors.grey;
        statusText = status.toUpperCase();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // Navegar al detalle del pedido
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeliveryOrderDetailScreen(delivery: delivery),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
        children: [
          // Header del pedido
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt, color: statusColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${delivery['id'].toString().substring(0, 8)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatDateTime(createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${totalAmount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Detalles del pedido
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Información del restaurante (para pedidos que requieren recoger)
                if (status == 'assigned' || status == 'ready_for_pickup') ...[
                  Row(
                    children: [
                      const Icon(Icons.store, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          restaurant['name'] ?? 'Restaurante desconocido',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          restaurant['address'] ?? 'Dirección no especificada',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const SizedBox(width: 28),
                      TextButton.icon(
                        onPressed: () => _openDirectionsToRestaurant(delivery),
                        icon: const Icon(Icons.directions, color: Colors.blue, size: 18),
                        label: const Text('Ruta al restaurante'),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                
                // Dirección de entrega al cliente (siempre visible)
                Row(
                  children: [
                    Icon(
                      Icons.home,
                      color: status == 'on_the_way' || status == 'en_camino' ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dirección del cliente',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            delivery['delivery_address'] ?? 'Dirección no especificada',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (status == 'on_the_way' || status == 'en_camino')
                  Row(
                    children: [
                      const SizedBox(width: 28),
                      TextButton.icon(
                        onPressed: () => _openDirectionsToClient(delivery),
                        icon: const Icon(Icons.directions, color: Colors.green, size: 18),
                        label: const Text('Ruta al cliente'),
                      ),
                    ],
                  ),
                
                const SizedBox(height: 12),
                
                // Botones de acción (solo para entregas activas)
                if (isActive) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            // TODO: Llamar al cliente
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Función de llamada próximamente')),
                            );
                          },
                          icon: const Icon(Icons.phone, size: 18),
                          label: const Text('Llamar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildActionButton(delivery, status),
                      ),
                    ],
                  ),
                ],
                
                // Información adicional para entregas completadas
                if (!isActive && delivery['delivery_time'] != null) ...[
                  const Divider(),
                  Row(
                    children: [
                      const Icon(Icons.schedule, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Entregado: ${_formatDateTime(DateTime.parse(delivery['delivery_time']))}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      )
    );
  }

  Widget _buildActionButton(Map<String, dynamic> delivery, String status) {
    switch (status) {
      case 'assigned':
        // SOLO mostrar botón si el restaurante NO ha marcado el pedido como listo
        return Container(); // No mostrar botón hasta que el restaurante marque listo
      case 'ready_for_pickup':
        // Mostrar código pickup en lugar del botón
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.purple.shade400, Colors.purple.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.qr_code, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Código Pickup',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                delivery['pickup_code']?.toString() ?? '----',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4.0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mostrar al restaurante',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        );
      case 'on_the_way':
      case 'en_camino':
        return ElevatedButton.icon(
          onPressed: () => _showConfirmCodeDialog(delivery),
          icon: const Icon(Icons.pin, color: Colors.white, size: 18),
          label: const Text(
            'Confirmar Código',
            style: TextStyle(color: Colors.white),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
          ),
        );
      default:
        return Container(); // No mostrar botón para estados no manejados
    }
  }

  String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);

    if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} horas';
    } else {
    return '${local.day}/${local.month} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
    }
  }

}