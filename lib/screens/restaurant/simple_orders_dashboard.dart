import 'dart:async';
import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/restaurant/order_detail_restaurant_screen.dart';

/// Dashboard simplificado de pedidos para uso en navbar
class SimpleOrdersDashboard extends StatefulWidget {
  const SimpleOrdersDashboard({super.key});

  @override
  State<SimpleOrdersDashboard> createState() => _SimpleOrdersDashboardState();
}

class _SimpleOrdersDashboardState extends State<SimpleOrdersDashboard> {
  DoaRestaurant? _restaurant;
  List<DoaOrder> _orders = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      if (mounted) {
        _loadData(showLoading: false);
      }
    });
  }

  Future<void> _loadData({bool showLoading = true}) async {
    try {
      if (showLoading && mounted) setState(() => _isLoading = true);
      
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) return;
      if (!mounted) return;
      
      // Cargar restaurante
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      if (restaurantResponse != null) {
        if (!mounted) return;
        _restaurant = DoaRestaurant.fromJson(restaurantResponse);
        
        // Cargar pedidos
        final ordersResponse = await SupabaseConfig.client
            .from('orders')
            .select('''
              *,
              user:users!orders_user_id_fkey(id, name, email, phone),
              delivery_agent:users!orders_delivery_agent_id_fkey(id, name, email, phone),
              order_items(
                *,
                products(name, price)
              )
            ''')
            .eq('restaurant_id', _restaurant!.id)
            .order('created_at', ascending: false)
            .limit(20);

        if (!mounted) return;
        setState(() {
          _orders = (ordersResponse as List)
              .map((data) => DoaOrder.fromJson(data))
              .toList();
        });
      }
      
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
    } finally {
      if (showLoading && mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header con estado del restaurante
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const Icon(Icons.analytics, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Dashboard Restaurante',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18, // Ligeramente más pequeño para optimizar espacio
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8), // Reemplazo Spacer por un margen fijo para dar prioridad al título si hay espacio
                // Estado del restaurante
                if (_restaurant != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _restaurant?.online == true ? Colors.green : Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _restaurant?.online == true ? Icons.wifi : Icons.wifi_off,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _restaurant?.online == true ? 'ONLINE' : 'OFFLINE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                  onPressed: () => _loadData(),
                ),
              ],
            ),
          ),
        ),
        
        // Contenido principal
        Expanded(
          child: _isLoading
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
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : _buildDashboardContent(),
        ),
      ],
    );
  }

  Widget _buildDashboardContent() {
    // Estadísticas rápidas
    final pendingOrders = _orders.where((o) => o.status == OrderStatus.pending).length;
    final activeOrders = _orders.where((o) => 
        o.status == OrderStatus.confirmed || 
        o.status == OrderStatus.inPreparation ||
        o.status == OrderStatus.readyForPickup
    ).length;
    final completedToday = _orders.where((o) {
      final today = DateTime.now();
      final orderDate = o.createdAt;
      return o.status == OrderStatus.delivered &&
             orderDate.year == today.year &&
             orderDate.month == today.month &&
             orderDate.day == today.day;
    }).length;

    return RefreshIndicator(
      onRefresh: () => _loadData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Estadísticas rápidas
            Container(
              margin: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(child: _buildStatCard('Pendientes', pendingOrders, Colors.orange, Icons.pending)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('En Proceso', activeOrders, Colors.blue, Icons.restaurant)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildStatCard('Hoy', completedToday, Colors.green, Icons.check_circle)),
                ],
              ),
            ),
            
            // Gráfica de distribución de pedidos
            _buildOrderChart(pendingOrders, activeOrders, completedToday),
            
            // Lista resumida de pedidos recientes
            Container(
              margin: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📋 Pedidos Recientes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_orders.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(Icons.receipt_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              'Aún no hay pedidos',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...(_orders.take(5).map((order) => _buildOrderTile(order))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderChart(int pending, int active, int completed) {
    final total = pending + active + completed;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.withValues(alpha: 0.1),
            Colors.blue.withValues(alpha: 0.1),
            Colors.green.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Distribución de Pedidos',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          
          if (total == 0)
            const Center(
              child: Text(
                'No hay pedidos para mostrar',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else ...[
            _buildProgressBar('Pendientes', pending, total, Colors.orange),
            const SizedBox(height: 8),
            _buildProgressBar('En Proceso', active, total, Colors.blue),
            const SizedBox(height: 8),
            _buildProgressBar('Completados', completed, total, Colors.green),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total) : 0.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
                fontSize: 12,
              ),
            ),
            Text(
              '$value (${(percentage * 100).toStringAsFixed(0)}%)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 6,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percentage,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderTile(DoaOrder order) {
    final isPending = order.status == OrderStatus.pending;
    
    return GestureDetector(
      onTap: () => _openOrderDetail(order),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPending 
                ? Colors.orange.withValues(alpha: 0.5) 
                : Colors.grey.withValues(alpha: 0.2),
            width: isPending ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isPending 
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.1),
              blurRadius: isPending ? 4 : 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icono de estado
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getStatusColor(order.status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pedido #${order.id.substring(0, 8)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      // Badge para pedidos pendientes
                      if (isPending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'NUEVO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    _getStatusText(order.status),
                    style: TextStyle(
                      color: _getStatusColor(order.status),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            
            Text(
              '\$${order.totalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Flecha indicando que es tocable
            Icon(
              Icons.arrow_forward_ios,
              size: 12,
              color: isPending ? Colors.orange : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  /// Abrir pantalla de detalles del pedido
  Future<void> _openOrderDetail(DoaOrder order) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderDetailRestaurantScreen(order: order),
      ),
    );
    
    // Si se actualizó el pedido, refrescar los datos
    if (result == true) {
      debugPrint('🔄 Pedido actualizado, refrescando lista...');
      await _loadData();
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.inPreparation:
        return Colors.purple;
      case OrderStatus.readyForPickup:
        return Colors.indigo;
      case OrderStatus.onTheWay:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.notDelivered:
        return Colors.red;
      case OrderStatus.canceled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmado';
      case OrderStatus.inPreparation:
        return 'Preparando';
      case OrderStatus.readyForPickup:
        return 'Listo';
      case OrderStatus.assigned:
        return 'Asignado';
      case OrderStatus.onTheWay:
        return 'En camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.notDelivered:
        return 'NO ENTREGADO ⛔';
      case OrderStatus.canceled:
        return 'Cancelado';
      default:
        return 'Desconocido';
    }
  }
}