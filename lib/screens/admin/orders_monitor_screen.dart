import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';
import 'package:intl/intl.dart';

/// Monitor profesional de pedidos para Admin con vista en tiempo real e historial completo
class OrdersMonitorScreen extends StatefulWidget {
  const OrdersMonitorScreen({super.key});

  @override
  State<OrdersMonitorScreen> createState() => _OrdersMonitorScreenState();
}

class _OrdersMonitorScreenState extends State<OrdersMonitorScreen> {
  final _supabase = SupabaseConfig.client;
  List<DoaOrder> _orders = [];
  bool _isLoading = true;
  String? _error;
  
  // Filtros
  OrderStatus? _filterStatus;
  String? _filterRestaurantId;
  String? _filterDeliveryAgentId;
  String? _filterClientId;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _searchQuery = '';
  
  // Listas para dropdowns
  List<DoaRestaurant> _restaurants = [];
  List<DoaUser> _deliveryAgents = [];
  
  // Realtime
  StreamSubscription? _ordersSubscription;
  StreamSubscription? _orderUpdatesSubscription;
  final _realtimeService = RealtimeNotificationService();
  
  // Stats
  int _totalOrders = 0;
  double _totalRevenue = 0.0;
  Map<String, int> _statusCounts = {};

  @override
  void initState() {
    super.initState();
    _initializeMonitor();
  }

  Future<void> _initializeMonitor() async {
    await _loadDropdownData();
    await _loadOrders();
    _setupRealtimeListeners();
  }

  Future<void> _loadDropdownData() async {
    try {
      // Cargar restaurantes
      final restaurantsData = await _supabase
          .from('restaurants')
          .select('id, name, user_id, status, online, created_at, updated_at')
          .order('name');
      _restaurants = (restaurantsData as List)
          .map((json) => DoaRestaurant.fromJson(json))
          .toList();

      // Cargar repartidores
      final deliveryAgentsData = await _supabase
          .from('users')
          .select()
          .eq('role', 'delivery_agent')
          .order('name');
      _deliveryAgents = (deliveryAgentsData as List)
          .map((json) => DoaUser.fromJson(json))
          .toList();

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ [MONITOR] Error cargando data para filtros: $e');
    }
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      debugPrint('🔍 [MONITOR] Cargando pedidos con filtros...');
      
      // Base query - construir paso a paso con tipo dinámico
      dynamic queryBuilder = _supabase
          .from('orders')
          .select('''
            *,
            user:user_id(id, name, email, phone, role, created_at, updated_at, email_confirm),
            restaurant:restaurant_id(id, name, user_id, logo_url, status, online, created_at, updated_at),
            delivery_agent_user:delivery_agent_id(id, name, email, phone, role, created_at, updated_at, email_confirm),
            order_items(*, product:product_id(*))
          ''');

      // Aplicar filtros
      if (_filterStatus != null) {
        queryBuilder = queryBuilder.eq('status', _filterStatus.toString());
      }
      if (_filterRestaurantId != null) {
        queryBuilder = queryBuilder.eq('restaurant_id', _filterRestaurantId!);
      }
      if (_filterDeliveryAgentId != null) {
        queryBuilder = queryBuilder.eq('delivery_agent_id', _filterDeliveryAgentId!);
      }
      if (_filterClientId != null) {
        queryBuilder = queryBuilder.eq('user_id', _filterClientId!);
      }
      if (_filterStartDate != null) {
        queryBuilder = queryBuilder.gte('created_at', _filterStartDate!.toIso8601String());
      }
      if (_filterEndDate != null) {
        final endOfDay = DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day, 23, 59, 59);
        queryBuilder = queryBuilder.lte('created_at', endOfDay.toIso8601String());
      }

      // Búsqueda de texto (por ID de orden)
      if (_searchQuery.isNotEmpty) {
        queryBuilder = queryBuilder.ilike('id', '%$_searchQuery%');
      }

      // Ordenar por más reciente primero
      queryBuilder = queryBuilder.order('created_at', ascending: false);

      final ordersData = await queryBuilder;
      
      _orders = (ordersData as List)
          .map((json) => DoaOrder.fromJson(json))
          .toList();

      // Calcular estadísticas
      _calculateStats();

