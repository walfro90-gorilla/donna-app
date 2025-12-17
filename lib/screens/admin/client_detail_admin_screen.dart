import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/supabase/rpc_names.dart';
import 'package:doa_repartos/screens/admin/admin_account_ledger_screen.dart';
import 'package:intl/intl.dart';

/// Admin view: Full client details page with comprehensive data
class AdminClientDetailScreen extends StatefulWidget {
  final DoaUser client;
  const AdminClientDetailScreen({super.key, required this.client});

  @override
  State<AdminClientDetailScreen> createState() => _AdminClientDetailScreenState();
}

class _AdminClientDetailScreenState extends State<AdminClientDetailScreen> with SingleTickerProviderStateMixin {
  bool _loading = true;
  DoaUser? _client;
  DoaAccount? _account;
  List<DoaAccountTransaction> _transactions = [];
  List<DoaOrder> _orders = [];
  // Addresses or other related data could be loaded here
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
      final id = widget.client.id;

      // 1. Refresh User Data + Client Profile
      final userRaw = await SupabaseConfig.client
          .from('users')
          .select('*, client_profiles(*)')
          .eq('id', id)
          .maybeSingle();
      
      DoaUser? client;
      if (userRaw != null) {
        client = DoaUser.fromJson(userRaw);
      }

      // 2. Load Orders
      final ordersRaw = await SupabaseConfig.client
          .from('orders')
          .select('*')
          .eq('user_id', id)
          .order('created_at', ascending: false)
          .limit(50);
      final orders = (ordersRaw as List).map((j) => DoaOrder.fromJson(j)).toList();

      // 3. Load Account & Transactions
      DoaAccount? account;
      List<DoaAccountTransaction> tx = [];
      final accRaw = await SupabaseConfig.client
          .from('accounts')
          .select()
          .eq('user_id', id)
          .eq('account_type', 'client')
          .maybeSingle();
      
      if (accRaw != null) {
        account = DoaAccount.fromJson(accRaw);
        final txRaw = await SupabaseConfig.client
            .from('account_transactions')
            .select()
            .eq('account_id', account.id)
            .order('created_at', ascending: false)
            .limit(50);
        tx = (txRaw as List).map((j) => DoaAccountTransaction.fromJson(j)).toList();
      }

