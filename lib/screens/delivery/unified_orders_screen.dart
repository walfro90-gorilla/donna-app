import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/screens/delivery/delivery_order_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doa_repartos/services/location_tracking_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/services/storage_service.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';

/// Pantalla unificada que muestra TODOS los pedidos relevantes para el repartidor:
/// - Disponibles (sin asignar)
/// - Mis pedidos (asignados, listos, en camino, completados)
/// Todo en un solo listado ordenado por estado y color
class UnifiedOrdersScreen extends StatefulWidget {
  const UnifiedOrdersScreen({super.key});

  @override
  State<UnifiedOrdersScreen> createState() => _UnifiedOrdersScreenState();
}

class _UnifiedOrdersScreenState extends State<UnifiedOrdersScreen> {
  List<Map<String, dynamic>> allOrders = [];
  bool isLoading = true;
  String? errorMessage;
  RealtimeNotificationService? _realtimeService;
  StreamSubscription<List<DoaOrder>>? _ordersSubscription;
  Timer? _refreshTimer;
  bool _isServiceInitialized = false;
  bool _isUpdatingStatus = false;
  DoaUser? _currentAgent;
  bool _canDeliver = true;

  @override
  void initState() {
    super.initState();
    debugPrint('🚚 [UNIFIED] ===== INICIALIZANDO UNIFIED ORDERS SCREEN =====');
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shouldContinue = await _verifyUserRole();
      if (shouldContinue) {
        await _loadOnboardingGate();
        await _initializeRealtimeService();
        await _loadAllOrders();
        _startPeriodicRefresh();
      }
    });
  }
  
  @override
  void dispose() {
    debugPrint('🧹 [UNIFIED] Limpiando unified orders screen...');
    _refreshTimer?.cancel();
    _cleanupRealtimeService();
    super.dispose();
  }
  
  Future<bool> _verifyUserRole() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) return false;
      
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user!.id)
          .single();
          
      final userRole = userData['role'] as String?;
      final enumRole = UserRole.fromString(userRole ?? '');
      
      if (enumRole != UserRole.delivery_agent) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Dashboard incorrecto para tu rol: ${userRole ?? 'desconocido'}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ [UNIFIED] Error verificando rol: $e');
      return false;
    }
  }

  Future<void> _loadOnboardingGate() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      
      Map<String, dynamic>? profile;
      Map<String, dynamic>? userRow;
      
      try {
        profile = await SupabaseConfig.client
            .from('delivery_agent_profiles')
            .select('status, account_state, profile_image_url, id_document_front_url, id_document_back_url, vehicle_photo_url, emergency_contact_name, emergency_contact_phone, user_id')
            .eq('user_id', user.id)
            .maybeSingle();
      } catch (e) {
        debugPrint('⚠️ [UNIFIED] Error consultando perfil: $e');
      }

      try {
        userRow = await SupabaseConfig.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {}

      final merged = <String, dynamic>{
        if (userRow != null) ...userRow!,
        if (profile != null) ...profile!,
      };

      if (merged.isNotEmpty) {
        _currentAgent = DoaUser.fromJson(merged);
        final hasPhoto = (_currentAgent!.profileImageUrl ?? '').isNotEmpty;
        final hasIdFront = (_currentAgent!.idDocumentFrontUrl ?? '').isNotEmpty;
        final hasIdBack = (_currentAgent!.idDocumentBackUrl ?? '').isNotEmpty;
        final hasVehiclePhoto = (_currentAgent!.vehiclePhotoUrl ?? '').isNotEmpty;
        final hasEmergency = (_currentAgent!.emergencyContactName ?? '').isNotEmpty && 
                            (_currentAgent!.emergencyContactPhone ?? '').isNotEmpty;
        final approved = _currentAgent!.accountState == DeliveryAccountState.approved;
        setState(() => _canDeliver = hasPhoto && hasIdFront && hasIdBack && hasVehiclePhoto && hasEmergency && approved);
      }
    } catch (e) {
      debugPrint('⚠️ [UNIFIED] Error verificando onboarding: $e');
      setState(() => _canDeliver = true);
    }
  }
  
  Future<void> _initializeRealtimeService() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      
      _realtimeService = RealtimeNotificationService.forUser(user.id);
      await _realtimeService!.initialize();
      _isServiceInitialized = true;
      
      _ordersSubscription = _realtimeService!.clientActiveOrders.listen(
        (orders) {
          if (mounted) _loadAllOrders();
        },
        onError: (error) {
          debugPrint('❌ [UNIFIED] Error en stream: $error');
        },
      );
      
    } catch (e) {
      debugPrint('❌ [UNIFIED] Error inicializando tiempo real: $e');
    }
  }
  
  Future<void> _cleanupRealtimeService() async {
    await _ordersSubscription?.cancel();
    _ordersSubscription = null;
    
    if (_realtimeService != null) {
      await _realtimeService!.dispose();
      _realtimeService = null;
    }
    
    _isServiceInitialized = false;
  }

  void _startPeriodicRefresh() {
    // 60s: el realtime + my_deliveries timer 30s ya cubren actualizaciones urgentes
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted && _isServiceInitialized) {
        _loadAllOrders();
      }
    });
  }

  Future<void> _loadAllOrders() async {
    try {
      final showLoading = allOrders.isEmpty;
      if (showLoading) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }

      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) throw Exception('Usuario no autenticado');

      debugPrint('🔄 [UNIFIED] Cargando todos los pedidos...');

      // 1. Pedidos disponibles (sin repartidor asignado, ya aceptados por restaurante)
      final availableResponse = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            restaurants (name, address, phone),
            user:user_id (name, phone)
          ''')
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup'])
          .isFilter('delivery_agent_id', null)
          .order('created_at', ascending: false);

      // 2. Mis pedidos asignados (todos los estados)
      final myOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            restaurants (name, address, phone),
            user:user_id (name, phone)
          ''')
          .eq('delivery_agent_id', currentUser.id)
          .order('created_at', ascending: false);

      // Combinar y ordenar por prioridad de estado
      final combinedOrders = [
        ...List<Map<String, dynamic>>.from(availableResponse as List),
        ...List<Map<String, dynamic>>.from(myOrdersResponse as List),
      ];

      // Ordenar por prioridad: disponibles > asignados > listos > en camino > completados
      combinedOrders.sort((a, b) {
        final priorityA = _getStatusPriority(a['status'] as String, a['delivery_agent_id'] == currentUser.id);
        final priorityB = _getStatusPriority(b['status'] as String, b['delivery_agent_id'] == currentUser.id);
        return priorityA.compareTo(priorityB);
      });

      setState(() {
        allOrders = combinedOrders;
        if (showLoading) isLoading = false;
        errorMessage = null;
      });

      debugPrint('✅ [UNIFIED] Cargados ${allOrders.length} pedidos totales');
      
    } catch (e) {
      debugPrint('❌ [UNIFIED] Error cargando pedidos: $e');
      setState(() {
        if (allOrders.isEmpty) {
          errorMessage = 'Error al cargar pedidos: $e';
          isLoading = false;
        }
      });
    }
  }

  int _getStatusPriority(String status, bool isMine) {
    // Prioridad: menor número = más arriba en la lista
    if (!isMine && ['confirmed', 'in_preparation', 'ready_for_pickup'].contains(status)) {
      return 1; // Disponibles (verde claro)
    }
    if (isMine && status == 'assigned') {
      return 2; // Asignado - ir al restaurante (amarillo)
    }
    if (isMine && status == 'ready_for_pickup') {
      return 3; // Listo para recoger (azul)
    }
    if (isMine && (status == 'on_the_way' || status == 'en_camino')) {
      return 4; // En camino (naranja)
    }
    if (isMine && (status == 'delivered' || status == 'entregado')) {
      return 5; // Completado (verde oscuro)
    }
    if (status == 'not_delivered') {
      return 7; // No entregado (rojo)
    }
    if (status == 'canceled' || status == 'cancelled') {
      return 8; // Cancelado (rojo claro)
    }
    return 6; // Otros estados
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      if (!_canDeliver) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Completa tu registro antes de aceptar pedidos'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final ok = await DoaRepartosService.acceptOrder(orderId);
      if (!ok) {
        throw Exception('No fue posible asignar el pedido. Quizá ya no está disponible.');
      }

      try {
        await LocationTrackingService.instance.start(orderId: orderId);
      } catch (e) {
        debugPrint('⚠️ [UNIFIED] Error iniciando tracking: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pedido asignado! Ve al restaurante para recoger'),
            backgroundColor: Colors.green,
          ),
        );
        _loadAllOrders();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al aceptar pedido: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateDeliveryStatus(String orderId, String newStatus) async {
    if (_isUpdatingStatus) return;
    _isUpdatingStatus = true;
    
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      final success = await OrderStatusHelper.updateOrderStatus(
        orderId, 
        newStatus, 
        user?.id
      );
      
      if (!success) throw Exception('Error al actualizar estado');

      if (mounted) {
        String message;
        switch (newStatus) {
          case 'delivered':
          case 'entregado':
            message = '¡Pedido entregado correctamente!';
            break;
          case 'on_the_way':
          case 'en_camino':
            message = '¡Pedido recogido, en camino al cliente!';
            break;
          default:
            message = 'Estado actualizado';
        }
            
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.green),
        );
        _loadAllOrders();
      }
    } catch (e) {
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
              title: const Row(
                children: [
                  Icon(Icons.pin, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Código de Confirmación'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Solicita al cliente el código de 3 dígitos:'),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      counterText: '',
                    ),
                    maxLength: 3,
                    enabled: !isValidating,
                  ),
                  if (isValidating) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
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
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isValidating ? null : () async {
                    final code = codeController.text.trim();
                    if (code.length != 3) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
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
                        Navigator.of(context).pop();
                        await _updateDeliveryStatus(delivery['id'], 'delivered');
                      } else {
                        setState(() => isValidating = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
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
                  child: const Text('Confirmar Entrega'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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
    final params = {'api': '1', 'destination': destination, 'travelmode': 'driving'};
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
    final dLat = (delivery['delivery_lat'] as num?)?.toDouble();
    final dLon = (delivery['delivery_lon'] as num?)?.toDouble();
    if (dLat != null && dLon != null) {
      final uri = _buildGoogleMapsDirectionsUri(lat: dLat, lng: dLon);
      await _launchUriExternal(uri);
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final currentUser = SupabaseConfig.client.auth.currentUser;
    
    // Contar por categorías
    final available = allOrders.where((o) => 
      o['delivery_agent_id'] == null && 
      ['confirmed', 'in_preparation', 'ready_for_pickup'].contains(o['status'])
    ).length;
    
    final assigned = allOrders.where((o) => 
      o['delivery_agent_id'] == currentUser?.id && 
      o['status'] == 'assigned'
    ).length;
    
    final readyPickup = allOrders.where((o) => 
      o['delivery_agent_id'] == currentUser?.id && 
      o['status'] == 'ready_for_pickup'
    ).length;
    
    final onTheWay = allOrders.where((o) => 
      o['delivery_agent_id'] == currentUser?.id && 
      ['on_the_way', 'en_camino'].contains(o['status'])
    ).length;
    
    final completed = allOrders.where((o) => 
      o['delivery_agent_id'] == currentUser?.id && 
      ['delivered', 'entregado'].contains(o['status'])
    ).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadOnboardingGate();
              await _loadAllOrders();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Estadísticas resumidas
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.1),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceEvenly,
              children: [
                _buildMiniStat('Disponibles', available, Colors.green.shade400),
                _buildMiniStat('Asignados', assigned, Colors.amber),
                _buildMiniStat('Listos', readyPickup, Colors.blue),
                _buildMiniStat('En Camino', onTheWay, Colors.orange),
                _buildMiniStat('Completados', completed, Colors.green.shade700),
              ],
            ),
          ),
          
          // Lista unificada
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
                            Text('Error al cargar pedidos', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadAllOrders,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : allOrders.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.grey),
                                SizedBox(height: 16),
                                Text('No hay pedidos disponibles', style: TextStyle(fontSize: 16, color: Colors.grey)),
                                SizedBox(height: 8),
                                Text('Vuelve a revisar en unos minutos', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAllOrders,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: allOrders.length,
                              itemBuilder: (context, index) {
                                final order = allOrders[index];
                                final isMine = order['delivery_agent_id'] == currentUser?.id;
                                return _buildOrderCard(order, isMine);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order, bool isMine) {
    final restaurant = order['restaurants'] ?? {};
    final totalAmount = (order['total_amount'] ?? 0.0).toDouble();
    final createdAt = DateTime.parse(order['created_at']);
    final status = order['status'] as String;
    final currentUser = SupabaseConfig.client.auth.currentUser;
    
    // Determinar color, texto y categoría del estado
    Color statusColor;
    String statusText;
    String categoryLabel;
    
    if (!isMine && ['confirmed', 'in_preparation', 'ready_for_pickup'].contains(status)) {
      statusColor = Colors.green.shade400;
      statusText = 'DISPONIBLE';
      categoryLabel = '🟢 DISPONIBLE';
    } else if (isMine && status == 'assigned') {
      statusColor = Colors.amber;
      statusText = 'ASIGNADO - IR AL RESTAURANTE';
      categoryLabel = '🟡 ASIGNADO';
    } else if (isMine && status == 'ready_for_pickup') {
      statusColor = Colors.blue;
      statusText = 'LISTO PARA RECOGER';
      categoryLabel = '🔵 LISTO';
    } else if (isMine && (status == 'on_the_way' || status == 'en_camino')) {
      statusColor = Colors.orange;
      statusText = 'EN CAMINO';
      categoryLabel = '🟠 EN CAMINO';
    } else if (isMine && (status == 'delivered' || status == 'entregado')) {
      statusColor = Colors.green.shade700;
      statusText = 'ENTREGADO';
      categoryLabel = '🟢 COMPLETADO';
    } else if (status == 'not_delivered') {
      statusColor = Colors.red;
      statusText = 'NO ENTREGADO';
      categoryLabel = '🔴 NO ENTREGADO';
    } else if (status == 'canceled' || status == 'cancelled') {
      statusColor = Colors.red.shade300;
      statusText = 'CANCELADO';
      categoryLabel = '🔴 CANCELADO';
    } else {
      statusColor = Colors.grey;
      statusText = status.toUpperCase();
      categoryLabel = '⚪ OTRO';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 2),
      ),
      child: InkWell(
        onTap: isMine ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => DeliveryOrderDetailScreen(delivery: order),
            ),
          );
        } : null,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Header con categoría visual
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      categoryLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido #${order['id'].toString().substring(0, 8)}',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDateTime(createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${totalAmount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ),
            
            // Detalles del pedido
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Restaurante (siempre visible)
                  Row(
                    children: [
                      const Icon(Icons.store, color: Colors.orange, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          restaurant['name'] ?? 'Restaurante',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                    ],
                  ),

                  // Nombre del cliente (solo en pedidos asignados a este repartidor)
                  if (isMine) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blueGrey, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (order['user'] as Map?)?['name'] ?? 'Cliente',
                            style: TextStyle(fontSize: 13, color: Colors.grey[300]),
                          ),
                        ),
                      ],
                    ),
                  ],
                  
                  // Dirección del restaurante (si es asignado o listo para recoger)
                  if (isMine && (status == 'assigned' || status == 'ready_for_pickup')) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 26),
                        Expanded(
                          child: Text(
                            restaurant['address'] ?? 'Dirección no especificada',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 26),
                        TextButton.icon(
                          onPressed: () => _openDirectionsToRestaurant(order),
                          icon: const Icon(Icons.directions, size: 16),
                          label: const Text('Ruta al restaurante', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                  
                  const SizedBox(height: 8),
                  
                  // Dirección del cliente (siempre visible)
                  Row(
                    children: [
                      Icon(
                        Icons.home,
                        color: (isMine && (status == 'on_the_way' || status == 'en_camino')) 
                            ? Colors.green 
                            : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entregar en:',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              order['delivery_address'] ?? 'Dirección no especificada',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  if (isMine && (status == 'on_the_way' || status == 'en_camino'))
                    Row(
                      children: [
                        const SizedBox(width: 26),
                        TextButton.icon(
                          onPressed: () => _openDirectionsToClient(order),
                          icon: const Icon(Icons.directions, size: 16, color: Colors.green),
                          label: const Text('Ruta al cliente', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                  // Pago en efectivo: mostrar monto y cambio
                  if (isMine && order['payment_method'] == 'cash') ...[
                    const SizedBox(height: 8),
                    Builder(builder: (context) {
                      final cashAmount = (order['cash_amount'] as num?)?.toDouble();
                      final change = cashAmount != null ? cashAmount - totalAmount : null;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.shade900.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade600, width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.payments_outlined, color: Colors.greenAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Pago en efectivo', style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
                                  if (cashAmount != null)
                                    Text(
                                      'Paga con: \$${cashAmount.toStringAsFixed(2)}  →  Cambio: \$${change!.toStringAsFixed(2)}',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    )
                                  else
                                    const Text('Monto exacto no especificado', style: TextStyle(fontSize: 12, color: Colors.white70)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 12),

                  // Botones de acción
                  _buildActionButtons(order, status, isMine),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> order, String status, bool isMine) {
    if (!isMine) {
      // Pedido disponible - botón para aceptar
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _canDeliver ? () => _acceptOrder(order['id']) : null,
          icon: const Icon(Icons.check, color: Colors.white, size: 18),
          label: const Text('Aceptar Pedido', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            disabledBackgroundColor: Colors.grey,
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
      );
    }
    
    // Pedido mío - botones según estado
    if (status == 'assigned') {
      return const SizedBox.shrink(); // Esperar a que restaurante marque listo
    }
    
    if (status == 'ready_for_pickup') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade400, Colors.purple.shade600],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code, color: Colors.white, size: 18),
                SizedBox(width: 6),
                Text('Código Pickup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              order['pickup_code']?.toString() ?? '----',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Mostrar al restaurante',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
    }
    
    if (status == 'on_the_way' || status == 'en_camino') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final clientPhone = (order['user'] as Map?)?['phone']?.toString();
                    if (clientPhone != null && clientPhone.isNotEmpty) {
                      await _launchUriExternal(Uri(scheme: 'tel', path: clientPhone));
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('El cliente no tiene teléfono registrado')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.phone, size: 16),
                  label: const Text('Llamar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showConfirmCodeDialog(order),
                  icon: const Icon(Icons.pin, color: Colors.white, size: 16),
                  label: const Text('Confirmar', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showNotDeliveredBottomSheet(order),
              icon: const Icon(Icons.report_gmailerrorred, color: Colors.red, size: 16),
              label: const Text(
                'Marcar como NO Entregado',
                style: TextStyle(fontSize: 13),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ),
        ],
      );
    }
    
    return const SizedBox.shrink();
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

  void _showNotDeliveredBottomSheet(Map<String, dynamic> order) {
    String? selectedReason;
    final TextEditingController notesController = TextEditingController();
    PlatformFile? selectedFile;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.report, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            'Marcar pedido como NO entregado',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Motivo', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _reasonChip(
                            setState,
                            selectedReason,
                            'client_no_show',
                            'Cliente no salió',
                            Icons.door_front_door,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                          _reasonChip(
                            setState,
                            selectedReason,
                            'fake_address',
                            'Dirección falsa/incorrecta',
                            Icons.location_off,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                          _reasonChip(
                            setState,
                            selectedReason,
                            'other',
                            'Otro',
                            Icons.help_outline,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ImageUploadField(
                        label: 'Foto de evidencia',
                        icon: Icons.camera_alt,
                        isRequired: true,
                        helpText: 'Toma o sube una foto como evidencia (obligatorio).',
                        onImageSelected: (file) {
                          setState(() => selectedFile = file);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                          hintText: 'Ej. Toqué varias veces, llamé y no contestaron',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (selectedReason == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Selecciona un motivo'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }
                                  if (selectedFile == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('La foto de evidencia es obligatoria'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  setState(() => isSubmitting = true);
                                  try {
                                    debugPrint('🚫 [NOT_DELIVERED] Iniciando proceso...');
                                    final userId = SupabaseConfig.client.auth.currentUser?.id;
                                    if (userId == null) {
                                      throw 'Sesión expirada. Vuelve a iniciar sesión.';
                                    }
                                    final orderId = order['id'].toString();
                                    debugPrint('🚫 [NOT_DELIVERED] OrderId: $orderId, Reason: $selectedReason');
                                    
                                    // 1) Subir evidencia a storage
                                    debugPrint('📸 [NOT_DELIVERED] Subiendo evidencia...');
                                    final photoUrl = await StorageService.uploadDeliveryEvidence(
                                      userId: userId,
                                      orderId: orderId,
                                      file: selectedFile!,
                                    );
                                    if (photoUrl == null) {
                                      throw 'No se pudo subir la evidencia';
                                    }
                                    debugPrint('✅ [NOT_DELIVERED] Evidencia subida: $photoUrl');

                                    // 2) Llamar RPC para marcar no entregado
                                    debugPrint('📞 [NOT_DELIVERED] Llamando RPC...');
                                    final ok = await DoaRepartosService.markOrderNotDelivered(
                                      orderId: orderId,
                                      deliveryAgentId: userId,
                                      reason: selectedReason!,
                                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                      photoUrl: photoUrl,
                                    );
                                    debugPrint('📦 [NOT_DELIVERED] RPC result: $ok');

                                    if (ok && mounted) {
                                      debugPrint('✅ [NOT_DELIVERED] Operación exitosa');
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Pedido marcado como NO entregado'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      // Stop tracking and refresh list
                                      LocationTrackingService.instance.stop();
                                      await _loadAllOrders();
                                    } else {
                                      debugPrint('❌ [NOT_DELIVERED] RPC retornó false');
                                      throw 'La operación no pudo completarse';
                                    }
                                  } catch (e, stack) {
                                    debugPrint('❌ [NOT_DELIVERED] Error: $e');
                                    debugPrint('❌ [NOT_DELIVERED] Stack: $stack');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => isSubmitting = false);
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.report_gmailerrorred, color: Colors.white),
                          label: Text(isSubmitting ? 'Enviando...' : 'Confirmar NO Entrega'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _reasonChip(
      void Function(void Function()) setState,
      String? selected,
      String value,
      String label,
      IconData icon,
      void Function(String?) onSelect,
      ) {
    final bool isSelected = selected == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[700]),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => onSelect(isSelected ? null : value),
      selectedColor: Colors.red,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey[700],
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}
