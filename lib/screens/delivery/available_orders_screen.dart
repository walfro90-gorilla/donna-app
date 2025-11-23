import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/navigation_service.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';
import 'package:doa_repartos/services/location_tracking_service.dart';
import 'package:doa_repartos/services/onboarding_notification_service.dart';

class AvailableOrdersScreen extends StatefulWidget {
  const AvailableOrdersScreen({super.key});

  @override
  State<AvailableOrdersScreen> createState() => _AvailableOrdersScreenState();
}

class _AvailableOrdersScreenState extends State<AvailableOrdersScreen> {
  List<Map<String, dynamic>> availableOrders = [];
  bool isLoading = true;
  String? errorMessage;
  StreamSubscription<DoaOrder>? _confirmedOrdersSubscription;
  StreamSubscription<DoaOrder>? _orderUpdatesSubscription;
  StreamSubscription<void>? _refreshDataSubscription;
  Timer? _refreshTimer;
    DoaUser? _currentAgent;
    bool _canDeliver = true; // set after onboarding check

  @override
  void initState() {
    super.initState();
    debugPrint('🚚 [DELIVERY] ===== INICIALIZANDO AVAILABLE ORDERS SCREEN =====');
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol del usuario al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _verifyUserRole();
    });
    
    _loadOnboardingGate().then((_) => _loadAvailableOrders());
    _startAutoRefresh();
    // Configurar sistema de notificaciones híbrido
    Future.delayed(const Duration(milliseconds: 500), () {
      _setupRealtimeNotifications();
    });
  }

  Future<void> _loadOnboardingGate() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) return;
      // Preferir delivery_agent_profiles para un gate preciso (docs + aprobación admin)
      Map<String, dynamic>? profile;
      Map<String, dynamic>? userRow;
      try {
        profile = await SupabaseConfig.client
            .from('delivery_agent_profiles')
            .select('status, account_state, profile_image_url, id_document_front_url, id_document_back_url, vehicle_photo_url, emergency_contact_name, emergency_contact_phone, user_id')
            .eq('user_id', user.id)
            .maybeSingle();
        debugPrint('🗂️ [DELIVERY-GATE] Perfil delivery_agent_profiles: ' 
            'status=' + (profile?['status']?.toString() ?? 'null') +
            ', account_state=' + (profile?['account_state']?.toString() ?? 'null'));
      } catch (e) {
        debugPrint('⚠️ [DELIVERY-GATE] Error consultando delivery_agent_profiles: $e');
      }

      try {
        userRow = await SupabaseConfig.client
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
      } catch (_) {}

      // Si existe una vista consolidada úsala como fallback para campos adicionales
      if (profile == null) {
        try {
          final view = await SupabaseConfig.client
              .from('delivery_agents_view')
              .select('*')
              .or('id.eq.${user.id},user_id.eq.${user.id}')
              .maybeSingle();
          if (view != null) profile = view;
        } catch (_) {}
      }

      final merged = <String, dynamic>{
        if (userRow != null) ...userRow!,
        if (profile != null) ...profile!,
      };

      if (merged.isNotEmpty) {
        _currentAgent = DoaUser.fromJson(merged);
        // Gate explícito: documentos requeridos + aprobación admin
        final hasPhoto = (_currentAgent!.profileImageUrl ?? '').isNotEmpty;
        final hasIdFront = (_currentAgent!.idDocumentFrontUrl ?? '').isNotEmpty;
        final hasIdBack = (_currentAgent!.idDocumentBackUrl ?? '').isNotEmpty;
        final hasVehiclePhoto = (_currentAgent!.vehiclePhotoUrl ?? '').isNotEmpty;
        final hasEmergency = (_currentAgent!.emergencyContactName ?? '').isNotEmpty && (_currentAgent!.emergencyContactPhone ?? '').isNotEmpty;
        final approved = _currentAgent!.accountState == DeliveryAccountState.approved;
        setState(() => _canDeliver = hasPhoto && hasIdFront && hasIdBack && hasVehiclePhoto && hasEmergency && approved);
        debugPrint('🔓 [DELIVERY-GATE] photo=$hasPhoto idFront=$hasIdFront idBack=$hasIdBack vehPhoto=$hasVehiclePhoto emergency=$hasEmergency approved=${approved} -> canDeliver=$_canDeliver');
      }
    } catch (e) {
      debugPrint('⚠️ [DELIVERY] Onboarding gate check failed: $e');
      setState(() => _canDeliver = true); // fail-open
    }
  }
  
  /// Verificar que el usuario actual sea un repartidor (normalizado como en DeliveryMainDashboard)
  Future<void> _verifyUserRole() async {
    try {
      debugPrint('🔍 [DELIVERY] ===== VERIFICANDO TIPO DE USUARIO =====');
      
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [DELIVERY] Usuario no autenticado');
        return;
      }
      
      debugPrint('👤 [DELIVERY] Usuario ID: ${user!.id}');
      debugPrint('📧 [DELIVERY] Usuario Email: ${user.email}');
      
      // Verificar rol del usuario en la BD
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
        debugPrint('❌ [DELIVERY] Evitando carga de datos incorrectos');
        
        // Mostrar error coherente con otras pantallas, sin expulsar la sesión
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: Dashboard incorrecto para tu rol: ${userRole ?? 'desconocido'}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      debugPrint('✅ [DELIVERY] ===== USUARIO REPARTIDOR VERIFICADO =====');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY] Error verificando rol de usuario: $e');
    }
  }

  @override
  void dispose() {
    _confirmedOrdersSubscription?.cancel();
    _orderUpdatesSubscription?.cancel();
    _refreshDataSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Iniciar auto-refresh cada 15 segundos (más frecuente para garantizar tiempo real)
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (!mounted) return;
      // Refrescar gate de onboarding de vez en cuando para reflejar aprobaciones del admin
      if (timer.tick % 2 == 0) {
        // cada 30s
        await _loadOnboardingGate();
      }
      await _loadAvailableOrders();
    });
  }
  
  /// Configurar sistema híbrido: tiempo real + polling garantizado  
  void _setupRealtimeNotifications() async {
    debugPrint('🔄 [DELIVERY] ===== CONFIGURANDO SISTEMA HÍBRIDO TIEMPO REAL =====');
    
    // SIEMPRE usar polling como base, tiempo real como extra
    debugPrint('✅ [DELIVERY] Sistema de polling activo cada 15 segundos');
    
    // Intentar tiempo real solo si hay usuario autenticado
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('⚠️ [DELIVERY] Sin usuario autenticado, usando solo polling');
      return;
    }
    
    debugPrint('👤 [DELIVERY] Usuario autenticado: ${user!.email}');
    
    final realtimeService = RealtimeNotificationService.forUser(user.id);
    
    // Inicializar tiempo real sin bloquear si falla
    try {
      if (!realtimeService.isInitialized) {
        debugPrint('🔄 [DELIVERY] Inicializando tiempo real...');
        await realtimeService.initialize().timeout(const Duration(seconds: 5));
      }
      
      if (realtimeService.isInitialized) {
        debugPrint('✅ [DELIVERY] Tiempo real activo como EXTRA');
        _setupRealtimeListeners(realtimeService);
      } else {
        debugPrint('⚠️ [DELIVERY] Tiempo real no disponible, usando solo polling');
      }
    } catch (e) {
      debugPrint('⚠️ [DELIVERY] Error en tiempo real: $e - usando solo polling');
    }
  }
  
  /// Configurar listeners del servicio de polling (PRINCIPAL)
  void _setupPollingListeners() {
    // Escuchar órdenes confirmadas del polling
    // TODO: Reactivar polling service cuando esté disponible
    /*
    _confirmedOrdersSubscription = _pollingService.confirmedOrders.listen((order) {
      debugPrint('🔔 [DELIVERY-POLLING] Nueva orden confirmada detectada: ${order.id.substring(0, 8)}');
      
      // Actualizar inmediatamente la UI
      if (mounted) {
        _loadAvailableOrders();
        
        // Mostrar notificación toast prominente
        NotificationToast.show(
          context,
          title: '¡NUEVA ORDEN DISPONIBLE! 🚚',
          message: 'Orden #${order.id.substring(0, 8)}\n\$${order.totalAmount.toStringAsFixed(0)} - ${order.restaurant?.name ?? "Restaurante"}',
          icon: Icons.delivery_dining,
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 8),
        );
      }
    });
    */
    
    // TODO: Reactivar polling service cuando esté disponible
    /*
    // Escuchar actualizaciones de pedidos del polling
    _orderUpdatesSubscription = _pollingService.orderUpdates.listen((order) {
      debugPrint('🔄 [DELIVERY-POLLING] Actualización detectada: ${order.id.substring(0, 8)}');
      
      if (mounted) {
        _loadAvailableOrders();
      }
    });
    
    // Escuchar refresh general
    _refreshDataSubscription = _pollingService.refreshData.listen((_) {
      if (mounted) {
        debugPrint('🔄 [DELIVERY-POLLING] Refresh solicitado');
        _loadAvailableOrders();
      }
    });
    */
  }
  
  /// Configurar listeners de tiempo real (EXTRA - NO CRÍTICO)
  void _setupRealtimeListeners(RealtimeNotificationService realtimeService) {
    // Solo agregar listeners para acelerar las notificaciones si el tiempo real funciona
    // El polling ya garantiza que funcione
    debugPrint('✅ [DELIVERY] Tiempo real configurado como acelerador');
  }

  Future<void> _loadAvailableOrders() async {
    try {
      // Solo mostrar loading si es la carga inicial
      final showLoading = availableOrders.isEmpty;
      if (showLoading) {
        setState(() {
          isLoading = true;
          errorMessage = null;
        });
      }

      print('🔍 [DELIVERY] Loading available orders...');
      
      // CORRECCIÓN: Solo mostrar pedidos ya aceptados por el restaurante
      // NO mostrar pedidos 'pending' que aún no han sido aceptados por el restaurante
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
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup'])
          .isFilter('delivery_agent_id', null) // Solo pedidos sin repartidor asignado
          .order('created_at', ascending: false);

      print('📦 [DELIVERY] Available orders response: ${response.length} orders');
      print('✅ [LOGIC] ¡CORRECTO! Solo mostrando pedidos aceptados por restaurante');

      // RLS diagnostic: si no hay pedidos, verificar rol y perfil
      if ((response as List).isEmpty) {
        try {
          final user = SupabaseConfig.client.auth.currentUser;
          final userData = user == null
              ? null
              : await SupabaseConfig.client
                  .from('users')
                  .select('role')
                  .eq('id', user.id)
                  .maybeSingle();
          final role = userData?['role'];
          print('🧪 [DELIVERY] Diagnóstico: role=$role, canDeliver=$_canDeliver');
          print('🧪 [DELIVERY] Si role=repartidor y sigue vacío, probablemente falta política RLS para ver pedidos no asignados.');
        } catch (e) {
          print('⚠️ [DELIVERY] Diagnóstico RLS fallido: $e');
        }
      }

      if (response is List) {
        final newOrders = List<Map<String, dynamic>>.from(response);
        
        // Detectar nuevos pedidos para notificación
        final newCount = newOrders.length;
        final previousCount = availableOrders.length;
        
         setState(() {
          availableOrders = newOrders;
          if (showLoading) isLoading = false;
          errorMessage = null;
        });
        
        // Mostrar notificación si hay nuevos pedidos (solo si no es carga inicial)
        if (!showLoading && newCount > previousCount && mounted) {
          final newOrdersCount = newCount - previousCount;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🔔 ¡$newOrdersCount ${newOrdersCount == 1 ? "nuevo pedido" : "nuevos pedidos"} disponibles!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        
        print('✅ [DELIVERY] Loaded ${availableOrders.length} available orders');
      }
    } catch (e) {
      print('❌ [DELIVERY] Error loading available orders: $e');
      setState(() {
        if (availableOrders.isEmpty) {
          errorMessage = 'Error al cargar pedidos: $e';
          isLoading = false;
        }
        // Si ya hay pedidos, no mostrar error para no interrumpir UX
      });
    }
  }

  Future<void> _acceptOrder(String orderId) async {
    try {
      if (!_canDeliver) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa tu registro antes de aceptar pedidos'), backgroundColor: Colors.orange),
        );
        return;
      }
      print('✋ [DELIVERY] Accepting order via RPC: $orderId');

      final ok = await DoaRepartosService.acceptOrder(orderId);
      if (!ok) {
        throw Exception('No fue posible asignar el pedido. Quizá ya no está disponible.');
      }

      // Start foreground location tracking for this order
      try {
        await LocationTrackingService.instance.start(orderId: orderId);
      } catch (e) {
        debugPrint('⚠️ [DELIVERY] Failed to start location tracking: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pedido asignado! Cliente y restaurante han sido notificados. Ve al restaurante para recoger'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Recargar la lista de pedidos disponibles
        _loadAvailableOrders();
      }
    } catch (e) {
      print('❌ [DELIVERY] Error accepting order: $e');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos Disponibles'),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // No mostrar botón de navegación hacia atrás
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadOnboardingGate();
              await _loadAvailableOrders();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header con estadísticas o bloqueo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.1),
            child: _canDeliver
                ? Row(
                    children: [
                      const Icon(Icons.local_shipping, color: Colors.green),
                      const SizedBox(width: 12),
                      Text(
                        '${availableOrders.length} pedidos disponibles',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(20)),
                        child: const Text('DISPONIBLE', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Completa tu perfil y documentos para ver y aceptar pedidos.',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed('/delivery/onboarding'),
                        icon: const Icon(Icons.assignment, color: Colors.orange),
                        label: const Text('Completar'),
                      ),
                    ],
                  ),
          ),
          
          // Lista de pedidos
          Expanded(
            child: !_canDeliver
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.assignment_turned_in_outlined, size: 56, color: Colors.orange),
                          const SizedBox(height: 12),
                          const Text('Completa tu registro de repartidor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          const Text('Sube tu foto, identificación y documentos del vehículo.', textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(context).pushNamed('/delivery/onboarding'),
                            icon: const Icon(Icons.arrow_forward, color: Colors.white),
                            label: const Text('Ir a completar', style: TextStyle(color: Colors.white)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          ),
                        ],
                      ),
                    ),
                  )
                : isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text(
                              'Error al cargar pedidos',
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
                              onPressed: _loadAvailableOrders,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : availableOrders.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No hay pedidos disponibles',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Vuelve a revisar en unos minutos',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadAvailableOrders,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: availableOrders.length,
                              itemBuilder: (context, index) {
                                final order = availableOrders[index];
                                return _buildOrderCard(order);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final restaurant = order['restaurants'] ?? {};
    final orderItems = order['items'] as List? ?? [];
    final totalAmount = (order['total_amount'] ?? 0.0).toDouble();
    final createdAt = DateTime.parse(order['created_at']);
    final timeAgo = DateTime.now().difference(createdAt).inMinutes;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header del pedido
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.receipt, color: Colors.green),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${order['id'].toString().substring(0, 8)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Hace $timeAgo minutos',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '\$${totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                // Información del restaurante
                Row(
                  children: [
                    const Icon(Icons.store, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurant['name'] ?? 'Restaurante desconocido',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (restaurant['address'] != null)
                            Text(
                              restaurant['address'],
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Dirección de entrega
                Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Entregar en:',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            order['delivery_address'] ?? 'Dirección no especificada',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Número de items
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_bag, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        '${orderItems.length} items en el pedido',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Botón de aceptar
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _acceptOrder(order['id']),
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'Aceptar Pedido',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}