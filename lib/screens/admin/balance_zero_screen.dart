import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/services/financial_service.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/theme.dart';

class BalanceZeroScreen extends StatefulWidget {
  const BalanceZeroScreen({super.key});

  @override
  State<BalanceZeroScreen> createState() => _BalanceZeroScreenState();
}

class _BalanceZeroScreenState extends State<BalanceZeroScreen> {
  bool _loading = true;
  DateTimeRange? _range;
  String _orderIdFilter = '';
  String _typeFilter = 'ALL';
  List<Map<String, dynamic>> _txs = [];
  int _txVisibleCount = 6; // pagination for visible transactions

  // Accounts metadata (UI only)
  Map<String, Map<String, dynamic>> _accounts = {}; // id -> {account_type, balance}
  String? _appAccountId;

  // Admin accounts dataset and labels
  final FinancialService _financial = FinancialService();
  List<DoaAccount> _allAccounts = [];
  String? _platformAccountId;
  final Map<String, String> _userNamesById = {}; // user_id -> name/email
  final Map<String, String> _restaurantNamesByUserId = {}; // user_id -> restaurant name

  // Computed
  double _globalNet = 0.0;
  int _totalOrders = 0;
  int _unbalancedOrders = 0;
  List<_OrderBalance> _topUnbalanced = [];
  Map<String, double> _totalsByType = {};
  Map<DateTime, double> _dailyNet = {};

  // Per-account metrics
  Map<String, double> _netByAccount = {}; // in selected range
  Map<String, Map<DateTime, double>> _dailyByAccount = {}; // per account per day

