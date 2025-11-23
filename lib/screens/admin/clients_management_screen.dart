import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';

/// Administración de Clientes
/// Lista usuarios con role "client" y muestra datos de client_profiles + acciones
class ClientsManagementScreen extends StatefulWidget {
  const ClientsManagementScreen({super.key});

  @override
  State<ClientsManagementScreen> createState() => _ClientsManagementScreenState();
}

class _ClientsManagementScreenState extends State<ClientsManagementScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  List<DoaUser> _all = [];
  List<DoaUser> _filtered = [];

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Leer usuarios con role 'client' y su client_profiles
      final data = await SupabaseConfig.client
          .from('users')
          .select('''
            id, email, name, phone, role, created_at, updated_at, email_confirm,
            client_profiles(*)
          ''')
          .eq('role', 'client')
          .order('created_at', ascending: false);

      final list = (data as List)
          .map((j) => DoaUser.fromJson(Map<String, dynamic>.from(j)))
          .toList();

      setState(() {
        _all = list;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [ADMIN/CLIENTS] Error cargando clientes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando clientes: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filtered = _all);
      return;
    }
    setState(() {
      _filtered = _all.where((u) {
        final name = (u.name ?? '').toLowerCase();
        final email = u.email.toLowerCase();
        final phone = (u.phone ?? '').toLowerCase();
        final addr = (u.formattedAddress ?? '').toLowerCase();
        return name.contains(q) || email.contains(q) || phone.contains(q) || addr.contains(q);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, email, teléfono o dirección',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _filtered.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Sin clientes')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) => _clientTile(_filtered[i]),
                    ),
            ),
    );
  }

  Widget _clientTile(DoaUser u) {
    final displayName = (u.name?.isNotEmpty ?? false) ? u.name! : u.email;
    final addr = u.formattedAddress ?? '—';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.1),
                  foregroundColor: Colors.blue,
                  child: const Icon(Icons.person),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(u.email, style: TextStyle(color: Colors.grey[700])),
                      if ((u.phone ?? '').isNotEmpty)
                        Text(u.phone!, style: TextStyle(color: Colors.grey[700])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (u.emailConfirm ? Colors.green : Colors.orange).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(u.emailConfirm ? Icons.verified : Icons.mark_email_unread, size: 16, color: u.emailConfirm ? Colors.green : Colors.orange),
                    const SizedBox(width: 6),
                    Text(u.emailConfirm ? 'VERIFICADO' : 'PENDIENTE', style: TextStyle(fontSize: 11, color: u.emailConfirm ? Colors.green : Colors.orange)),
                  ]),
                )
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.location_on, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(addr, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[700]))),
            ]),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: const Text('Pedidos'),
                  onPressed: () => _showOrders(u.id),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.account_balance_wallet, size: 18),
                  label: const Text('Cuenta'),
                  onPressed: () => _showAccount(u.id, displayName),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_location_alt, size: 18),
                  label: const Text('Editar dirección'),
                  onPressed: () => _editAddress(u),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.verified_user, size: 18),
                  label: const Text('Asegurar perfil'),
                  onPressed: () => _ensureProfile(u.id),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Future<void> _ensureProfile(String userId) async {
    try {
      await SupabaseClientProfileExtensions.ensureClientProfileAndAccount(userId: userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil y cuenta verificados')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _editAddress(DoaUser u) async {
    final controller = TextEditingController(text: u.formattedAddress ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dirección de ${u.name ?? u.email}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder()),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DoaRepartosService.updateClientDefaultAddress(userId: u.id, address: controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dirección actualizada')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showOrders(String userId) async {
    try {
      final data = await SupabaseConfig.client
          .from('orders')
          .select('id, status, total_amount, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(30);

      final orders = (data as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: const [Icon(Icons.list_alt, color: Colors.blue), SizedBox(width: 8), Text('Pedidos del cliente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))]),
              const SizedBox(height: 12),
              Flexible(
                child: orders.isEmpty
                    ? const Center(child: Text('Sin pedidos'))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: orders.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final o = orders[i];
                          final id = o['id']?.toString() ?? '';
                          final status = (o['status'] ?? '').toString();
                          final total = (o['total_amount'] as num?)?.toDouble() ?? 0.0;
                          final created = (o['created_at'] ?? '').toString();
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.receipt_long),
                            title: Text('#$id • ${status.toUpperCase()}'),
                            subtitle: Text(created.split('T').first),
                            trailing: Text('${total.toStringAsFixed(2)} mxn', style: const TextStyle(fontWeight: FontWeight.bold)),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
              )
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leyendo pedidos: $e')));
    }
  }

  Future<void> _showAccount(String userId, String name) async {
    try {
      Map<String, dynamic>? account;
      List<Map<String, dynamic>> tx = [];
      try {
        account = await SupabaseConfig.client
            .from('accounts')
            .select()
            .eq('user_id', userId)
            .eq('account_type', 'client')
            .maybeSingle();
        if (account != null) {
          final accId = account!['id'];
          final rawTx = await SupabaseConfig.client
              .from('account_transactions')
              .select()
              .eq('account_id', accId)
              .order('created_at', ascending: false)
              .limit(20);
          tx = (rawTx as List).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('⚠️ Cuenta cliente no disponible: $e');
      }

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [const Icon(Icons.account_balance_wallet, color: Colors.teal), const SizedBox(width: 8), Expanded(child: Text('Cuenta de $name', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))]),
              const SizedBox(height: 8),
              if (account == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: const Text('Sin cuenta de cliente. Usa "Asegurar perfil" para crearla.'),
                )
              else
                Row(
                  children: [
                    const Text('Balance: ', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('${((account['balance'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)} mxn', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              const SizedBox(height: 12),
              Flexible(
                child: tx.isEmpty
                    ? const Center(child: Text('Sin transacciones'))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemBuilder: (context, i) {
                          final t = tx[i];
                          final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
                          final type = (t['type'] ?? '').toString();
                          final date = (t['created_at'] ?? '').toString();
                          return ListTile(
                            dense: true,
                            leading: Icon(amount >= 0 ? Icons.arrow_downward : Icons.arrow_upward, color: amount >= 0 ? Colors.green : Colors.red),
                            title: Text(type.replaceAll('_', ' ')),
                            subtitle: Text(date.split('T').first),
                            trailing: Text('${amount.toStringAsFixed(2)} mxn', style: TextStyle(color: amount >= 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: tx.length,
                      ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                ),
              )
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leyendo cuenta: $e')));
    }
  }
}
