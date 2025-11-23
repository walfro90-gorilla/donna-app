import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/realtime_service.dart';

/// Pantalla para gestionar pedidos del restaurante
class OrdersManagementScreen extends StatefulWidget {
  const OrdersManagementScreen({super.key});

  @override
  State<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends State<OrdersManagementScreen> {
  DoaRestaurant? _restaurant;
  List<DoaOrder> _orders = [];
  bool _isLoading = true;
  OrderStatus? _selectedStatus; // Filter
  Timer? _refreshTimer;
  int _previousOrderCount = 0;
  StreamSubscription<DoaOrder>? _newOrdersSubscription;
  StreamSubscription<DoaOrder>? _orderUpdatesSubscription;
  StreamSubscription<void>? _refreshDataSubscription;

  @override
  void initState() {
    super.initState();
    _loadRestaurantAndOrders();
    _startAutoRefresh();
    // Configurar notificaciones después de cargar el restaurante
    Future.delayed(const Duration(milliseconds: 500), () {
      _setupRealtimeNotifications();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _newOrdersSubscription?.cancel();
    _orderUpdatesSubscription?.cancel();
    _refreshDataSubscription?.cancel();
    super.dispose();
  }

  /// Iniciar auto-refresh cada 8 segundos (más frecuente para garantizar tiempo real)
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted) {
        debugPrint('🔄 [RESTAURANT] Auto-refresh ejecutándose...');
        _loadRestaurantAndOrders(showLoading: false);
      }
    });
  }

  /// Configurar sistema híbrido: tiempo real + polling garantizado
  void _setupRealtimeNotifications() async {
    debugPrint('🔄 [RESTAURANT] ===== CONFIGURANDO SISTEMA HÍBRIDO TIEMPO REAL =====');
    
    // SIEMPRE usar polling como base, tiempo real como extra
    debugPrint('✅ [RESTAURANT] Sistema de polling activo cada 15 segundos');
    
    // Intentar tiempo real solo si hay usuario autenticado
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('⚠️ [RESTAURANT] Sin usuario autenticado, usando solo polling');
      return;
    }
    
    debugPrint('👤 [RESTAURANT] Usuario autenticado: ${user!.email}');
    
    final realtimeService = RealtimeNotificationService.forUser(user.id);
    
    // Inicializar tiempo real sin bloquear si falla
    try {
      if (!realtimeService.isInitialized) {
        debugPrint('🔄 [RESTAURANT] Inicializando tiempo real...');
        await realtimeService.initialize().timeout(const Duration(seconds: 5));
      }
      
      if (realtimeService.isInitialized) {
        debugPrint('✅ [RESTAURANT] Tiempo real activo como EXTRA');
        _setupRealtimeListeners(realtimeService);
      } else {
        debugPrint('⚠️ [RESTAURANT] Tiempo real no disponible, usando solo polling');
      }
    } catch (e) {
      debugPrint('⚠️ [RESTAURANT] Error en tiempo real: $e - usando solo polling');
    }
  }
  
  /// Configurar listeners de tiempo real
  void _setupRealtimeListeners(RealtimeNotificationService realtimeService) {
    // Escuchar nuevos pedidos
    _newOrdersSubscription = realtimeService.newOrders.listen((order) {
      debugPrint('🔔 [RESTAURANT] Nueva orden en tiempo real: ${order.id}');
      
      if (_restaurant != null && order.restaurantId == _restaurant!.id) {
        debugPrint('✅ [RESTAURANT] Pedido para MI restaurante');
        
        // Actualizar inmediatamente SIN esperar al polling
        setState(() {
          final existingIndex = _orders.indexWhere((o) => o.id == order.id);
          if (existingIndex == -1) {
            _orders.insert(0, order);
            debugPrint('✅ [RESTAURANT] Pedido agregado instantáneamente');
          } else {
            _orders[existingIndex] = order;
          }
        });
        
        // Mostrar notificación toast
        if (mounted) {
          NotificationToast.show(
            context,
            title: '¡Nuevo Pedido! 📱',
            message: 'Pedido #${order.id.substring(0, 8)} - \$${order.totalAmount.toStringAsFixed(0)}',
            icon: Icons.restaurant_menu,
            backgroundColor: Colors.orange,
          );
        }
      }
    });
    
    // Escuchar actualizaciones de pedidos
    _orderUpdatesSubscription = realtimeService.orderUpdates.listen((order) {
      if (_restaurant != null && order.restaurantId == _restaurant!.id) {
        debugPrint('🔄 [RESTAURANT] Actualización en tiempo real: ${order.id}');
        
        // Actualizar inmediatamente
        setState(() {
          final index = _orders.indexWhere((o) => o.id == order.id);
          if (index != -1) {
            _orders[index] = order;
            debugPrint('✅ [RESTAURANT] Actualizado instantáneamente');
          }
        });
      }
    });
  }

  /// Cargar restaurante y pedidos
  Future<void> _loadRestaurantAndOrders({bool showLoading = true}) async {
    try {
      if (showLoading) setState(() => _isLoading = true);
      
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) return;
      
      // Cargar restaurante
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      if (restaurantResponse != null) {
        _restaurant = DoaRestaurant.fromJson(restaurantResponse);
        
        // Cargar pedidos del restaurante con datos relacionados INCLUYENDO REPARTIDOR
        print('🔍 [RESTAURANT] Consultando pedidos para restaurante: ${_restaurant!.id}');
        
        var query = SupabaseConfig.client
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
            .eq('restaurant_id', _restaurant!.id);
        
        // Filtrar por estado si está seleccionado
        if (_selectedStatus != null) {
          query = query.eq('status', _selectedStatus.toString());
        }
        
        final ordersResponse = await query.order('created_at', ascending: false);
        
        // Debug: Mostrar información completa de pedidos
        print('🔍 [RESTAURANT] Total pedidos encontrados: ${ordersResponse.length}');
        print('📋 [RESTAURANT] Raw orders response: ${ordersResponse.map((o) => {
          'id': o['id']?.toString().substring(0, 8) ?? 'NO_ID',
          'restaurant_id': o['restaurant_id'],
          'user_id': o['user_id'], 
          'status': o['status'],
          'total_amount': o['total_amount']
        }).toList()}');
        
        for (var orderData in ordersResponse) {
          print('📦 [RESTAURANT] Procesando pedido ${orderData['id']?.toString().substring(0, 8) ?? 'NO_ID'}');
          if (orderData['delivery_agents'] != null) {
            print('   🚚 Repartidor: ${orderData['delivery_agents']['name']} (${orderData['delivery_agents']['status']})');
          } else {
            print('   🚚 Sin repartidor asignado');
          }
        }
        
        final newOrders = <DoaOrder>[];
        for (var orderJson in ordersResponse) {
          try {
            // Validar que el pedido tiene datos mínimos requeridos
            if (orderJson['id'] == null || orderJson['user_id'] == null) {
              print('⚠️ [RESTAURANT] Skipping order with missing critical data: ${orderJson['id'] ?? 'NO_ID'}');
              continue;
            }
            
            // Debug user data specifically
            if (orderJson['users'] != null) {
              print('👤 [RESTAURANT] User data: ${orderJson['users']}');
              print('📞 [RESTAURANT] User phone: "${orderJson['users']['phone']}" (type: ${orderJson['users']['phone'].runtimeType})');
              print('👤 [RESTAURANT] User name: "${orderJson['users']['name']}" (type: ${orderJson['users']['name'].runtimeType})');
            }
            
            print('🔧 [RESTAURANT] About to parse order: ${orderJson['id']?.toString().substring(0, 8) ?? 'NO_ID'}');
            final order = DoaOrder.fromJson(orderJson);
            print('✅ [RESTAURANT] Order parsed successfully');
            
            // Validar que el pedido realmente pertenece a este restaurante
            if (order.restaurantId != null && order.restaurantId == _restaurant!.id) {
              newOrders.add(order);
              print('✅ [RESTAURANT] Order added: ${order.user?.name ?? "Sin nombre"} | Phone: ${order.user?.phone ?? "Sin teléfono"}');
            } else {
              print('⚠️ [RESTAURANT] Skipping order ${order.id.substring(0, 8)} - restaurant ID mismatch: ${order.restaurantId} vs ${_restaurant!.id}');
            }
          } catch (e, stackTrace) {
            print('❌ [RESTAURANT] Error parsing order ${orderJson['id']?.toString().substring(0, 8) ?? 'NO_ID'}: $e');
            print('📍 [RESTAURANT] Stack trace: $stackTrace');
            print('🔍 [RESTAURANT] Problem order data: $orderJson');
            // Continue processing other orders
          }
        }
        print('✅ [RESTAURANT] Successfully parsed ${newOrders.length} orders out of ${ordersResponse.length} total');
        
        // Detectar nuevos pedidos COMPARANDO IDs ÚNICOS (más confiable)
        final currentOrderIds = _orders.map((o) => o.id).toSet();
        final newOrderIds = newOrders.map((o) => o.id).toSet();
        final reallyNewOrders = newOrderIds.difference(currentOrderIds);
        
        debugPrint('🔍 [RESTAURANT] Órdenes actuales: ${currentOrderIds.length}');
        debugPrint('🔍 [RESTAURANT] Órdenes nuevas cargadas: ${newOrderIds.length}');
        debugPrint('🔍 [RESTAURANT] Órdenes realmente nuevas: ${reallyNewOrders.length}');
        
        // Solo mostrar notificación si hay REALMENTE nuevas órdenes
        if (!showLoading && reallyNewOrders.isNotEmpty && mounted) {
          debugPrint('🎉 [RESTAURANT] ¡NUEVAS ÓRDENES DETECTADAS! Mostrando notificación...');
          
          // Encontrar las órdenes realmente nuevas
          final newOrdersList = newOrders.where((o) => reallyNewOrders.contains(o.id)).toList();
          
          for (final newOrder in newOrdersList) {
            debugPrint('📱 [RESTAURANT] Nueva orden: ${newOrder.id.substring(0, 8)} - ${newOrder.user?.name}');
            
            // Toast personalizado
            NotificationToast.show(
              context,
              title: '¡NUEVO PEDIDO! 🔔',
              message: 'Pedido #${newOrder.id.substring(0, 8)} - \$${newOrder.totalAmount.toStringAsFixed(0)}\nDe: ${newOrder.user?.name ?? "Cliente"}',
              icon: Icons.restaurant_menu,
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 6),
            );
          }
          
          // SnackBar adicional
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.notifications_active, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('🔔 ${reallyNewOrders.length} nuevo${reallyNewOrders.length > 1 ? "s" : ""} pedido${reallyNewOrders.length > 1 ? "s" : ""} recibido${reallyNewOrders.length > 1 ? "s" : ""}!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        
        _orders = newOrders;
      }
      
    } catch (e) {
      print('Error cargando pedidos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando pedidos: $e')),
        );
      }
    } finally {
      if (mounted && showLoading) setState(() => _isLoading = false);
      if (mounted && !showLoading) setState(() {});
    }
  }

  /// Actualizar estado del pedido
  Future<void> _updateOrderStatus(DoaOrder order, OrderStatus newStatus) async {
    try {
      await SupabaseConfig.client
          .from('orders')
          .update({
            'status': newStatus.toString(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', order.id);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Pedido actualizado a ${_getStatusText(newStatus)}')),
      );
      
      await _loadRestaurantAndOrders();
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error actualizando: $e')),
      );
    }
  }

  /// Mostrar opciones de cambio de estado
  Future<void> _showStatusOptions(DoaOrder order) async {
    final List<OrderStatus> availableStatuses = _getAvailableStatuses(order.status);
    
    if (availableStatuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios de estado disponibles')),
      );
      return;
    }
    
    final selectedStatus = await showDialog<OrderStatus>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar Estado del Pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: availableStatuses.map((status) {
            return ListTile(
              leading: Icon(_getStatusIcon(status), color: _getStatusColor(status)),
              title: Text(_getStatusText(status)),
              subtitle: Text(_getStatusDescription(status)),
              onTap: () => Navigator.of(context).pop(status),
            );
          }).toList(),
        ),
      ),
    );
    
    if (selectedStatus != null) {
      await _updateOrderStatus(order, selectedStatus);
    }
  }

  /// Estados disponibles según el estado actual
  List<OrderStatus> _getAvailableStatuses(OrderStatus currentStatus) {
    switch (currentStatus) {
      case OrderStatus.pending:
        return [OrderStatus.confirmed, OrderStatus.canceled];
      case OrderStatus.confirmed:
        return [OrderStatus.inPreparation, OrderStatus.canceled];
      case OrderStatus.inPreparation:
        return [OrderStatus.readyForPickup];
      case OrderStatus.readyForPickup:
        return [OrderStatus.onTheWay];
      case OrderStatus.onTheWay:
        return [OrderStatus.delivered];
      default:
        return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Dashboard Restaurante'),
            const Spacer(),
            // Botón de disponibilidad
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _restaurant?.online == true ? Colors.green : Colors.red,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _restaurant?.online == true ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _restaurant?.online == true ? 'DISPONIBLE' : 'CERRADO',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // Botón toggle disponibilidad
          IconButton(
            icon: Icon(
              _restaurant?.online == true ? Icons.toggle_on : Icons.toggle_off,
              size: 32,
            ),
            tooltip: _restaurant?.online == true ? 'Cerrar restaurante' : 'Abrir restaurante',
            onPressed: _toggleAvailability,
          ),
          PopupMenuButton<OrderStatus?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrar por estado',
            onSelected: (status) {
              setState(() => _selectedStatus = status);
              _loadRestaurantAndOrders();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: null,
                child: Row(
                  children: [
                    const Icon(Icons.list, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    const Text('Todos los pedidos'),
                    const Spacer(),
                    Text(
                      '(${_orders.length})',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              ...OrderStatus.values.map((status) {
                final count = _orders.where((o) => o.status == status).length;
                return PopupMenuItem(
                  value: status,
                  child: Row(
                    children: [
                      Icon(_getStatusIcon(status), color: _getStatusColor(status), size: 16),
                      const SizedBox(width: 8),
                      Text(_getStatusText(status)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          count.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _restaurant == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.store_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Primero debes crear tu restaurante',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Dashboard con contadores esenciales y estado del servicio
                    _buildDashboardCounters(),
                    
                    // Indicador de estado del servicio
                    _buildServiceStatusIndicator(),
                    
                    // Lista de pedidos
                    Expanded(
                      child: _orders.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedStatus != null 
                                        ? 'No hay pedidos con estado "${_getStatusText(_selectedStatus!)}"'
                                        : 'No tienes pedidos aún',
                                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadRestaurantAndOrders,
                              child: ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _orders.length,
                                itemBuilder: (context, index) {
                                  final order = _orders[index];
                                  return OrderCard(
                                    order: order,
                                    onStatusChange: () => _showStatusOptions(order),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
      
      // NAVBAR INFERIOR AGREGADO
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.orange,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        currentIndex: 0, // Dashboard está seleccionado
        elevation: 8,
        onTap: (index) {
          switch (index) {
            case 0:
              // Ya estamos en Dashboard
              break;
            case 1:
              // Navegar al perfil del restaurante
              Navigator.of(context).pushReplacementNamed('/restaurant-profile');
              break;
            case 2:
              // Navegar a gestión de productos
              Navigator.of(context).pushReplacementNamed('/products-management');
              break;
            case 3:
              // Navegar al perfil de usuario
              Navigator.of(context).pushReplacementNamed('/profile');
              break;
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.store),
            label: 'Mi Restaurante',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu),
            label: 'Productos',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.person),
                // Indicador de notificaciones si hay pedidos nuevos
                if (_orders.where((o) => o.status == OrderStatus.pending).isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                      child: Text(
                        '${_orders.where((o) => o.status == OrderStatus.pending).length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }

  /// Construir dashboard con contadores esenciales
  Widget _buildDashboardCounters() {
    if (_orders.isEmpty && !_isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        color: Colors.orange.withValues(alpha: 0.1),
        child: const Text(
          'No hay pedidos para mostrar estadísticas',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    
    // Contadores esenciales
    final newOrders = _orders.where((o) => o.status == OrderStatus.pending).length;
    final inProgress = _orders.where((o) => 
        o.status == OrderStatus.confirmed || 
        o.status == OrderStatus.inPreparation ||
        o.status == OrderStatus.readyForPickup
    ).length;
    
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final completedToday = _orders.where((order) {
      return order.status == OrderStatus.delivered &&
             order.createdAt.isAfter(startOfDay) && 
             order.createdAt.isBefore(endOfDay);
    }).length;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Dashboard en Tiempo Real',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const Spacer(),
              Text(
                'Total: ${_orders.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Contadores en fila
          Row(
            children: [
              // Nuevos
              Expanded(
                child: _buildCounterCard(
                  'Nuevos',
                  newOrders.toString(),
                  Icons.fiber_new,
                  Colors.orange,
                  () => _filterByStatus(OrderStatus.pending),
                ),
              ),
              const SizedBox(width: 12),
              
              // En Curso  
              Expanded(
                child: _buildCounterCard(
                  'En Curso',
                  inProgress.toString(),
                  Icons.restaurant,
                  Colors.blue,
                  () => _filterByStatus(OrderStatus.confirmed),
                ),
              ),
              const SizedBox(width: 12),
              
              // Terminados Hoy
              Expanded(
                child: _buildCounterCard(
                  'Terminados',
                  completedToday.toString(),
                  Icons.check_circle,
                  Colors.green,
                  () => _filterByStatus(OrderStatus.delivered),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  /// Construir tarjeta de contador individual
  Widget _buildCounterCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  /// Filtrar por estado específico
  void _filterByStatus(OrderStatus status) {
    setState(() {
      _selectedStatus = _selectedStatus == status ? null : status;
    });
    _loadRestaurantAndOrders();
  }
  
  /// Construir indicador de estado del servicio
  Widget _buildServiceStatusIndicator() {
    final isPollingActive = true; // Siempre activo por ahora
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isPollingActive ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: isPollingActive ? Colors.green.withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPollingActive ? Icons.wifi : Icons.wifi_off,
            color: isPollingActive ? Colors.green : Colors.red,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            isPollingActive 
              ? '🟢 Notificaciones activas (Polling cada 6s)'
              : '🔴 Notificaciones desactivadas',
            style: TextStyle(
              fontSize: 12,
              color: isPollingActive ? Colors.green.shade700 : Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!isPollingActive) ...[
            const Spacer(),
            TextButton(
              onPressed: () => _setupRealtimeNotifications(),
              child: const Text(
                'Reactivar',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  /// Construir sección de estadísticas (legacy - mantenido para compatibilidad)
  Widget _buildStatsSection() {
    if (_orders.isEmpty) return const SizedBox.shrink();
    
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    
    final todayOrders = _orders.where((order) {
      return order.createdAt.isAfter(startOfDay) && order.createdAt.isBefore(endOfDay);
    }).toList();
    
    final pendingCount = _orders.where((o) => o.status == OrderStatus.pending || o.status == OrderStatus.confirmed).length;
    final inPreparationCount = _orders.where((o) => o.status == OrderStatus.inPreparation || o.status == OrderStatus.readyForPickup).length;
    final onTheWayCount = _orders.where((o) => o.status == OrderStatus.onTheWay).length;
    final todayRevenue = todayOrders.fold<double>(0, (sum, order) => sum + order.totalAmount);
    
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Dashboard de Hoy',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              const Spacer(),
              Text(
                'Total pedidos: ${_orders.length}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Por Confirmar',
                  pendingCount.toString(),
                  Icons.schedule,
                  Colors.orange,
                  () => setState(() {
                    _selectedStatus = pendingCount > 0 ? OrderStatus.pending : null;
                    _loadRestaurantAndOrders();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'En Cocina',
                  inPreparationCount.toString(),
                  Icons.restaurant,
                  Colors.blue,
                  () => setState(() {
                    _selectedStatus = inPreparationCount > 0 ? OrderStatus.inPreparation : null;
                    _loadRestaurantAndOrders();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'En Camino',
                  onTheWayCount.toString(),
                  Icons.local_shipping,
                  Colors.purple,
                  () => setState(() {
                    _selectedStatus = onTheWayCount > 0 ? OrderStatus.onTheWay : null;
                    _loadRestaurantAndOrders();
                  }),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Revenue Today
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.attach_money, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Ingresos Hoy:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.green.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  '\$${todayRevenue.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                Text(
                  ' (${todayOrders.length} pedidos)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Toggle disponibilidad del restaurante
  Future<void> _toggleAvailability() async {
    if (_restaurant == null) return;
    
    try {
      final newOnlineStatus = !(_restaurant!.online);
      
      // Usar el nuevo método del servicio para actualizar el estado online
      await DoaRepartosService.updateRestaurantOnlineStatus(_restaurant!.id, newOnlineStatus);
      
      setState(() {
        _restaurant = DoaRestaurant(
          id: _restaurant!.id,
          userId: _restaurant!.userId,
          name: _restaurant!.name,
          description: _restaurant!.description,
          logoUrl: _restaurant!.logoUrl,
          status: _restaurant!.status,
          online: newOnlineStatus, // Usar el campo online de la base de datos
          createdAt: _restaurant!.createdAt,
          updatedAt: DateTime.now(),
          user: _restaurant!.user,
          imageUrl: _restaurant!.imageUrl,
          rating: _restaurant!.rating,
          deliveryTime: _restaurant!.deliveryTime,
          deliveryFee: _restaurant!.deliveryFee,
          isOpen: newOnlineStatus, // Mantener sincronizado con online
        );
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newOnlineStatus 
                  ? '✅ Restaurante EN LÍNEA - Recibiendo pedidos'
                  : '⏸️ Restaurante FUERA DE LÍNEA - No recibiendo pedidos',
            ),
            backgroundColor: newOnlineStatus ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cambiar disponibilidad: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// Agregar datos de prueba (solo para desarrollo)
  Future<void> _addTestData() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Creando datos de prueba...'),
            ],
          ),
        ),
      );
      
      final currentUser = SupabaseConfig.client.auth.currentUser;
      if (currentUser == null) return;
      
      // Funcionalidad de test data fue removida ya que no se utilizan datos de prueba
      // Solo se usa la conexión directa a Supabase
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La funcionalidad de test data no está disponible. Se usa solo la base de datos real.'),
          backgroundColor: Colors.orange,
        ),
      );
      
      return;
      
      Navigator.of(context).pop(); // Cerrar diálogo de carga
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 ¡Datos de prueba creados exitosamente!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Recargar datos
      await _loadRestaurantAndOrders();
      
    } catch (e) {
      Navigator.of(context).pop(); // Cerrar diálogo de carga si hay error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error creando datos de prueba: $e')),
      );
    }
  }
  
  /// Construir tarjeta de estadística individual
  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // Métodos auxiliares para estados
  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmado';
      case OrderStatus.inPreparation:
        return 'En Preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para Recoger';
      case OrderStatus.assigned:
        return 'Repartidor Asignado';
      case OrderStatus.onTheWay:
        return 'En Camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'NO ENTREGADO ⛔';
    }
  }

  String _getStatusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Nuevo pedido recibido - Esperando confirmación';
      case OrderStatus.confirmed:
        return 'Pedido confirmado por el restaurante';
      case OrderStatus.inPreparation:
        return 'Preparando el pedido en cocina';
      case OrderStatus.readyForPickup:
        return 'Pedido listo para ser recogido';
      case OrderStatus.assigned:
        return 'Repartidor asignado, va camino al restaurante';
      case OrderStatus.onTheWay:
        return 'En camino hacia el cliente';
      case OrderStatus.delivered:
        return 'Pedido entregado al cliente';
      case OrderStatus.canceled:
        return 'Pedido cancelado';
      case OrderStatus.notDelivered:
        return 'No se pudo entregar (cliente no recibió)';
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.done_all;
      case OrderStatus.assigned:
        return Icons.person_pin_circle;
      case OrderStatus.onTheWay:
        return Icons.local_shipping;
      case OrderStatus.delivered:
        return Icons.check_circle;
      case OrderStatus.canceled:
        return Icons.cancel;
      case OrderStatus.notDelivered:
        return Icons.block;
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.lightBlue;
      case OrderStatus.inPreparation:
        return Colors.blue;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.purple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.canceled:
        return Colors.red;
      case OrderStatus.notDelivered:
        return Colors.red;
    }
  }

  /// Construir widget de status del repartidor
  Widget _buildDeliveryStatus(DoaUser deliveryAgent) {
    final status = deliveryAgent.status ?? 'pending';
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status.toString().toLowerCase()) {
      case 'approved':
        statusText = 'ACTIVO';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusText = 'PENDIENTE';
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case 'rejected':
        statusText = 'RECHAZADO';
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'suspended':
        statusText = 'SUSPENDIDO';
        statusColor = Colors.grey;
        statusIcon = Icons.pause_circle;
        break;
      default:
        statusText = 'DESCONOCIDO';
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Card individual para mostrar pedido
class OrderCard extends StatelessWidget {
  final DoaOrder order;
  final VoidCallback onStatusChange;

  const OrderCard({
    super.key,
    required this.order,
    required this.onStatusChange,
  });

  @override
  Widget build(BuildContext context) {
    final totalItems = order.orderItems?.fold<int>(0, (sum, item) => sum + item.quantity) ?? 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con número de pedido y estado
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pedido #${order.id.substring(0, 8).toUpperCase()}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _formatDateTime(order.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _getStatusColor(order.status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(order.status),
                        size: 16,
                        color: _getStatusColor(order.status),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(order.status),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _getStatusColor(order.status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Información del cliente y repartidor
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cliente
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        order.user?.name ?? 'Cliente',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  if (order.user?.phone != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(order.user!.phone!),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(order.deliveryAddress ?? 'No especificada')),
                    ],
                  ),
                  
                  // Repartidor (si está asignado)
                  if (order.deliveryAgentId != null) ...[
                    const Divider(height: 16, thickness: 1),
                    Row(
                      children: [
                        const Icon(Icons.delivery_dining, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Repartidor:',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(order.deliveryAgent?.name ?? 'Asignado'),
                      ],
                    ),
                    if (order.deliveryAgent?.phone != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 16, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(order.deliveryAgent!.phone!),
                          const Spacer(),
                          _buildDeliveryStatus(order.deliveryAgent!),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Spacer(),
                          _buildDeliveryStatus(order.deliveryAgent!),
                        ],
                      ),
                    ],
                  ] else if (order.status == OrderStatus.onTheWay) ...[
                    const Divider(height: 16, thickness: 1),
                    Row(
                      children: [
                        const Icon(Icons.warning, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        const Text(
                          'Buscando repartidor...',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Items del pedido
            if (order.orderItems != null && order.orderItems!.isNotEmpty) ...[
              Text(
                'Productos ($totalItems items):',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...order.orderItems!.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${item.quantity}x',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(item.product?.name ?? 'Producto'),
                    ),
                    Text(
                      '\$${(item.priceAtTimeOfOrder * item.quantity).toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              )),
            ],
            
            const SizedBox(height: 16),
            
            // Total y botón de acción
            Row(
              children: [
                Text(
                  'Total: \$${order.totalAmount.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
                const Spacer(),
                if (_getAvailableStatuses(order.status).isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: onStatusChange,
                    icon: const Icon(Icons.update, size: 16),
                    label: const Text('Actualizar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
    
    if (difference.inDays > 0) {
    return '${difference.inDays} día${difference.inDays > 1 ? 's' : ''} atrás';
    } else if (difference.inHours > 0) {
    return '${difference.inHours} hora${difference.inHours > 1 ? 's' : ''} atrás';
    } else if (difference.inMinutes > 0) {
    return '${difference.inMinutes} minuto${difference.inMinutes > 1 ? 's' : ''} atrás';
    } else {
      return 'Hace un momento';
    }
  }

  List<OrderStatus> _getAvailableStatuses(OrderStatus currentStatus) {
    switch (currentStatus) {
      case OrderStatus.pending:
        return [OrderStatus.inPreparation, OrderStatus.canceled];
      case OrderStatus.inPreparation:
        return [OrderStatus.onTheWay];
      case OrderStatus.onTheWay:
        return [OrderStatus.delivered];
      default:
        return [];
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmado';
      case OrderStatus.inPreparation:
        return 'En Preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para Recoger';
      case OrderStatus.assigned:
        return 'Repartidor Asignado';
      case OrderStatus.onTheWay:
        return 'En Camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'NO ENTREGADO ⛔';
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.done_all;
      case OrderStatus.assigned:
        return Icons.person_pin_circle;
      case OrderStatus.onTheWay:
        return Icons.local_shipping;
      case OrderStatus.delivered:
        return Icons.check_circle;
      case OrderStatus.canceled:
        return Icons.cancel;
      case OrderStatus.notDelivered:
        return Icons.block;
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.lightBlue;
      case OrderStatus.inPreparation:
        return Colors.blue;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.purple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.canceled:
        return Colors.red;
      case OrderStatus.notDelivered:
        return Colors.red;
    }
  }

  /// Construir widget de status del repartidor
  Widget _buildDeliveryStatus(DoaUser deliveryAgent) {
    final status = deliveryAgent.status ?? 'pending';
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status.toString().toLowerCase()) {
      case 'approved':
        statusText = 'ACTIVO';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusText = 'PENDIENTE';
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case 'rejected':
        statusText = 'RECHAZADO';
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'suspended':
        statusText = 'SUSPENDIDO';
        statusColor = Colors.grey;
        statusIcon = Icons.pause_circle;
        break;
      default:
        statusText = 'DESCONOCIDO';
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }
}