      debugPrint('✅ [MONITOR] ${_orders.length} pedidos cargados');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [MONITOR] Error cargando pedidos: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _calculateStats() {
    _totalOrders = _orders.length;
    _totalRevenue = _orders
        .where((o) => o.status != OrderStatus.canceled)
        .fold(0.0, (sum, order) => sum + order.totalAmount);
    
    _statusCounts = {};
    for (final order in _orders) {
      final status = order.status.toString();
      _statusCounts[status] = (_statusCounts[status] ?? 0) + 1;
    }
  }

  void _setupRealtimeListeners() {
    // Escuchar nuevas órdenes
    _ordersSubscription = _realtimeService.newOrders.listen((order) {
      debugPrint('🆕 [MONITOR] Nueva orden detectada: ${order.id}');
      if (_shouldIncludeOrder(order)) {
        setState(() {
          _orders.insert(0, order);
          _calculateStats();
        });
      }
    });

    // Escuchar actualizaciones de órdenes
    _orderUpdatesSubscription = _realtimeService.orderUpdates.listen((order) {
      debugPrint('🔄 [MONITOR] Orden actualizada: ${order.id}');
      final index = _orders.indexWhere((o) => o.id == order.id);
      if (index != -1) {
        setState(() {
          if (_shouldIncludeOrder(order)) {
            _orders[index] = order;
          } else {
            _orders.removeAt(index);
          }
          _calculateStats();
        });
      } else if (_shouldIncludeOrder(order)) {
        setState(() {
          _orders.insert(0, order);
          _calculateStats();
        });
      }
    });
  }

  bool _shouldIncludeOrder(DoaOrder order) {
    if (_filterStatus != null && order.status != _filterStatus) return false;
    if (_filterRestaurantId != null && order.restaurantId != _filterRestaurantId) return false;
    if (_filterDeliveryAgentId != null && order.deliveryAgentId != _filterDeliveryAgentId) return false;
    if (_filterClientId != null && order.userId != _filterClientId) return false;
    if (_filterStartDate != null && order.createdAt.isBefore(_filterStartDate!)) return false;
    if (_filterEndDate != null) {
      final endOfDay = DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day, 23, 59, 59);
      if (order.createdAt.isAfter(endOfDay)) return false;
    }
    if (_searchQuery.isNotEmpty && !order.id.toLowerCase().contains(_searchQuery.toLowerCase())) return false;
    return true;
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _orderUpdatesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitor de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOrders,
            tooltip: 'Recargar',
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _showFiltersDialog,
            tooltip: 'Filtros',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats Cards
          _buildStatsCards(theme),
          
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por ID de orden...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _loadOrders();
              },
            ),
          ),

          // Active Filters Chips
          if (_hasActiveFilters()) _buildActiveFiltersChips(),

          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _orders.isEmpty
                        ? const Center(child: Text('No hay pedidos'))
                        : RefreshIndicator(
                            onRefresh: _loadOrders,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _orders.length,
                              itemBuilder: (context, index) => _buildOrderCard(_orders[index], theme),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Total Pedidos',
              _totalOrders.toString(),
              Icons.shopping_cart,
              Colors.blue,
              theme,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Ingresos Total',
              '\$${_totalRevenue.toStringAsFixed(2)}',
              Icons.attach_money,
              Colors.green,
              theme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _filterStatus != null ||
        _filterRestaurantId != null ||
        _filterDeliveryAgentId != null ||
        _filterClientId != null ||
        _filterStartDate != null ||
        _filterEndDate != null;
  }

  Widget _buildActiveFiltersChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_filterStatus != null)
            Chip(
              label: Text('Estado: ${_filterStatus!.displayName}'),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: () {
                setState(() => _filterStatus = null);
                _loadOrders();
              },
            ),
          if (_filterRestaurantId != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('Restaurante: ${_restaurants.firstWhere((r) => r.id == _filterRestaurantId).name}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() => _filterRestaurantId = null);
                  _loadOrders();
                },
              ),
            ),
          if (_filterDeliveryAgentId != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('Repartidor: ${_deliveryAgents.firstWhere((d) => d.id == _filterDeliveryAgentId).name ?? "N/A"}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() => _filterDeliveryAgentId = null);
                  _loadOrders();
                },
              ),
            ),
          if (_filterStartDate != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('Desde: ${DateFormat('dd/MM/yyyy').format(_filterStartDate!)}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() => _filterStartDate = null);
                  _loadOrders();
                },
              ),
            ),
          if (_filterEndDate != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('Hasta: ${DateFormat('dd/MM/yyyy').format(_filterEndDate!)}'),
                deleteIcon: const Icon(Icons.close, size: 18),
                onDeleted: () {
                  setState(() => _filterEndDate = null);
                  _loadOrders();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(DoaOrder order, ThemeData theme) {
    final statusColor = order.status.color;
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _showOrderDetails(order),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: ID + Status
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pedido #${order.id.substring(0, 8)}',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formattedDate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(order.status.icon, size: 16, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          order.status.displayName,
                          style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const Divider(height: 24),
              
              // Details
              _buildInfoRow(Icons.person, 'Cliente', order.user?.name ?? 'N/A', theme),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.restaurant, 'Restaurante', order.restaurant?.name ?? 'N/A', theme),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.delivery_dining,
                'Repartidor',
                order.deliveryAgent?.name ?? 'Sin asignar',
                theme,
              ),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.attach_money, 'Total', '\$${order.totalAmount.toStringAsFixed(2)}', theme),
              
              if (order.orderItems != null && order.orderItems!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${order.orderItems!.length} producto(s)',
                  style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.iconTheme.color?.withValues(alpha: 0.6)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _showFiltersDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _FiltersDialog(
        currentStatus: _filterStatus,
        currentRestaurantId: _filterRestaurantId,
        currentDeliveryAgentId: _filterDeliveryAgentId,
        currentStartDate: _filterStartDate,
        currentEndDate: _filterEndDate,
        restaurants: _restaurants,
        deliveryAgents: _deliveryAgents,
      ),
    );

    if (result != null) {
      setState(() {
        _filterStatus = result['status'];
        _filterRestaurantId = result['restaurantId'];
        _filterDeliveryAgentId = result['deliveryAgentId'];
        _filterStartDate = result['startDate'];
        _filterEndDate = result['endDate'];
      });
      await _loadOrders();
    }
  }

  Future<void> _showOrderDetails(DoaOrder order) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => OrderDetailsMonitorScreen(order: order),
      ),
    );
    // Recargar después de volver por si hubo cambios
    _loadOrders();
  }
}

