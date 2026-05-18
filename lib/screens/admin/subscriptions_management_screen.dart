import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/core/services/admin_service.dart';
import 'package:doa_repartos/core/services/billing_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/admin/billing_settings_screen.dart';
import 'package:doa_repartos/screens/admin/subscription_detail_screen.dart';

class SubscriptionsManagementScreen extends StatefulWidget {
  const SubscriptionsManagementScreen({super.key});

  @override
  State<SubscriptionsManagementScreen> createState() => _SubscriptionsManagementScreenState();
}

class _SubscriptionsManagementScreenState extends State<SubscriptionsManagementScreen> {
  final _admin = AdminService();
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final _date  = DateFormat('dd/MM/yyyy');

  bool _loading = true;
  String? _roleFilter;
  String? _statusFilter;
  List<DoaSubscription> _subs = [];
  BillingModeConfig? _mode;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mode = await BillingService.instance.getMode(force: true);
      final subs = await _admin.listSubscriptions(
        role: _roleFilter,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _subs = subs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<DoaSubscription> get _filtered {
    if (_search.trim().isEmpty) return _subs;
    final q = _search.toLowerCase();
    return _subs.where((s) {
      return s.displayName.toLowerCase().contains(q) ||
          (s.userEmail ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuotas mensuales'),
        actions: [
          IconButton(
            tooltip: 'Configuración del modo',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const BillingSettingsScreen(),
              ));
              if (mounted) _load();
            },
          ),
          IconButton(
            tooltip: 'Refrescar',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _modeBanner(),
                  const SizedBox(height: 12),
                  _filtersRow(),
                  const SizedBox(height: 12),
                  if (_filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'No hay suscripciones que coincidan',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  else
                    ..._filtered.map(_subscriptionTile),
                ],
              ),
            ),
    );
  }

  Widget _modeBanner() {
    final mode = _mode;
    if (mode == null) return const SizedBox.shrink();
    final isSub = mode.isSubscription;
    return Card(
      color: isSub
          ? Colors.green.withValues(alpha: 0.08)
          : Colors.blueGrey.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(isSub ? Icons.event_repeat : Icons.percent,
                color: isSub ? Colors.green : Colors.blueGrey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modo activo: ${isSub ? "Renta mensual" : "Comisión por pedido"}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSub
                        ? 'Restaurantes \$${mode.subscriptionFeeRestaurant.toStringAsFixed(0)}/mes · Repartidores \$${mode.subscriptionFeeDelivery.toStringAsFixed(0)}/mes · ${mode.graceDays} días de gracia'
                        : 'Las cuotas mensuales NO se cobran en este modo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtersRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por nombre o email',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        DropdownButton<String?>(
          value: _roleFilter,
          hint: const Text('Rol: todos'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Rol: todos')),
            DropdownMenuItem(value: 'restaurant', child: Text('Restaurantes')),
            DropdownMenuItem(value: 'delivery_agent', child: Text('Repartidores')),
          ],
          onChanged: (v) {
            setState(() => _roleFilter = v);
            _load();
          },
        ),
        DropdownButton<String?>(
          value: _statusFilter,
          hint: const Text('Estado: todos'),
          items: const [
            DropdownMenuItem(value: null, child: Text('Estado: todos')),
            DropdownMenuItem(value: 'active', child: Text('Activa')),
            DropdownMenuItem(value: 'past_due', child: Text('Vencida')),
            DropdownMenuItem(value: 'suspended', child: Text('Suspendida')),
            DropdownMenuItem(value: 'cancelled', child: Text('Cancelada')),
          ],
          onChanged: (v) {
            setState(() => _statusFilter = v);
            _load();
          },
        ),
      ],
    );
  }

  Widget _subscriptionTile(DoaSubscription s) {
    final daysLeft = s.daysUntilDue;
    final dueColor = daysLeft < 0
        ? Colors.red
        : (daysLeft <= 7 ? Colors.orange : Colors.green);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: s.status.color.withValues(alpha: 0.18),
          child: Icon(
            s.role == 'restaurant' ? Icons.store : Icons.delivery_dining,
            color: s.status.color,
          ),
        ),
        title: Text(s.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s.role == "restaurant" ? "Restaurante" : "Repartidor"} · ${_money.format(s.monthlyFee)}/mes'),
            Row(
              children: [
                Chip(
                  label: Text(s.status.displayName),
                  backgroundColor: s.status.color.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                if (s.nextDueDate != null)
                  Text(
                    'Vence: ${_date.format(s.nextDueDate!)} (${daysLeft >= 0 ? "$daysLeft" : daysLeft}d)',
                    style: TextStyle(color: dueColor, fontWeight: FontWeight.w500),
                  ),
                if (s.openInvoices > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${s.openInvoices} pend.',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => SubscriptionDetailScreen(subscription: s),
          ));
          if (mounted) _load();
        },
      ),
    );
  }
}
