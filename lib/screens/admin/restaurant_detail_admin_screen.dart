import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/screens/orders/order_details_screen.dart';
import 'package:doa_repartos/screens/admin/admin_account_ledger_screen.dart';
import 'package:intl/intl.dart';

/// Admin view: Full restaurant details page with comprehensive data
/// Displays all restaurant information, orders, products, reviews, finances and admin actions
class AdminRestaurantDetailScreen extends StatefulWidget {
  final DoaRestaurant restaurant;
  const AdminRestaurantDetailScreen({super.key, required this.restaurant});

  @override
  State<AdminRestaurantDetailScreen> createState() => _AdminRestaurantDetailScreenState();
}

class _AdminRestaurantDetailScreenState extends State<AdminRestaurantDetailScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  DoaRestaurant? _restaurant;
  DoaUser? _owner;
  List<DoaProduct> _products = [];
  List<DoaOrder> _orders = [];
  Map<String, dynamic> _analytics = const {};
  double _avgRating = 0;
  int _totalReviews = 0;
  List<Map<String, dynamic>> _reviews = const [];
  DoaAccount? _account;
  List<DoaAccountTransaction> _recentTx = [];
  
  // Tab controller for sections
  late TabController _tabController;
  
  // Filters
  String _orderStatusFilter = 'all';
  String _productTypeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final id = widget.restaurant.id;

      // Restaurant + owner with full data
      final restRaw = await SupabaseConfig.client
          .from('restaurants')
          .select('*, users:user_id (id, email, name, phone, created_at)')
          .eq('id', id)
          .maybeSingle();

      DoaRestaurant? rest;
      DoaUser? owner;
      if (restRaw != null) {
        rest = DoaRestaurant.fromJson(restRaw);
        if (restRaw['users'] != null) {
          owner = DoaUser.fromJson(Map<String, dynamic>.from(restRaw['users']));
        }
      }

      // Products
      final productsRaw = await SupabaseConfig.client
          .from('products')
          .select()
          .eq('restaurant_id', id)
          .order('name', ascending: true);
      final products = productsRaw.map((j) => DoaProduct.fromJson(j)).toList();

      // Orders with items
      final ordersRaw = await SupabaseConfig.client
          .from('orders')
          .select('*, order_items(*)')
          .eq('restaurant_id', id)
          .order('created_at', ascending: false)
          .limit(50);
      final orders = ordersRaw.map((j) => DoaOrder.fromJson(j)).toList();

      // Calculate analytics from orders
      final totalOrders = orders.length;
      final totalRevenue = orders.fold<double>(0, (sum, o) => sum + (o.totalAmount - (o.deliveryFee ?? 0)));
      final completedOrders = orders.where((o) => o.status == OrderStatus.delivered).length;
      final analytics = {
        'total_orders': totalOrders,
        'total_revenue': totalRevenue,
        'completed_orders': completedOrders,
      };

      // Reviews
      final reviewsRaw = await SupabaseConfig.client
          .from('reviews')
          .select('rating, comment, created_at, users:author_id (name)')
          .eq('subject_restaurant_id', id)
          .order('created_at', ascending: false)
          .limit(10);
      double avg = 0;
      int total = 0;
      if (reviewsRaw is List) {
        total = reviewsRaw.length;
        if (total > 0) {
          avg = reviewsRaw
                  .map((e) => (e['rating'] as num?)?.toDouble() ?? 0)
                  .fold<double>(0, (a, b) => a + b) /
              total;
        }
      }

      // Account and last transactions
      DoaAccount? account;
      List<DoaAccountTransaction> tx = [];
      if (rest != null) {
        final accRaw = await SupabaseConfig.client
            .from('accounts')
            .select()
            .eq('user_id', rest.userId)
            .maybeSingle();
        if (accRaw != null) {
          account = DoaAccount.fromJson(accRaw);
          final txRaw = await SupabaseConfig.client
              .from('account_transactions')
              .select()
              .eq('account_id', account.id)
              .order('created_at', ascending: false)
              .limit(10);
          tx = txRaw
              .map<DoaAccountTransaction>((j) => DoaAccountTransaction.fromJson(j))
              .toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _restaurant = rest ?? widget.restaurant;
        _owner = owner;
        _products = products;
        _orders = orders;
        _analytics = analytics;
        _avgRating = avg;
        _totalReviews = total;
        _reviews = List<Map<String, dynamic>>.from(reviewsRaw as List? ?? []);
        _account = account;
        _recentTx = tx;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando restaurante: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _restaurant ?? widget.restaurant;
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.name),
            Text(
              r.status.displayName.toUpperCase(),
              style: TextStyle(fontSize: 12, color: r.status.color),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
            tooltip: 'Recargar',
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              if (r.status == RestaurantStatus.pending)
                const PopupMenuItem(value: 'approve', child: Row(children: [Icon(Icons.check, color: Colors.green), SizedBox(width: 8), Text('Aprobar')])),
              if (r.status == RestaurantStatus.pending)
                const PopupMenuItem(value: 'reject', child: Row(children: [Icon(Icons.close, color: Colors.red), SizedBox(width: 8), Text('Rechazar')])),
              const PopupMenuItem(value: 'edit_commission', child: Row(children: [Icon(Icons.percent), SizedBox(width: 8), Text('Editar comisión')])),
              const PopupMenuItem(value: 'toggle_online', child: Row(children: [Icon(Icons.toggle_on), SizedBox(width: 8), Text('Cambiar estado online')])),
              const PopupMenuItem(value: 'contact_owner', child: Row(children: [Icon(Icons.email), SizedBox(width: 8), Text('Contactar propietario')])),
            ],
            onSelected: (value) => _handleAdminAction(value.toString()),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.info), text: 'General'),
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Productos'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Órdenes'),
            Tab(icon: Icon(Icons.star), text: 'Reseñas'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Finanzas'),
            Tab(icon: Icon(Icons.settings), text: 'Configuración'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGeneralTab(r),
                  _buildProductsTab(),
                  _buildOrdersTab(),
                  _buildReviewsTab(),
                  _buildFinancesTab(),
                  _buildConfigTab(r),
                ],
              ),
            ),
    );
  }

  // ===== TABS =====
  Widget _buildGeneralTab(DoaRestaurant r) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildHeader(r),
      const SizedBox(height: 16),
      _buildOwnerInfo(),
      const SizedBox(height: 16),
      _buildBusinessInfo(r),
      const SizedBox(height: 16),
      _buildQuickStats(r),
    ],
  );

  Widget _buildProductsTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Productos (${_products.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('Todos')),
              ButtonSegment(value: 'principal', label: Text('Principal')),
              ButtonSegment(value: 'extra', label: Text('Extra')),
              ButtonSegment(value: 'combo', label: Text('Combo')),
            ],
            selected: {_productTypeFilter},
            onSelectionChanged: (v) => setState(() => _productTypeFilter = v.first),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildProductsGrid(),
    ],
  );

  Widget _buildOrdersTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Órdenes (${_orders.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          DropdownButton<String>(
            value: _orderStatusFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Todas')),
              DropdownMenuItem(value: 'pending', child: Text('Pendientes')),
              DropdownMenuItem(value: 'delivered', child: Text('Entregadas')),
              DropdownMenuItem(value: 'cancelled', child: Text('Canceladas')),
            ],
            onChanged: (v) => setState(() => _orderStatusFilter = v ?? 'all'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      _buildOrdersList(),
    ],
  );

  Widget _buildReviewsTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildRatingOverview(),
      const SizedBox(height: 16),
      _buildReviewsList(),
    ],
  );

  Widget _buildFinancesTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildFinancials(),
    ],
  );

  Widget _buildConfigTab(DoaRestaurant r) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _buildConfigSection(r),
    ],
  );

  // ===== ADMIN ACTIONS =====
  Future<void> _handleAdminAction(String action) async {
    final r = _restaurant ?? widget.restaurant;
    
    switch (action) {
      case 'approve':
        await _approveRestaurant(r);
        break;
      case 'reject':
        await _rejectRestaurant(r);
        break;
      case 'edit_commission':
        await _editCommission(r);
        break;
      case 'toggle_online':
        await _toggleOnline(r);
        break;
      case 'contact_owner':
        _contactOwner();
        break;
    }
  }

  Future<void> _approveRestaurant(DoaRestaurant r) async {
    try {
      await SupabaseConfig.client
          .from('restaurants')
          .update({'status': 'approved'})
          .eq('id', r.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Restaurante aprobado')),
      );
      _loadAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _rejectRestaurant(DoaRestaurant r) async {
    try {
      await SupabaseConfig.client
          .from('restaurants')
          .update({'status': 'rejected'})
          .eq('id', r.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Restaurante rechazado')),
      );
      _loadAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _editCommission(DoaRestaurant r) async {
    final controller = TextEditingController(text: (r.commissionBps / 100).toStringAsFixed(2));
    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar comisión'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Comisión (%)',
            helperText: 'Ingresa el porcentaje (ej: 15 para 15%)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              if (value != null && value >= 0 && value <= 30) {
                Navigator.pop(context, value);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Valor inválido (0-30%)')),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    
    if (result != null) {
      try {
        await SupabaseConfig.client
            .from('restaurants')
            .update({'commission_bps': (result * 100).toInt()})
            .eq('id', r.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Comisión actualizada a ${result.toStringAsFixed(2)}%')),
        );
        _loadAll();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _toggleOnline(DoaRestaurant r) async {
    try {
      await SupabaseConfig.client
          .from('restaurants')
          .update({'online': !r.online})
          .eq('id', r.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.online ? '⚫ Restaurante offline' : '🟢 Restaurante online')),
      );
      _loadAll();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _contactOwner() {
    if (_owner?.email != null) {
      Clipboard.setData(ClipboardData(text: _owner!.email));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📧 Email copiado: ${_owner!.email}')),
      );
    }
  }

  // ===== UI COMPONENTS =====

  Widget _buildHeader(DoaRestaurant r) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: r.coverImageUrl != null && r.coverImageUrl!.isNotEmpty
                ? Image.network(r.coverImageUrl!, fit: BoxFit.cover)
                : Container(color: Colors.grey.shade200),
          ),
          Container(
            height: 180,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            right: 16,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  backgroundImage: (r.logoUrl != null && r.logoUrl!.isNotEmpty)
                      ? NetworkImage(r.logoUrl!)
                      : null,
                  child: (r.logoUrl == null || r.logoUrl!.isEmpty)
                      ? const Icon(Icons.restaurant, color: Colors.grey, size: 32)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _chip(
                            icon: r.status.icon,
                            label: r.status.displayName,
                            color: r.status.color,
                          ),
                          _chip(
                            icon: Icons.star,
                            label: _avgRating.toStringAsFixed(1),
                            color: Colors.amber,
                          ),
                          if (r.cuisineType != null && r.cuisineType!.isNotEmpty)
                            _chip(icon: Icons.local_dining, label: r.cuisineType!, color: Colors.blue),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildOwnerInfo() {
    if (_owner == null) return const SizedBox();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('Propietario', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            _infoRow(Icons.email, 'Email', _owner!.email),
            if (_owner!.phone != null) _infoRow(Icons.phone, 'Teléfono', _owner!.phone!),
            if (_owner!.name != null) _infoRow(Icons.badge, 'Nombre', _owner!.name!),
            _infoRow(Icons.calendar_today, 'Registrado', _formatDate(_owner!.createdAt)),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessInfo(DoaRestaurant r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.business, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Información del negocio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            if (r.description != null && r.description!.isNotEmpty)
              _infoRow(Icons.description, 'Descripción', r.description!),
            if (r.address != null) _infoRow(Icons.location_on, 'Dirección', r.address!),
            if (r.phone != null) _infoRow(Icons.phone_in_talk, 'Teléfono negocio', r.phone!),
            if (r.cuisineType != null) _infoRow(Icons.restaurant, 'Tipo de cocina', r.cuisineType!),
            _infoRow(Icons.access_time, 'Tiempo entrega estimado', '${r.estimatedDeliveryTimeMinutes ?? 30} min'),
            _infoRow(Icons.delivery_dining, 'Radio de entrega', '${r.deliveryRadiusKm ?? 5} km'),
            _infoRow(Icons.attach_money, 'Pedido mínimo', _formatCurrency(r.minOrderAmount ?? 0)),
            const SizedBox(height: 12),
            if (r.businessHours != null) _buildBusinessHours(r.businessHours!),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildImagePreview('Logo', r.logoUrl)),
                const SizedBox(width: 8),
                Expanded(child: _buildImagePreview('Portada', r.coverImageUrl)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildImagePreview('Fachada', r.facadeImageUrl)),
                const SizedBox(width: 8),
                Expanded(child: _buildImagePreview('Menú', r.menuImageUrl)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildImagePreview('Permiso negocio', r.businessPermitUrl)),
                const SizedBox(width: 8),
                Expanded(child: _buildImagePreview('Permiso salud', r.healthPermitUrl)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessHours(Map<String, dynamic> hours) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Horario:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...hours.entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(width: 80, child: Text(e.key, style: TextStyle(color: Colors.grey.shade700))),
              Text(e.value.toString()),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildImagePreview(String label, String? url) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: url != null && url.isNotEmpty ? () => _showImageDialog(url) : null,
          child: Container(
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: url != null && url.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(url, fit: BoxFit.cover, width: double.infinity),
                  )
                : const Center(child: Icon(Icons.image_not_supported, color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(url, fit: BoxFit.contain),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigSection(DoaRestaurant r) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Configuración del restaurante', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 24),
            _configTile('Estado', r.status.displayName, r.status.color),
            _configTile('Online', r.online ? 'Sí' : 'No', r.online ? Colors.green : Colors.red),
            _configTile('Comisión', '${(r.commissionBps / 100).toStringAsFixed(2)}%', Colors.blue),
            _configTile('Onboarding completado', r.onboardingCompleted ? 'Sí' : 'No', r.onboardingCompleted ? Colors.green : Colors.orange),
            _configTile('Paso de onboarding', '${r.onboardingStep}', Colors.purple),
            _configTile('Completitud del perfil', '${r.profileCompletionPercentage}%', Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _configTile(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    final filtered = _orderStatusFilter == 'all'
        ? _orders
        : _orders.where((o) {
            if (_orderStatusFilter == 'pending') return o.status == OrderStatus.pending || o.status == OrderStatus.confirmed || o.status == OrderStatus.inPreparation;
            if (_orderStatusFilter == 'delivered') return o.status == OrderStatus.delivered;
            if (_orderStatusFilter == 'cancelled') return o.status == OrderStatus.canceled;
            return true;
          }).toList();

    if (filtered.isEmpty) {
      return _emptyState('No hay órdenes en este filtro');
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final o = filtered[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: o.status.color.withValues(alpha: 0.2),
              child: Icon(o.status.icon, color: o.status.color),
            ),
            title: Text('Orden #${o.id.substring(0, 8)}'),
            subtitle: Text('${_formatDate(o.createdAt)} - ${o.status.displayName}'),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_formatCurrency(o.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${o.items?.length ?? 0} items', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: o)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRatingOverview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Column(
                  children: [
                    Text(
                      _avgRating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < _avgRating.round() ? Icons.star : Icons.star_border,
                        color: Colors.amber.shade700,
                        size: 20,
                      )),
                    ),
                    Text('$_totalReviews reseñas', style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: Column(
                    children: [
                      _ratingBar(5, _reviews.where((r) => r['rating'] == 5).length, _totalReviews),
                      _ratingBar(4, _reviews.where((r) => r['rating'] == 4).length, _totalReviews),
                      _ratingBar(3, _reviews.where((r) => r['rating'] == 3).length, _totalReviews),
                      _ratingBar(2, _reviews.where((r) => r['rating'] == 2).length, _totalReviews),
                      _ratingBar(1, _reviews.where((r) => r['rating'] == 1).length, _totalReviews),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingBar(int stars, int count, int total) {
    final percent = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$stars', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          const Icon(Icons.star, size: 12, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percent,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.amber.shade700,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 30,
            child: Text('$count', style: const TextStyle(fontSize: 12), textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats(DoaRestaurant r) {
    final cells = <_StatCell>[
      _StatCell(Icons.email, _owner?.email ?? '—', 'Email propietario'),
      _StatCell(Icons.phone, _owner?.phone ?? '—', 'Teléfono'),
      _StatCell(Icons.place, r.address ?? '—', 'Dirección'),
      _StatCell(Icons.receipt_long, (_analytics['total_orders'] ?? 0).toString(), 'Órdenes totales'),
      _StatCell(Icons.payments, _formatCurrency((_analytics['total_revenue'] ?? 0).toDouble()), 'Ingresos totales'),
      _StatCell(Icons.calendar_today, _formatDate(r.createdAt), 'Creado'),
    ];

    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(builder: (context, c) {
          final width = c.maxWidth;
          final perRow = width > 1000
              ? 6
              : width > 700
                  ? 3
                  : 2;
          return Wrap(
            runSpacing: 12,
            spacing: 12,
            children: [
              for (final cell in cells)
                SizedBox(
                  width: (width - (perRow - 1) * 12) / perRow,
                  child: _buildStatTile(cell),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildStatTile(_StatCell cell) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cell.icon, color: Colors.blue, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cell.title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text(cell.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsGrid() {
    final filtered = _productTypeFilter == 'all'
        ? _products
        : _products.where((p) => p.type == _productTypeFilter).toList();

    if (filtered.isEmpty) {
      return _emptyState('No hay productos en este filtro');
    }
    
    return LayoutBuilder(builder: (context, c) {
      final width = c.maxWidth;
      final perRow = width > 1100
          ? 4
          : width > 800
              ? 3
              : width > 500
                  ? 2
                  : 1;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final p in filtered)
            SizedBox(width: (width - (perRow - 1) * 12) / perRow, child: _productTile(p)),
        ],
      );
    });
  }

  Widget _productTile(DoaProduct p) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: p.imageUrl != null && p.imageUrl!.isNotEmpty
                ? Image.network(p.imageUrl!, fit: BoxFit.cover)
                : Container(color: Colors.grey.shade200, child: const Icon(Icons.image, color: Colors.grey)),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (p.isAvailable ? Colors.green : Colors.red).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(p.isAvailable ? 'Disponible' : 'No disp.', style: TextStyle(color: p.isAvailable ? Colors.green : Colors.red, fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(p.description ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 8),
                Text(_formatCurrency(p.price), style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsList() {
    if (_reviews.isEmpty) {
      return _emptyState('Este restaurante aún no tiene reseñas');
    }
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _reviews.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final r = _reviews[i];
          final user = r['users'];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text(
                user != null && user['name'] != null && user['name'].toString().isNotEmpty
                    ? user['name'].toString()[0].toUpperCase()
                    : '?',
                style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Icon(Icons.star, color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 4),
                Text('${r['rating']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_formatDate(DateTime.tryParse(r['created_at'] ?? '') ?? DateTime.now()), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            subtitle: Text(r['comment']?.toString() ?? ''),
          );
        },
      ),
    );
  }

  Widget _buildFinancials() {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _moneyTile('Balance de cuenta', _formatCurrency(_account?.balance ?? 0))),
                const SizedBox(width: 12),
                Expanded(child: _moneyTile('Ingresos totales', _formatCurrency((_analytics['total_revenue'] ?? 0).toDouble()))),
                const SizedBox(width: 12),
                Expanded(child: _moneyTile('Órdenes totales', (_analytics['total_orders'] ?? 0).toString())),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Últimas transacciones', style: TextStyle(fontWeight: FontWeight.w600)),
                if (_account != null)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminAccountLedgerScreen(
                            account: _account!,
                            ownerName: _restaurant?.name ?? 'Restaurante',
                          ),
                        ),
                      );
                    },
                    child: const Text('Ver historial completo'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_recentTx.isEmpty) _emptyState('Sin transacciones') else _transactionsList(),
          ],
        ),
      ),
    );
  }

  Widget _moneyTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _transactionsList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _recentTx.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = _recentTx[i];
        final c = t.type.color;
        return ListTile(
          leading: CircleAvatar(backgroundColor: c.withValues(alpha: 0.15), child: Icon(t.type.icon, color: c)),
          title: Text(t.type.displayName),
          subtitle: Text(_formatDate(t.createdAt)),
          trailing: Text(
            (t.amount >= 0 ? '+' : '-') + _formatCurrency(t.amount.abs()),
            style: TextStyle(color: t.amount >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.w600),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) Icon(icon, color: Colors.blue),
        if (icon != null) const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _emptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.grey),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return '${formatter.format(value)} mxn';
  }

  String _formatDate(DateTime d) {
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
    return '$day/$m/$y';
  }
}

class _StatCell {
  final IconData icon;
  final String value;
  final String title;
  const _StatCell(this.icon, this.value, this.title);
}