/// Dialog de filtros
class _FiltersDialog extends StatefulWidget {
  final OrderStatus? currentStatus;
  final String? currentRestaurantId;
  final String? currentDeliveryAgentId;
  final DateTime? currentStartDate;
  final DateTime? currentEndDate;
  final List<DoaRestaurant> restaurants;
  final List<DoaUser> deliveryAgents;

  const _FiltersDialog({
    this.currentStatus,
    this.currentRestaurantId,
    this.currentDeliveryAgentId,
    this.currentStartDate,
    this.currentEndDate,
    required this.restaurants,
    required this.deliveryAgents,
  });

  @override
  State<_FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends State<_FiltersDialog> {
  late OrderStatus? _selectedStatus;
  late String? _selectedRestaurantId;
  late String? _selectedDeliveryAgentId;
  late DateTime? _selectedStartDate;
  late DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.currentStatus;
    _selectedRestaurantId = widget.currentRestaurantId;
    _selectedDeliveryAgentId = widget.currentDeliveryAgentId;
    _selectedStartDate = widget.currentStartDate;
    _selectedEndDate = widget.currentEndDate;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filtros de Pedidos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status
            const Text('Estado', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<OrderStatus?>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...OrderStatus.values.map((status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.displayName),
                    )),
              ],
              onChanged: (value) => setState(() => _selectedStatus = value),
            ),
            
            const SizedBox(height: 16),
            
            // Restaurante
            const Text('Restaurante', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _selectedRestaurantId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...widget.restaurants.map((r) => DropdownMenuItem(
                      value: r.id,
                      child: Text(r.name),
                    )),
              ],
              onChanged: (value) => setState(() => _selectedRestaurantId = value),
            ),
            
            const SizedBox(height: 16),
            
            // Repartidor
            const Text('Repartidor', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _selectedDeliveryAgentId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...widget.deliveryAgents.map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(d.name ?? d.email),
                    )),
              ],
              onChanged: (value) => setState(() => _selectedDeliveryAgentId = value),
            ),
            
            const SizedBox(height: 16),
            
            // Fechas
            const Text('Rango de fechas', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_selectedStartDate != null
                        ? DateFormat('dd/MM/yyyy').format(_selectedStartDate!)
                        : 'Desde'),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedStartDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _selectedStartDate = date);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(_selectedEndDate != null
                        ? DateFormat('dd/MM/yyyy').format(_selectedEndDate!)
                        : 'Hasta'),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _selectedEndDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _selectedEndDate = date);
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedStatus = null;
              _selectedRestaurantId = null;
              _selectedDeliveryAgentId = null;
              _selectedStartDate = null;
              _selectedEndDate = null;
            });
          },
          child: const Text('Limpiar todo'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, {
              'status': _selectedStatus,
              'restaurantId': _selectedRestaurantId,
              'deliveryAgentId': _selectedDeliveryAgentId,
              'startDate': _selectedStartDate,
              'endDate': _selectedEndDate,
            });
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