  final _numberFmt = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7)),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) Get transactions within filters
      var query = SupabaseConfig.client.from('account_transactions').select();

      if (_range != null) {
        query = query
            .gte('created_at', _range!.start.toIso8601String())
            .lte('created_at', _range!.end.toIso8601String());
      }
      if (_orderIdFilter.trim().isNotEmpty) {
        query = query.eq('order_id', _orderIdFilter.trim());
      }
      if (_typeFilter != 'ALL') {
        query = query.eq('type', _typeFilter);
      } else {
        // EXCLUDE CLIENT_DEBT from balance calculations (only show paid/completed transactions)
        query = query.neq('type', 'CLIENT_DEBT');
      }

      final data = await query.order('created_at', ascending: false).limit(500);
      final List<Map<String, dynamic>> items =
          (data as List).map((e) => Map<String, dynamic>.from(e)).toList();

      // 2) Get minimal accounts metadata for labeling and app account detection
      final accountsRaw = await SupabaseConfig.client
          .from('accounts')
          .select('id, account_type, balance, user_id')
          .order('created_at', ascending: false);
      _accounts = {
        for (final a in (accountsRaw as List)) a['id'].toString(): Map<String, dynamic>.from(a)
      };

      // Detect app account by conventional types
      _appAccountId = _accounts.entries.firstWhere(
        (e) {
          final t = (e.value['account_type']?.toString() ?? '').toLowerCase();
          return t == 'platform' || t == 'app' || t == 'system' || t == 'platform_app';
        },
        orElse: () => _accounts.entries.isNotEmpty ? _accounts.entries.first : const MapEntry('', {}),
      ).key;
      if (_appAccountId != null && _appAccountId!.isEmpty) _appAccountId = null; // guard

      // 3) Admin dataset for drilldowns and labels (RLS-aware via service)
      List<DoaAccount> allAcc = [];
      String? platformId;
      try {
        allAcc = await _financial.adminListAllAccounts();
      } catch (e) {
        debugPrint('⚠️ [BALANCE ZERO] adminListAllAccounts fallo: $e');
      }
      try {
        platformId = await _financial.getPlatformAccountId();
      } catch (_) {}

      // Build label maps
      final userIds = allAcc.map((a) => a.userId).where((id) => id.isNotEmpty).toSet().toList();
      if (userIds.isNotEmpty) {
        try {
          final usersRows = await SupabaseConfig.client.from('users').select('id, name, email').inFilter('id', userIds);
          for (final row in usersRows) {
            final id = row['id']?.toString() ?? '';
            final name = (row['name']?.toString().trim().isNotEmpty ?? false)
                ? row['name'].toString().trim()
                : (row['email']?.toString() ?? '');
            if (id.isNotEmpty && name.isNotEmpty) {
              _userNamesById[id] = name;
            }
          }
        } catch (e) {
          debugPrint('⚠️ [BALANCE ZERO] No se pudieron leer nombres de users: $e');
        }
      }
      final restUserIds = allAcc
          .where((a) => a.accountType == AccountType.restaurant)
          .map((a) => a.userId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (restUserIds.isNotEmpty) {
        try {
          final restRows = await SupabaseConfig.client
              .from('restaurants')
              .select('user_id, name')
              .inFilter('user_id', restUserIds);
          for (final r in restRows) {
            final uid = r['user_id']?.toString() ?? '';
            final rname = r['name']?.toString() ?? '';
            if (uid.isNotEmpty && rname.isNotEmpty) {
              _restaurantNamesByUserId[uid] = rname;
            }
          }
        } catch (e) {
          debugPrint('⚠️ [BALANCE ZERO] No se pudieron leer nombres de restaurantes: $e');
        }
      }

      _recompute(items);

      if (mounted) {
        setState(() {
          _allAccounts = allAcc;
          _platformAccountId = platformId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando transacciones: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recompute(List<Map<String, dynamic>> items) {
    // Ensure newest-to-oldest ordering
    items.sort((a, b) {
      final ad = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    _txs = items;
    _txVisibleCount = _txs.isEmpty ? 0 : (_txs.length >= 6 ? 6 : _txs.length);

    // Global net
    _globalNet = 0.0;
    for (final t in items) {
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      _globalNet += amt;
    }

    // Per order sum
    final Map<String, double> byOrder = {};
    for (final t in items) {
      final orderId = t['order_id']?.toString();
      if (orderId == null || orderId.isEmpty) continue;
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      byOrder.update(orderId, (v) => v + amt, ifAbsent: () => amt);
    }
    _totalOrders = byOrder.length;

    const double epsilon = 0.01; // $0.01 tolerance
    final List<_OrderBalance> unbalanced = [];
    byOrder.forEach((orderId, net) {
      if (net.abs() > epsilon) {
        unbalanced.add(_OrderBalance(orderId: orderId, net: net));
      }
    });
    unbalanced.sort((a, b) => b.net.abs().compareTo(a.net.abs()));
    _unbalancedOrders = unbalanced.length;
    _topUnbalanced = unbalanced.take(20).toList();

    // Totals by type (absolute for proportions)
    _totalsByType = {};
    for (final t in items) {
      final type = t['type']?.toString() ?? 'UNKNOWN';
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      _totalsByType.update(type, (v) => v + amt.abs(), ifAbsent: () => amt.abs());
    }

    // Daily net (global)
    _dailyNet = {};
    for (final t in items) {
      final createdAtStr = t['created_at']?.toString();
      if (createdAtStr == null) continue;
      final dt = DateTime.tryParse(createdAtStr) ?? DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      _dailyNet.update(day, (v) => v + amt, ifAbsent: () => amt);
    }

    // Per-account aggregates
    _netByAccount = {};
    _dailyByAccount = {};
    for (final t in items) {
      final accountId = t['account_id']?.toString();
      if (accountId == null || accountId.isEmpty) continue;
      final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
      _netByAccount.update(accountId, (v) => v + amt, ifAbsent: () => amt);

      // Daily per account
      final createdAtStr = t['created_at']?.toString();
      final dt = DateTime.tryParse(createdAtStr ?? '') ?? DateTime.now();
      final day = DateTime(dt.year, dt.month, dt.day);
      final m = _dailyByAccount.putIfAbsent(accountId, () => {});
      m.update(day, (v) => v + amt, ifAbsent: () => amt);
    }
  }

  Future<void> _pickRange() async {
    final initial = _range;
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      saveText: 'Aplicar',
      helpText: 'Rango de fechas',
    );
    if (picked != null) {
      setState(() => _range = DateTimeRange(
            start: DateTime(picked.start.year, picked.start.month, picked.start.day),
            end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
          ));
      _load();
    }
  }

  Color _typeColor(String type) {
    // Prefer readable color coding; keep consistent with charts and list
    switch (type) {
      case 'ORDER_REVENUE':
        return Colors.green;
      case 'PLATFORM_COMMISSION':
        return Colors.red;
      case 'DELIVERY_EARNING':
        return Colors.blue;
      case 'CASH_COLLECTED':
        return Colors.orange;
      case 'SETTLEMENT_PAYMENT':
        return Colors.teal;
      case 'SETTLEMENT_RECEPTION':
        return Colors.purple;
      case 'RESTAURANT_PAYABLE':
        return Colors.lightGreen;
      case 'DELIVERY_PAYABLE':
        return Colors.lightBlue;
      case 'PLATFORM_DELIVERY_MARGIN':
        return Colors.amber;
      case 'PLATFORM_NOT_DELIVERED_REFUND':
        return Colors.deepOrange;
      case 'CLIENT_DEBT':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final okGlobal = _globalNet.abs() < 0.01;
    final okOrders = _unbalancedOrders == 0;
    final allOk = okGlobal && okOrders;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance 0'),
        // Allow theme to control colors; keep action
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFilters(),
                  const SizedBox(height: 12),
                  _buildStatusCard(allOk, okGlobal, okOrders),
                  const SizedBox(height: 16),
                  _buildAccountTypeSummary(),
                  const SizedBox(height: 16),
                  _buildCharts(),
                  const SizedBox(height: 16),
                  if (_unbalancedOrders > 0) _buildUnbalancedOrders(),
                  const SizedBox(height: 16),
                  _buildTransactionsList(),
                ],
              ),
            ),
      backgroundColor: scheme.surface,
    );
  }

  Widget _buildFilters() {
    final scheme = Theme.of(context).colorScheme;
    String rangeLabel = 'Todo';
    if (_range != null) {
      final df = DateFormat('yyyy-MM-dd');
      rangeLabel = '${df.format(_range!.start)} → ${df.format(_range!.end)}';
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          runSpacing: 8,
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: 'Seleccionar rango de fechas',
              child: TextButton.icon(
                onPressed: _pickRange,
                icon: Icon(Icons.date_range, color: scheme.primary),
                label: Text(rangeLabel, style: TextStyle(color: scheme.onSurface)),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Filtrar por Order ID',
                  prefixIcon: const Icon(Icons.filter_alt),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => _orderIdFilter = v,
                onSubmitted: (_) => _load(),
              ),
            ),
            DropdownButton<String>(
              value: _typeFilter,
              items: const [
                DropdownMenuItem(value: 'ALL', child: Text('Todos los tipos')),
                DropdownMenuItem(value: 'ORDER_REVENUE', child: Text('ORDER_REVENUE')),
                DropdownMenuItem(value: 'PLATFORM_COMMISSION', child: Text('PLATFORM_COMMISSION')),
                DropdownMenuItem(value: 'DELIVERY_EARNING', child: Text('DELIVERY_EARNING')),
                DropdownMenuItem(value: 'CASH_COLLECTED', child: Text('CASH_COLLECTED')),
                DropdownMenuItem(value: 'SETTLEMENT_PAYMENT', child: Text('SETTLEMENT_PAYMENT')),
                DropdownMenuItem(value: 'SETTLEMENT_RECEPTION', child: Text('SETTLEMENT_RECEPTION')),
                DropdownMenuItem(value: 'RESTAURANT_PAYABLE', child: Text('RESTAURANT_PAYABLE')),
                DropdownMenuItem(value: 'DELIVERY_PAYABLE', child: Text('DELIVERY_PAYABLE')),
                DropdownMenuItem(value: 'PLATFORM_DELIVERY_MARGIN', child: Text('PLATFORM_DELIVERY_MARGIN')),
                DropdownMenuItem(value: 'PLATFORM_NOT_DELIVERED_REFUND', child: Text('PLATFORM_NOT_DELIVERED_REFUND')),
                DropdownMenuItem(value: 'CLIENT_DEBT', child: Text('CLIENT_DEBT')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _typeFilter = v);
                _load();
              },
            ),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.search),
              label: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(bool allOk, bool okGlobal, bool okOrders) {
    final scheme = Theme.of(context).colorScheme;
    final Color base = allOk ? Colors.green : Colors.red;
    final Color bg = base.withValues(alpha: 0.12);
    final Color fg = Theme.of(context).colorScheme.onSurface;
    final Color borderColor = base;
    final Color iconColor = base;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(allOk ? Icons.verified : Icons.error_outline, color: iconColor, size: 28),
              const SizedBox(width: 8),
              Text(
                allOk ? 'Balance OK (0)' : 'Desbalance detectado',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: fg,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _metricChip(label: 'Global net', value: '${_numberFmt.format(_globalNet)} MXN', ok: okGlobal),
              _metricChip(label: 'Órdenes no balanceadas', value: '$_unbalancedOrders / $_totalOrders', ok: okOrders),
              _metricChip(label: 'Transacciones', value: '${_txs.length}', ok: true),
            ],
          )
        ],
      ),
    );
  }

  Widget _metricChip({required String label, required String value, required bool ok}) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(ok ? Icons.check_circle : Icons.warning, color: ok ? scheme.secondary : scheme.error),
      label: Text('$label: $value', style: TextStyle(color: scheme.onSurface)),
      backgroundColor: scheme.surfaceVariant,
      side: BorderSide(color: ok ? scheme.secondary.withValues(alpha: 0.4) : scheme.error.withValues(alpha: 0.4)),
    );
  }

  // Summary cards by account type with drilldown and dynamic status colors
  Widget _buildAccountTypeSummary() {
    final scheme = Theme.of(context).colorScheme;

    // Compute counts and totals from available metadata
    final platformId = _platformAccountId ?? _appAccountId;
    final Iterable<MapEntry<String, Map<String, dynamic>>> metaEntries = _accounts.entries;

    bool isRestaurantRaw(Map<String, dynamic> acc) {
      final t = (acc['account_type']?.toString() ?? '').toLowerCase();
      return t.startsWith('restaur');
    }

    bool isDeliveryRaw(Map<String, dynamic> acc) {
      final t = (acc['account_type']?.toString() ?? '').toLowerCase();
      return t.startsWith('delivery');
    }

    bool isClientRaw(Map<String, dynamic> acc) {
      final t = (acc['account_type']?.toString() ?? '').toLowerCase();
      return t.startsWith('client') || t.startsWith('customer') || t.startsWith('user');
    }

    bool isMasterRaw(Map<String, dynamic> acc) {
      final t = (acc['account_type']?.toString() ?? '').toLowerCase();
      return t == 'platform' || t == 'app' || t == 'system' || t == 'platform_app' ||
          t == 'platform_revenue' || t == 'platform_payables' || t == 'revenue' || t == 'payables';
    }

    // Prepare id buckets by category
    final List<String> restaurantIds = [];
    final List<String> deliveryIds = [];
    final List<String> clientIds = [];
    final List<String> masterIds = [];

    // Aggregates by category (sum of balances)
    int restaurantsCount = 0;
    double restaurantsTotal = 0;
    int deliveryCount = 0;
    double deliveryTotal = 0;
    int clientsCount = 0;
    double clientsTotal = 0;
    int masterCount = 0;
    double masterTotal = 0;

    for (final e in metaEntries) {
      final id = e.key;
      final m = e.value;
      final bal = (m['balance'] is num)
          ? (m['balance'] as num).toDouble()
          : double.tryParse(m['balance']?.toString() ?? '0') ?? 0.0;
      final typeIsMaster = isMasterRaw(m);
      final isPlatform = platformId != null && platformId == id;
      if (isPlatform || typeIsMaster) {
        masterCount += 1;
        masterTotal += bal;
        masterIds.add(id);
        continue;
      }
      if (isRestaurantRaw(m)) {
        restaurantsCount += 1;
        restaurantsTotal += bal;
        restaurantIds.add(id);
      } else if (isDeliveryRaw(m)) {
        deliveryCount += 1;
        deliveryTotal += bal;
        deliveryIds.add(id);
      } else if (isClientRaw(m)) {
        clientsCount += 1;
        clientsTotal += bal;
        clientIds.add(id);
      }
    }

    // Net del período por categoría (usa _netByAccount en el rango seleccionado)
    double netPeriodFor(List<String> ids) {
      double s = 0.0;
      for (final id in ids) {
        s += _netByAccount[id] ?? 0.0;
      }
      return s;
    }

    final double restaurantsNet = netPeriodFor(restaurantIds);
    final double deliveryNet = netPeriodFor(deliveryIds);
    final double clientsNet = netPeriodFor(clientIds);
    final double masterNet = netPeriodFor(masterIds);

    Color colorForTotal(double total) {
      const double eps = 0.01;
      if (total < -eps) return Colors.red;
      if (total > eps) return Colors.green;
      return Colors.blue; // near zero
    }

    String statusForTotal(double total) {
      const double eps = 0.01;
      if (total < -eps) return 'Deuda';
      if (total > eps) return 'Saldo';
      return 'Saldada';
    }

    Widget tile({
      required String title,
      required String subtitle,
      required double total,
      required double netPeriod,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      final color = colorForTotal(total);
      final status = statusForTotal(total);
      final onSurface = Theme.of(context).colorScheme.onSurface;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border.all(color: color.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Leading icon badge
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: TextStyle(color: onSurface.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.outline),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${_numberFmt.format(total)} MXN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.today, size: 18, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Net del periodo: ${_numberFmt.format(netPeriod)} MXN',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cols = maxW >= 1200 ? 4 : (maxW >= 900 ? 3 : 1);
        final w = cols > 1 ? (maxW / cols) - 12 : maxW;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: w,
              child: tile(
                title: 'Restaurantes',
                subtitle: '$restaurantsCount cuentas · Total: ${_numberFmt.format(restaurantsTotal)} MXN',
                total: restaurantsTotal,
                netPeriod: restaurantsNet,
                icon: Icons.store,
                onTap: () => _openCategoryDrilldown('restaurant'),
              ),
            ),
            SizedBox(
              width: w,
              child: tile(
                title: 'Repartidores',
                subtitle: '$deliveryCount cuentas · Total: ${_numberFmt.format(deliveryTotal)} MXN',
                total: deliveryTotal,
                netPeriod: deliveryNet,
                icon: Icons.delivery_dining,
                onTap: () => _openCategoryDrilldown('delivery_agent'),
              ),
            ),
            SizedBox(
              width: w,
              child: tile(
                title: 'Clientes',
                subtitle: '$clientsCount cuentas · Total: ${_numberFmt.format(clientsTotal)} MXN',
                total: clientsTotal,
                netPeriod: clientsNet,
                icon: Icons.person,
                onTap: () => _openCategoryDrilldown('client'),
              ),
            ),
            SizedBox(
              width: w,
              child: tile(
                title: 'MASTER',
                subtitle: '$masterCount cuentas · Total: ${_numberFmt.format(masterTotal)} MXN',
                total: masterTotal,
                netPeriod: masterNet,
                icon: Icons.account_balance_wallet,
                onTap: () => _openCategoryDrilldown('master'),
              ),
            ),
          ],
        );
      },
    );
  }

  // SECTION: Per-account cards (retained for future use; not used in current summary)
  Widget _buildAccountCardsSection() {
    if (_netByAccount.isEmpty && _accounts.isEmpty) return const SizedBox.shrink();

    // Build list of account ids sorted: app first, then by absolute net desc
    final accountIds = _netByAccount.keys.toList();
    accountIds.sort((a, b) => _netByAccount[b]!.abs().compareTo(_netByAccount[a]!.abs()));
    if (_appAccountId != null && accountIds.contains(_appAccountId)) {
      accountIds.remove(_appAccountId);
      accountIds.insert(0, _appAccountId!);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        final cardWidth = isWide ? constraints.maxWidth / 2 - 10 : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final id in accountIds) SizedBox(width: cardWidth, child: _accountCard(id)),
          ],
        );
      },
    );
  }

  Widget _accountCard(String accountId) {
    final acc = _accounts[accountId] ?? {};
    final typeRaw = (acc['account_type']?.toString() ?? '').toLowerCase();
    final isApp = accountId == _appAccountId;

    final title = isApp
        ? 'Cuenta de la App'
        : typeRaw == 'restaurant'
            ? 'Cuenta Restaurante'
            : typeRaw == 'delivery_agent'
                ? 'Cuenta Repartidor'
                : 'Cuenta';

    final icon = isApp
        ? Icons.account_balance_wallet
        : typeRaw == 'restaurant'
            ? Icons.store
            : typeRaw == 'delivery_agent'
                ? Icons.delivery_dining
                : Icons.account_balance;

    final net = _netByAccount[accountId] ?? 0.0;
    final currentBalance = (acc['balance'] as num?)?.toDouble() ?? 0.0;
    const double epsilon = 0.01;
    final bool isZero = currentBalance.abs() < epsilon;
    final bool isDebt = currentBalance < -epsilon;

    // Prepare last N days series (max 10)
    final dailyMap = (_dailyByAccount[accountId] ?? {});
    final days = dailyMap.keys.toList()..sort();
    final lastDays = days.length > 10 ? days.sublist(days.length - 10) : days;

    final scheme = Theme.of(context).colorScheme;
    final bgColor = isZero
        ? scheme.primary
        : (isDebt
            ? scheme.error
            : scheme.secondary);
    final subtitle = isZero
        ? 'Cuenta al día'
        : (isDebt ? 'Cuenta con deuda por liquidar' : 'Cuenta con dinero por cobrar');

    return InkWell(
      onTap: () => _openAccountTransactions(accountId: accountId, title: title),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [bgColor.withValues(alpha: 0.95), bgColor.withValues(alpha: 0.85)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: bgColor.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.account_balance, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Chip(
                  label: Text(isZero ? 'Al día' : (isDebt ? 'Deuda' : 'Saldo'), style: const TextStyle(color: Colors.white)),
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                )
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_numberFmt.format(currentBalance)} MXN',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.today, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Net del periodo: ${_numberFmt.format(net)} MXN',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= lastDays.length) return const SizedBox.shrink();
                          final d = lastDays[i];
                          return Text(DateFormat('MM/dd').format(d), style: const TextStyle(color: Colors.white, fontSize: 9));
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < lastDays.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: (dailyMap[lastDays[i]] ?? 0.0),
                            color: (dailyMap[lastDays[i]] ?? 0) >= 0 ? Colors.lightGreenAccent : Colors.orangeAccent,
                            width: 10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      )
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCharts() {
    if (_txs.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    // Pie data
    final typeEntries = _totalsByType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final totalAbs = typeEntries.fold<double>(0, (s, e) => s + e.value);

    // Line data
    final dailyEntries = _dailyNet.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 900;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            Container(
              width: isWide ? constraints.maxWidth / 2 - 10 : constraints.maxWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Composición por tipo', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 48,
                        sections: typeEntries.map((e) {
                          final percent = totalAbs > 0 ? (e.value / totalAbs) * 100 : 0;
                          return PieChartSectionData(
                            color: _typeColor(e.key),
                            value: e.value,
                            title: '${percent.toStringAsFixed(0)}%\n${e.key}',
                            radius: 80,
                            titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: isWide ? constraints.maxWidth / 2 - 10 : constraints.maxWidth,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Net diario', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: LineChart(
                      LineChartData(
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, reservedSize: 42),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= dailyEntries.length) return const SizedBox.shrink();
                                final day = dailyEntries[index].key;
                                return Text(DateFormat('MM-dd').format(day), style: const TextStyle(fontSize: 10));
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: true),
                        gridData: FlGridData(show: true),
                        lineTouchData: const LineTouchData(enabled: true),
                        lineBarsData: [
                          LineChartBarData(
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            spots: [
                              for (int i = 0; i < dailyEntries.length; i++) FlSpot(i.toDouble(), dailyEntries[i].value),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUnbalancedOrders() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: scheme.error),
                const SizedBox(width: 8),
                Text('Órdenes con desbalance (${_topUnbalanced.length}/${_unbalancedOrders})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                final ob = _topUnbalanced[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.error.withValues(alpha: 0.12),
                    child: Icon(Icons.receipt_long, color: scheme.error),
                  ),
                  title: Text('Order ${ob.orderId}'),
                  subtitle: const Text('Suma de transacciones != 0'),
                  trailing: Text(
                    '${_numberFmt.format(ob.net)} MXN',
                    style: TextStyle(fontWeight: FontWeight.bold, color: scheme.error),
                  ),
                );
              },
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemCount: _topUnbalanced.length,
            )
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList() {
    final scheme = Theme.of(context).colorScheme;
    final List<Map<String, dynamic>> displayed = _txs.take(_txVisibleCount).toList();
    return Card(
      elevation: 0,
      color: scheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transacciones (${_txs.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (displayed.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Sin transacciones'),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final t = displayed[index];
                  final type = t['type']?.toString() ?? 'UNKNOWN';
                  final createdAt = DateTime.tryParse(t['created_at']?.toString() ?? '') ?? DateTime.now();
                  final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;

                  final isPositive = amount >= 0;
                  final amtColor = isPositive ? Colors.green : Colors.red;

                  return ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _typeColor(type).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.swap_vert, color: _typeColor(type)),
                    ),
                    title: Text(type),
                    subtitle: Text('Orden: ${t['order_id'] ?? '-'}  ·  ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt.toLocal())}'),
                    trailing: Text(
                      '${_numberFmt.format(amount)} MXN',
                      style: TextStyle(fontWeight: FontWeight.bold, color: amtColor),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemCount: displayed.length,
              ),
            if (_txVisibleCount < _txs.length) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _txVisibleCount = (_txVisibleCount + 10) > _txs.length ? _txs.length : _txVisibleCount + 10;
                    });
                  },
                  icon: const Icon(Icons.expand_more),
                  label: const Text('Cargar 10 más'),
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  // Drilldown modal for accounts by category
  void _openAccountsList(String category) {
    final isMaster = category == 'master';
    final isRestaurant = category == 'restaurant';
    final isDelivery = category == 'delivery_agent';

    final platformId = _platformAccountId ?? _appAccountId;

    // Filter accounts from _accounts meta to preserve balances if DoaAccount lacks platform typing
    final List<String> ids = _accounts.keys.where((id) {
      final acc = _accounts[id] ?? {};
      final type = (acc['account_type']?.toString() ?? '').toLowerCase();
      if (isMaster) return platformId != null && id == platformId;
      if (isRestaurant) return type.startsWith('restaur') && (platformId == null || id != platformId);
      if (isDelivery) return type.startsWith('delivery') && (platformId == null || id != platformId);
      return false;
    }).toList();

    ids.sort((a, b) {
      final balA = ((_accounts[a]?['balance']) as num?)?.toDouble() ?? 0.0;
      final balB = ((_accounts[b]?['balance']) as num?)?.toDouble() ?? 0.0;
      return balB.abs().compareTo(balA.abs());
    });

    String modalTitle = isMaster
        ? 'Cuentas MASTER'
        : isRestaurant
            ? 'Restaurantes'
            : 'Repartidores';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.8;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(modalTitle, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.separated(
                  itemCount: ids.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, index) {
                    final id = ids[index];
                    final raw = _accounts[id] ?? {};
                    final bal = (raw['balance'] is num)
                        ? (raw['balance'] as num).toDouble()
                        : double.tryParse(raw['balance']?.toString() ?? '0') ?? 0.0;
                    final userId = (raw['user_id']?.toString() ?? '');
                    final label = _buildAccountDisplayLabel(id: id, userId: userId, rawType: raw['account_type']?.toString());

                    const double eps = 0.01;
                    final Color amtColor = bal > eps
                        ? Colors.green
                        : (bal < -eps ? Colors.red : Colors.blue);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: amtColor.withValues(alpha: 0.12),
                        child: Icon(
                          isMaster
                              ? Icons.account_balance_wallet
                              : isRestaurant
                                  ? Icons.store
                                  : Icons.delivery_dining,
                          color: amtColor,
                        ),
                      ),
                      title: Text(label),
                      subtitle: Text('ID: ${_short(id)}'),
                      trailing: Text(
                        _numberFmt.format(bal),
                        style: TextStyle(fontWeight: FontWeight.bold, color: amtColor),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _buildAccountDisplayLabel({required String id, required String userId, String? rawType}) {
    final isPlatform = (_platformAccountId != null && id == _platformAccountId) || (_appAccountId != null && id == _appAccountId);
    if (isPlatform) {
      return 'Cuenta Master • ${_short(id)}';
    }
    final typeStr = (rawType ?? '').toLowerCase();
    if (typeStr.startsWith('restaur')) {
      final restName = _restaurantNamesByUserId[userId];
      final fallback = _userNamesById[userId] ?? _short(userId);
      final name = (restName != null && restName.trim().isNotEmpty) ? restName : fallback;
      return 'Restaurante • $name';
    }
    if (typeStr.startsWith('delivery')) {
      final name = _userNamesById[userId] ?? _short(userId);
      return 'Repartidor • $name';
    }
    if (typeStr.startsWith('client') || typeStr.startsWith('customer') || typeStr.startsWith('user')) {
      final name = _userNamesById[userId] ?? _short(userId);
      return 'Cliente • $name';
    }
    return 'Cuenta • ${_short(id)}';
  }

  // Drilldown sheet with tabs (Transacciones / Cuentas) for a category
  void _openCategoryDrilldown(String category) {
    final isMaster = category == 'master';
    final isRestaurant = category == 'restaurant';
    final isDelivery = category == 'delivery_agent';
    final isClient = category == 'client';
    final platformId = _platformAccountId ?? _appAccountId;

    // 1) Account ids for the category
    final List<String> ids = _accounts.keys.where((id) {
      final acc = _accounts[id] ?? {};
      final type = (acc['account_type']?.toString() ?? '').toLowerCase();
      if (isMaster) {
        final isPlat = platformId != null && id == platformId;
        final isPlatTypes = type == 'platform_revenue' || type == 'platform_payables' ||
            type == 'platform' || type == 'app' || type == 'system' || type == 'platform_app';
        return isPlat || isPlatTypes;
      }
      if (isRestaurant) return type.startsWith('restaur') && (platformId == null || id != platformId);
      if (isDelivery) return type.startsWith('delivery') && (platformId == null || id != platformId);
      if (isClient) return (type.startsWith('client') || type.startsWith('customer') || type.startsWith('user')) && (platformId == null || id != platformId);
      return false;
    }).toList();

    // 2) Transactions filtered by those account ids
    final List<Map<String, dynamic>> catTxs = _txs
        .where((t) {
          final aid = t['account_id']?.toString() ?? '';
          return ids.contains(aid);
        })
        .toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

    String modalTitle = isMaster
        ? 'Cuentas MASTER'
        : isRestaurant
            ? 'Restaurantes'
            : isDelivery
                ? 'Repartidores'
                : 'Clientes';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.85;
        return DefaultTabController(
          length: 2,
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        modalTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                const TabBar(
                  tabs: [
                    Tab(icon: Icon(Icons.swap_vert), text: 'Transacciones'),
                    Tab(icon: Icon(Icons.account_balance_wallet), text: 'Cuentas'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: Transacciones del tipo de cuenta seleccionado
                      _CategoryTransactionsList(
                        txs: catTxs,
                        numberFmt: _numberFmt,
                        typeColor: _typeColor,
                      ),
                      // Tab 2: Cuentas de la categoría
                      _CategoryAccountsList(
                        ids: ids,
                        accounts: _accounts,
                        isMaster: isMaster,
                        isRestaurant: isRestaurant,
                        isDelivery: isDelivery,
                        numberFmt: _numberFmt,
                        labelBuilder: ({required String id, required String userId, String? rawType}) =>
                            _buildAccountDisplayLabel(id: id, userId: userId, rawType: rawType),
                        shortener: _short,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openAccountTransactions({required String accountId, String? title}) {
    final filtered = _txs
        .where((t) => (t['account_id']?.toString() ?? '') == accountId)
        .toList()
      ..sort((a, b) {
        final ad = DateTime.tryParse(a['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = DateTime.tryParse(b['created_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

    final acc = _accounts[accountId] ?? {};
    final label = title ?? _buildAccountDisplayLabel(
      id: accountId,
      userId: (acc['user_id']?.toString() ?? ''),
      rawType: acc['account_type']?.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.8;
        return SizedBox(
          height: height,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _CategoryTransactionsList(
                  txs: filtered,
                  numberFmt: _numberFmt,
                  typeColor: _typeColor,
                ),
              )
            ],
          ),
        );
      },
    );
  }

  String _short(String id) => id.length <= 8 ? id : '${id.substring(0, 4)}…${id.substring(id.length - 4)}';
}

// Helper widgets for category drilldown
class _CategoryTransactionsList extends StatelessWidget {
  final List<Map<String, dynamic>> txs;
  final NumberFormat numberFmt;
  final Color Function(String type) typeColor;
  const _CategoryTransactionsList({super.key, required this.txs, required this.numberFmt, required this.typeColor});

  @override
  Widget build(BuildContext context) {
    if (txs.isEmpty) {
      return const Center(child: Text('Sin transacciones en el rango seleccionado'));
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: txs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final t = txs[index];
        final type = t['type']?.toString() ?? 'UNKNOWN';
        final createdAt = DateTime.tryParse(t['created_at']?.toString() ?? '') ?? DateTime.now();
        final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
        final amtColor = amount >= 0 ? Colors.green : Colors.red;
        return ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: typeColor(type).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.swap_vert, color: typeColor(type)),
          ),
          title: Text(type),
          subtitle: Text('Orden: ${t['order_id'] ?? '-'}  ·  ${DateFormat('yyyy-MM-dd HH:mm').format(createdAt.toLocal())}'),
          trailing: Text(
            '${numberFmt.format(amount)} MXN',
            style: TextStyle(fontWeight: FontWeight.bold, color: amtColor),
          ),
        );
      },
    );
  }
}

class _CategoryAccountsList extends StatelessWidget {
  final List<String> ids;
  final Map<String, Map<String, dynamic>> accounts;
  final bool isMaster;
  final bool isRestaurant;
  final bool isDelivery;
  final NumberFormat numberFmt;
  final String Function({required String id, required String userId, String? rawType}) labelBuilder;
  final String Function(String id) shortener;
  const _CategoryAccountsList({
    super.key,
    required this.ids,
    required this.accounts,
    required this.isMaster,
    required this.isRestaurant,
    required this.isDelivery,
    required this.numberFmt,
    required this.labelBuilder,
    required this.shortener,
  });

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return const Center(child: Text('Sin cuentas en esta categoría'));
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      itemCount: ids.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, index) {
        final id = ids[index];
        final raw = accounts[id] ?? {};
        final bal = (raw['balance'] is num)
            ? (raw['balance'] as num).toDouble()
            : double.tryParse(raw['balance']?.toString() ?? '0') ?? 0.0;
        final userId = (raw['user_id']?.toString() ?? '');
        final label = labelBuilder(id: id, userId: userId, rawType: raw['account_type']?.toString());

        const double eps = 0.01;
        final Color amtColor = bal > eps
            ? Colors.green
            : (bal < -eps ? Colors.red : Colors.blue);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: amtColor.withValues(alpha: 0.12),
            child: Icon(
              isMaster
                  ? Icons.account_balance_wallet
                  : isRestaurant
                      ? Icons.store
                      : Icons.delivery_dining,
              color: amtColor,
            ),
          ),
          title: Text(label),
          subtitle: Text('ID: ${shortener(id)}'),
          trailing: Text(
            numberFmt.format(bal),
            style: TextStyle(fontWeight: FontWeight.bold, color: amtColor),
          ),
        );
      },
    );
  }
}

class _OrderBalance {
  final String orderId;
  final double net;
  const _OrderBalance({required this.orderId, required this.net});
}