      if (!mounted) return;
      setState(() {
        _client = client ?? widget.client;
        _orders = orders;
        _account = account;
        _transactions = tx;
        _loading = false;
      });

    } catch (e) {
      debugPrint('Error loading client details: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _client ?? widget.client;
    final displayName = (c.name?.isNotEmpty ?? false) ? c.name! : c.email;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(displayName, style: const TextStyle(fontSize: 16)),
            const Text('Cliente', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.person), text: 'General'),
            Tab(icon: Icon(Icons.receipt_long), text: 'Pedidos'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'Finanzas'),
            Tab(icon: Icon(Icons.admin_panel_settings), text: 'Acciones'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAll,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralTab(c),
                _buildOrdersTab(),
                _buildFinancesTab(),
                _buildActionsTab(c),
              ],
            ),
    );
  }

  // === TABS ===

  Widget _buildGeneralTab(DoaUser c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(c),
        const SizedBox(height: 16),
        _buildLocationCard(c),
        const SizedBox(height: 16),
        _buildStatsCard(),
      ],
    );
  }

  Widget _buildOrdersTab() {
    if (_orders.isEmpty) {
      return const Center(child: Text('Sin pedidos registrados', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = _orders[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: order.status.color.withOpacity(0.1),
              child: Icon(order.status.icon, color: order.status.color),
            ),
            title: Text('Orden #${order.id.substring(0, 8)}'),
            subtitle: Text(DateFormat('dd MMM HH:mm').format(order.createdAt)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$${order.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  order.status.displayName,
                  style: TextStyle(fontSize: 12, color: order.status.color),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFinancesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildAccountSummary(),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Transacciones Recientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_account != null)
              TextButton(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => AdminAccountLedgerScreen(
                    account: _account!,
                    ownerName: _client?.name ?? 'Cliente',
                  )));
                },
                child: const Text('Ver historial completo'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_transactions.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('No hay transacciones'))
        else
          ..._transactions.map((t) => Card(
                elevation: 0,
                color: Colors.grey.shade50,
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8), 
                  side: BorderSide(color: Colors.grey.shade200)
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    t.amount >= 0 ? Icons.arrow_downward : Icons.arrow_upward,
                    color: t.amount >= 0 ? Colors.green : Colors.red,
                  ),
                  title: Text(t.type.name.replaceAll('_', ' ')),
                  subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(t.createdAt)),
                  trailing: Text(
                    '\$${t.amount.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: t.amount >= 0 ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              )).toList(),
      ],
    );
  }

  Widget _buildActionsTab(DoaUser c) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Acciones de Admin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.email),
                  title: const Text('Contactar (Email)'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: c.email));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Email copiado: ${c.email}')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: const Text('Contactar (Teléfono)'),
                  subtitle: Text(c.phone ?? 'No disponible'),
                  onTap: c.phone != null ? () {
                    Clipboard.setData(ClipboardData(text: c.phone!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Teléfono copiado: ${c.phone}')),
                    );
                  } : null,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.verified_user, color: Colors.blue),
                  title: const Text('Reparar Perfil/Cuenta'),
                  subtitle: const Text('Crear entradas faltantes en DB'),
                  onTap: () async {
                    try {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Función no implementada en este v1')));
                    } catch(e) { /* */ }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Eliminar Cuenta', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Soft delete si tiene historial, Hard delete si es nuevo'),
                  onTap: () => _confirmDeleteUser(c),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteUser(DoaUser c) async {
    // 1. Calcular Resumen
    final activeOrders = _orders.where((o) => !['delivered', 'cancelled', 'canceled', 'not_delivered'].contains(o.status.name)).length;
    final totalOrders = _orders.length;
    final balance = _account?.balance ?? 0.0;

    // 2. Mostrar Diálogo
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar Usuario?', style: TextStyle(color: Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Estás a punto de eliminar a "${c.name ?? c.email}".'),
            const SizedBox(height: 16),
            const Text('Resumen de datos:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _summaryItem('Pedidos Activos', '$activeOrders', isWarning: activeOrders > 0),
            _summaryItem('Historial de Pedidos', '$totalOrders'),
            _summaryItem('Saldo en Billetera', '\$${balance.toStringAsFixed(2)}', isWarning: balance > 0),
            const SizedBox(height: 16),
            if (activeOrders > 0)
              const Text('⚠️ NO SE PUEDE ELIMINAR mientras tenga pedidos activos.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
            else if (totalOrders > 0)
              const Text('ℹ️ Al tener historial, el usuario será "Anonimizado" (Soft Delete) para mantener la integridad de los registros.', style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              const Text('ℹ️ El usuario no tiene historial. Se eliminará permanentemente (Hard Delete).', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          if (activeOrders == 0)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ELIMINAR', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );

    if (confirm != true) return;

    // 3. Ejecutar RPC
    setState(() => _loading = true);
    try {
      final res = await SupabaseConfig.client.rpc(RpcNames.adminDeleteUser, params: {'p_user_id': c.id});
      
      if (mounted) {
        if (res['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['message'] ?? 'Usuario eliminado correctamente'),
            backgroundColor: Colors.green,
          ));
          Navigator.pop(context); // Volver atrás
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['message'] ?? 'Error al eliminar'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error RPC: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _summaryItem(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(isWarning ? Icons.warning : Icons.check_circle, size: 16, color: isWarning ? Colors.red : Colors.green),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: isWarning ? Colors.red : Colors.black)),
        ],
      ),
    );
  }

  // === WIDGETS ===

  Widget _buildHeaderCard(DoaUser c) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blue.shade100,
              backgroundImage: (c.profileImageUrl != null) ? NetworkImage(c.profileImageUrl!) : null,
              child: (c.profileImageUrl == null) 
                  ? Text(c.email[0].toUpperCase(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue))
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name ?? 'Sin Nombre',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Text(c.email, style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                       _statusChip(c.emailConfirm ? 'Verificado' : 'No Verificado', c.emailConfirm ? Colors.green : Colors.orange),
                       _statusChip('Rol: ${c.role.toString().split('.').last}', Colors.blue),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(DoaUser c) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             const Row(children: [Icon(Icons.location_on, color: Colors.red), SizedBox(width: 8), Text('Ubicación Principal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
             const SizedBox(height: 12),
             Text(c.formattedAddress ?? 'Sin dirección registrada'),
             if (c.lat != null && c.lon != null)
               Padding(
                 padding: const EdgeInsets.only(top: 8),
                 child: Text('Lat: ${c.lat}, Lon: ${c.lon}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
               ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final totalSpent = _orders.fold<double>(0, (sum, o) => sum + o.totalAmount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
             const Row(children: [Icon(Icons.bar_chart, color: Colors.purple), SizedBox(width: 8), Text('Estadísticas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
             const SizedBox(height: 12),
             Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem('Pedidos', '${_orders.length}'),
                  _statItem('Gasto Total', '\$${totalSpent.toStringAsFixed(0)}'),
                  _statItem('Antigüedad', '${DateTime.now().difference(_client?.createdAt ?? DateTime.now()).inDays} días'),
                ],
             )
          ],
        ),
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildAccountSummary() {
    if (_account == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No existe cuenta financiera')));
    }
    return Card(
      color: Colors.blue.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade200)
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('Balance de Billetera', style: TextStyle(fontSize: 14, color: Colors.blueGrey)),
            const SizedBox(height: 8),
            Text(
              '\$${_account!.balance.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 8),
            Text('ID: ${_account!.id}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
