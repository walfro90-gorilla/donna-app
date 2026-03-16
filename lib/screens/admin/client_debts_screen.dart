import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/session/session_manager.dart';

/// Pantalla de gestión de adeudos de clientes (órdenes no entregadas).
/// Permite confirmar pagos en efectivo y perdonar deudas.
/// Cada acción llama a RPCs que mantienen Balance 0 y desbloquean al cliente.
class ClientDebtsScreen extends StatefulWidget {
  const ClientDebtsScreen({super.key});

  @override
  State<ClientDebtsScreen> createState() => _ClientDebtsScreenState();
}

class _ClientDebtsScreenState extends State<ClientDebtsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;

  // Agrupados por status
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _paid = [];
  List<Map<String, dynamic>> _forgiven = [];
  List<Map<String, dynamic>> _disputed = [];

  final _fmt = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await SupabaseConfig.client
          .from('client_debts')
          .select('''
            id, amount, status, reason, fault_party, created_at, paid_at, forgiven_at,
            order_id,
            client:users!client_id(id, name, email, phone),
            order:orders!order_id(id, total_amount, payment_method, delivery_address)
          ''')
          .order('created_at', ascending: false);

      final all = List<Map<String, dynamic>>.from(data as List);

      setState(() {
        _pending  = all.where((d) => d['status'] == 'pending').toList();
        _paid     = all.where((d) => d['status'] == 'paid').toList();
        _forgiven = all.where((d) => d['status'] == 'forgiven').toList();
        _disputed = all.where((d) => d['status'] == 'disputed').toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [CLIENT_DEBTS] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando adeudos: $e')),
        );
      }
      setState(() => _loading = false);
    }
  }

  // ── Confirmar pago en efectivo ───────────────────────────────────────────────
  Future<void> _confirmPayment(Map<String, dynamic> debt) async {
    final client = debt['client'] as Map<String, dynamic>?;
    final clientName = client?['name'] ?? client?['email'] ?? 'Cliente';
    final amount = (debt['amount'] as num).toDouble();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Pago en Efectivo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.person_outline, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(child: Text(clientName, style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.payments_outlined, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text('Monto: ${_fmt.format(amount)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Esto marcará la deuda como pagada, desbloqueará al cliente '
                'y creará un settlement de recuperación hacia MASTER.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirmar Pago'),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final adminId = SessionManager.instance.currentSession!.userId;

    try {
      final result = await SupabaseConfig.client.rpc(
        'admin_confirm_client_debt_payment',
        params: {'p_debt_id': debt['id'], 'p_admin_id': adminId},
      );

      final res = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pago confirmado. Settlement creado. $clientName desbloqueado.',
            ),
            backgroundColor: Colors.green,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${res['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Perdonar deuda ───────────────────────────────────────────────────────────
  Future<void> _forgivDebt(Map<String, dynamic> debt) async {
    final client = debt['client'] as Map<String, dynamic>?;
    final clientName = client?['name'] ?? client?['email'] ?? 'Cliente';
    final amount = (debt['amount'] as num).toDouble();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Perdonar Deuda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: $clientName',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Monto: ${_fmt.format(amount)}',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Perdonar la deuda desbloqueará al cliente. MASTER absorberá '
                'la pérdida. El Balance 0 se mantiene con un settlement interno.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.volunteer_activism),
            label: const Text('Perdonar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final adminId = SessionManager.instance.currentSession!.userId;

    try {
      // Llama RPC que crea el settlement contable + desbloquea al cliente
      final result = await SupabaseConfig.client.rpc(
        'admin_forgive_client_debt',
        params: {
          'p_debt_id': debt['id'],
          'p_admin_id': adminId,
          'p_reason': 'admin_decision',
        },
      );

      final res = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deuda perdonada. $clientName desbloqueado.'),
            backgroundColor: Colors.orange,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${res['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Culpa del repartidor ──────────────────────────────────────────────────────
  Future<void> _setDeliveryFault(Map<String, dynamic> debt) async {
    final client = debt['client'] as Map<String, dynamic>?;
    final clientName = client?['name'] ?? client?['email'] ?? 'Cliente';
    final amount = (debt['amount'] as num).toDouble();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delivery_dining, color: Colors.deepOrange),
            const SizedBox(width: 8),
            const Text('Culpa del Repartidor'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: $clientName',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Monto: ${_fmt.format(amount)}'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepOrange.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.deepOrange.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '• El cliente quedará exonerado y desbloqueado.\n'
                '• Se penalizará al repartidor revirtiendo su ganancia.\n'
                '• MASTER absorberá la pérdida.\n'
                '• Balance 0 se mantiene.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.delivery_dining),
            label: const Text('Confirmar'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final adminId = SessionManager.instance.currentSession!.userId;

    try {
      final result = await SupabaseConfig.client.rpc(
        'admin_set_delivery_fault',
        params: {
          'p_debt_id': debt['id'],
          'p_admin_id': adminId,
          'p_notes': 'Determinado por admin tras revisión de evidencia',
        },
      );

      final res = Map<String, dynamic>.from(result as Map);
      if (!mounted) return;

      if (res['success'] == true) {
        final penalty = (res['penalty_amount'] as num?)?.toDouble() ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$clientName exonerado. Repartidor penalizado ${_fmt.format(penalty)}.',
            ),
            backgroundColor: Colors.deepOrange,
          ),
        );
        await _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${res['error']}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adeudos de Clientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pendientes'),
                  if (_pending.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _badge(_pending.length, Colors.red),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Pagados'),
            const Tab(text: 'Perdonados'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Disputados'),
                  if (_disputed.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _badge(_disputed.length, Colors.orange),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _debtList(_pending, showActions: true),
                _debtList(_paid, showActions: false),
                _debtList(_forgiven, showActions: false),
                _debtList(_disputed, showActions: false),
              ],
            ),
      // Resumen flotante de pendientes
      bottomNavigationBar: _pending.isEmpty
          ? null
          : _buildSummaryBar(cs),
    );
  }

  Widget _buildSummaryBar(ColorScheme cs) {
    final total = _pending.fold<double>(
      0,
      (sum, d) => sum + (d['amount'] as num).toDouble(),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        border: Border(top: BorderSide(color: cs.error.withValues(alpha: 0.3))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_pending.length} adeudo${_pending.length != 1 ? 's' : ''} pendiente${_pending.length != 1 ? 's' : ''}',
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontSize: 12,
                ),
              ),
              Text(
                _fmt.format(total),
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          Text(
            'Por recuperar en MASTER',
            style: TextStyle(color: cs.onErrorContainer, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Lista de deudas ──────────────────────────────────────────────────────────
  Widget _debtList(List<Map<String, dynamic>> debts, {required bool showActions}) {
    if (debts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'Sin adeudos en esta categoría',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
        itemCount: debts.length,
        itemBuilder: (_, i) => _debtCard(debts[i], showActions: showActions),
      ),
    );
  }

  Widget _debtCard(Map<String, dynamic> debt, {required bool showActions}) {
    final client = debt['client'] as Map<String, dynamic>?;
    final order = debt['order'] as Map<String, dynamic>?;
    final clientName = client?['name'] ?? client?['email'] ?? 'Cliente';
    final clientEmail = client?['email'] ?? '';
    final amount = (debt['amount'] as num).toDouble();
    final status = debt['status'] as String;
    final faultParty = debt['fault_party'] as String? ?? 'client';
    final reason = debt['reason'] as String? ?? 'not_delivered';
    final createdAt = DateTime.tryParse(debt['created_at'] as String? ?? '');
    final orderId = debt['order_id'] as String? ?? '';
    final paymentMethod = order?['payment_method'] as String? ?? 'cash';
    final address = order?['delivery_address'] as String? ?? '—';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabecera ──────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.red.withValues(alpha: 0.12),
                  foregroundColor: Colors.red,
                  child: const Icon(Icons.money_off),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clientName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(clientEmail,
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                // Monto
                Text(
                  _fmt.format(amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            // ── Detalles ──────────────────────────────────────────────────────
            _infoRow(Icons.tag, 'Orden', '#${orderId.substring(0, 8)}'),
            _infoRow(Icons.location_on_outlined, 'Dirección', address),
            _infoRow(
              Icons.report_problem_outlined,
              'Motivo',
              _reasonLabel(reason),
            ),
            _infoRow(
              Icons.payment_outlined,
              'Pago original',
              paymentMethod == 'cash' ? 'Efectivo' : 'Tarjeta',
            ),
            if (createdAt != null)
              _infoRow(Icons.calendar_today_outlined, 'Fecha',
                  _dateFmt.format(createdAt.toLocal())),
            const SizedBox(height: 10),
            // ── Badges: status + culpable ─────────────────────────────────────
            Row(
              children: [
                _statusBadge(status),
                const SizedBox(width: 8),
                _faultBadge(faultParty),
              ],
            ),
            // ── Acciones ──────────────────────────────────────────────────────
            if (showActions) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.volunteer_activism, size: 18),
                      label: const Text('Perdonar'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.orange),
                      ),
                      onPressed: () => _forgivDebt(debt),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Cobrado'),
                      style: FilledButton.styleFrom(
                          backgroundColor: Colors.green),
                      onPressed: () => _confirmPayment(debt),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delivery_dining, size: 18),
                  label: const Text('Culpa del Repartidor'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepOrange,
                    side: const BorderSide(color: Colors.deepOrange),
                  ),
                  onPressed: () => _setDeliveryFault(debt),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final cfg = switch (status) {
      'pending'  => (Colors.red, Icons.hourglass_empty, 'Pendiente'),
      'paid'     => (Colors.green, Icons.check_circle, 'Pagado'),
      'forgiven' => (Colors.orange, Icons.volunteer_activism, 'Perdonado'),
      'disputed' => (Colors.purple, Icons.gavel, 'En Disputa'),
      _          => (Colors.grey, Icons.help_outline, status),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cfg.$1.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cfg.$2, size: 14, color: cfg.$1),
          const SizedBox(width: 4),
          Text(cfg.$3,
              style: TextStyle(
                  fontSize: 12, color: cfg.$1, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _faultBadge(String faultParty) {
    final cfg = switch (faultParty) {
      'client'   => (Colors.red[700]!, Icons.person_off_outlined, 'Culpa Cliente'),
      'delivery' => (Colors.deepOrange, Icons.delivery_dining, 'Culpa Repartidor'),
      'platform' => (Colors.blue, Icons.business_outlined, 'Plataforma'),
      _          => (Colors.grey, Icons.help_outline, 'Por determinar'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cfg.$1.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cfg.$1.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(cfg.$2, size: 13, color: cfg.$1),
          const SizedBox(width: 4),
          Text(cfg.$3,
              style: TextStyle(
                  fontSize: 11, color: cfg.$1, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _badge(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _reasonLabel(String reason) => switch (reason) {
    'not_delivered'  => 'No entregado',
    'client_no_show' => 'Cliente no estaba',
    'fake_address'   => 'Dirección falsa',
    _                => reason,
  };
}