/// Pantalla de detalle de orden para monitor
class OrderDetailsMonitorScreen extends StatefulWidget {
  final DoaOrder order;

  const OrderDetailsMonitorScreen({super.key, required this.order});

  @override
  State<OrderDetailsMonitorScreen> createState() => _OrderDetailsMonitorScreenState();
}

class _OrderDetailsMonitorScreenState extends State<OrderDetailsMonitorScreen> with SingleTickerProviderStateMixin {
  late DoaOrder _order;
  final _supabase = SupabaseConfig.client;
  late TabController _tabController;
  
  List<OrderStatusUpdate> _statusHistory = [];
  List<DoaAccountTransaction> _transactions = [];
  bool _isLoadingHistory = true;
  bool _isLoadingTransactions = true;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _tabController = TabController(length: 4, vsync: this);
    _loadStatusHistory();
    _loadTransactions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStatusHistory() async {
    try {
      final data = await _supabase
          .from('order_status_updates')
          .select('*')
          .eq('order_id', _order.id)
          .order('created_at', ascending: false);
      
      _statusHistory = (data as List)
          .map((json) => OrderStatusUpdate.fromJson(json))
          .toList();
      
      if (mounted) setState(() => _isLoadingHistory = false);
    } catch (e) {
      debugPrint('❌ Error cargando historial: $e');
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final data = await _supabase
          .from('account_transactions')
          .select('*')
          .eq('order_id', _order.id)
          .order('created_at', ascending: false);
      
      _transactions = (data as List)
          .map((json) => DoaAccountTransaction.fromJson(json))
          .toList();
      
      if (mounted) setState(() => _isLoadingTransactions = false);
    } catch (e) {
      debugPrint('❌ Error cargando transacciones: $e');
      if (mounted) setState(() => _isLoadingTransactions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${_order.id.substring(0, 8)}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'General', icon: Icon(Icons.info_outline)),
            Tab(text: 'Productos', icon: Icon(Icons.shopping_bag_outlined)),
            Tab(text: 'Historial', icon: Icon(Icons.history)),
            Tab(text: 'Finanzas', icon: Icon(Icons.attach_money)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGeneralTab(theme),
          _buildProductsTab(theme),
          _buildHistoryTab(theme),
          _buildFinancesTab(theme),
        ],
      ),
    );
  }

  Widget _buildGeneralTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estado Actual', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _order.status.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _order.status.color),
                    ),
                    child: Row(
                      children: [
                        Icon(_order.status.icon, color: _order.status.color),
                        const SizedBox(width: 8),
                        Text(
                          _order.status.displayName,
                          style: TextStyle(
                            color: _order.status.color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Cliente
          _buildInfoCard(
            'Cliente',
            Icons.person,
            [
              _InfoItem('Nombre', _order.user?.name ?? 'N/A'),
              _InfoItem('Email', _order.user?.email ?? 'N/A'),
              _InfoItem('Teléfono', _order.user?.phone ?? 'N/A'),
            ],
            theme,
          ),
          
          const SizedBox(height: 16),
          
          // Restaurante
          _buildInfoCard(
            'Restaurante',
            Icons.restaurant,
            [
              _InfoItem('Nombre', _order.restaurant?.name ?? 'N/A'),
              _InfoItem('Estado', _order.restaurant?.status.displayName ?? 'N/A'),
              _InfoItem('Online', _order.restaurant?.online == true ? 'Sí' : 'No'),
            ],
            theme,
          ),
          
          const SizedBox(height: 16),
          
          // Repartidor
          _buildInfoCard(
            'Repartidor',
            Icons.delivery_dining,
            [
              _InfoItem('Nombre', _order.deliveryAgent?.name ?? 'Sin asignar'),
              if (_order.deliveryAgent != null) ...[
                _InfoItem('Email', _order.deliveryAgent?.email ?? 'N/A'),
                _InfoItem('Teléfono', _order.deliveryAgent?.phone ?? 'N/A'),
              ],
            ],
            theme,
          ),
          
          const SizedBox(height: 16),
          
          // Dirección de entrega
          _buildInfoCard(
            'Entrega',
            Icons.location_on,
            [
              _InfoItem('Dirección', _order.deliveryAddress ?? 'N/A'),
              if (_order.deliveryLat != null && _order.deliveryLon != null)
                _InfoItem('Coordenadas', '${_order.deliveryLat}, ${_order.deliveryLon}'),
            ],
            theme,
          ),
          
          const SizedBox(height: 16),
          
          // Fechas
          _buildInfoCard(
            'Fechas',
            Icons.calendar_today,
            [
              _InfoItem('Creado', DateFormat('dd/MM/yyyy HH:mm').format(_order.createdAt)),
              _InfoItem('Actualizado', DateFormat('dd/MM/yyyy HH:mm').format(_order.updatedAt)),
              if (_order.assignedAt != null)
                _InfoItem('Asignado', DateFormat('dd/MM/yyyy HH:mm').format(_order.assignedAt!)),
              if (_order.deliveryTime != null)
                _InfoItem('Tiempo de entrega', DateFormat('dd/MM/yyyy HH:mm').format(_order.deliveryTime!)),
            ],
            theme,
          ),
          
          const SizedBox(height: 16),
          
          // Códigos
          if (_order.pickupCode != null || _order.confirmCode != null)
            _buildInfoCard(
              'Códigos',
              Icons.qr_code,
              [
                if (_order.pickupCode != null) _InfoItem('Código de recogida', _order.pickupCode!),
                if (_order.confirmCode != null) _InfoItem('Código de confirmación', _order.confirmCode!),
              ],
              theme,
            ),
          
          if (_order.orderNotes != null && _order.orderNotes!.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildInfoCard(
              'Notas',
              Icons.note,
              [_InfoItem('Notas del pedido', _order.orderNotes!)],
              theme,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductsTab(ThemeData theme) {
    if (_order.orderItems == null || _order.orderItems!.isEmpty) {
      return const Center(child: Text('No hay productos'));
    }

    double subtotal = 0;
    for (final item in _order.orderItems!) {
      subtotal += item.priceAtTimeOfOrder * item.quantity;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._order.orderItems!.map((item) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: item.product?.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.product!.imageUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: Colors.grey,
                            child: const Icon(Icons.fastfood),
                          ),
                        ),
                      )
                    : Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.fastfood),
                      ),
                title: Text(item.product?.name ?? 'Producto'),
                subtitle: Text('Cantidad: ${item.quantity}'),
                trailing: Text(
                  '\$${(item.priceAtTimeOfOrder * item.quantity).toStringAsFixed(2)}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            )),
        
        const Divider(height: 32),
        
        // Resumen de precios
        _buildPriceRow('Subtotal', subtotal, theme),
        _buildPriceRow('Tarifa de entrega', _order.deliveryFee ?? 0, theme),
        const Divider(),
        _buildPriceRow('Total', _order.totalAmount, theme, isBold: true),
      ],
    );
  }

  Widget _buildPriceRow(String label, double amount, ThemeData theme, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(ThemeData theme) {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_statusHistory.isEmpty) {
      return const Center(child: Text('No hay historial de cambios'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _statusHistory.length,
      itemBuilder: (context, index) {
        final update = _statusHistory[index];
        final status = update.status;
        final formattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(update.createdAt);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(status.icon, color: status.color),
            ),
            title: Text(status.displayName),
            subtitle: Text(formattedDate),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          ),
        );
      },
    );
  }

  Widget _buildFinancesTab(ThemeData theme) {
    if (_isLoadingTransactions) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_transactions.isEmpty) {
      return const Center(child: Text('No hay transacciones'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final tx = _transactions[index];
        final isCredit = tx.amount > 0;
        final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(tx.createdAt);
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: tx.type.color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(tx.type.icon, color: tx.type.color),
            ),
            title: Text(tx.type.displayName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(formattedDate),
                if (tx.description != null) Text(tx.description!, style: const TextStyle(fontSize: 12)),
              ],
            ),
            trailing: Text(
              '${isCredit ? '+' : ''}\$${tx.amount.abs().toStringAsFixed(2)}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isCredit ? Colors.green : Colors.red,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoCard(String title, IconData icon, List<_InfoItem> items, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                          '${item.label}:',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.value,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;

  _InfoItem(this.label, this.value);
}
