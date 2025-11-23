import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/services/financial_service.dart';

class SettlementsManagementScreen extends StatefulWidget {
  const SettlementsManagementScreen({super.key});

  @override
  State<SettlementsManagementScreen> createState() => _SettlementsManagementScreenState();
}

class _SettlementsManagementScreenState extends State<SettlementsManagementScreen> {
  final DateFormat _df = DateFormat('dd/MM/yyyy HH:mm');

  // Filters
  String _status = 'all'; // all | pending | completed | cancelled
  DateTimeRange? _range;
  String _search = '';

  bool _loading = false;
  List<Map<String, dynamic>> _rows = [];

  // Platform account
  String? _platformAccountId;

  @override
  void initState() {
    super.initState();
    _loadPlatformAccountId().then((_) => _fetch());
  }

  Future<void> _loadPlatformAccountId() async {
    try {
      final res = await SupabaseConfig.client.rpc('rpc_get_platform_account_id');
      if (res is String) {
        setState(() => _platformAccountId = res);
      } else if (res is Map) {
        final map = Map<String, dynamic>.from(res);
        setState(() => _platformAccountId = (map['id'] ?? map['account_id'])?.toString());
      }
    } catch (e) {
      // Non-blocking
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final base = SupabaseConfig.client
          .from('settlements')
          .select('''
            *,
            payer:payer_account_id(user_id, users(*)),
            receiver:receiver_account_id(user_id, users(*))
          ''');

      if (_status != 'all') {
        base.eq('status', _status);
      }

      if (_range != null) {
        base
          .gte('initiated_at', _range!.start.toIso8601String())
          .lte('initiated_at', _range!.end.toIso8601String());
      }

      final data = await base.order('initiated_at', ascending: false);

      final List<Map<String, dynamic>> flattened = [];
      for (final json in (data as List)) {
        final map = Map<String, dynamic>.from(json);
        if (json['payer'] != null && json['payer']['users'] != null) {
          map['payer'] = json['payer']['users'];
        }
        if (json['receiver'] != null && json['receiver']['users'] != null) {
          map['receiver'] = json['receiver']['users'];
        }
        flattened.add(map);
      }

      // Search filter (by payer/receiver name or email)
      final filtered = _search.trim().isEmpty
          ? flattened
          : flattened.where((m) {
              final payer = m['payer'] as Map<String, dynamic>?;
              final receiver = m['receiver'] as Map<String, dynamic>?;
              final target = '${payer?['name'] ?? ''} ${payer?['email'] ?? ''} ${receiver?['name'] ?? ''} ${receiver?['email'] ?? ''}'.toLowerCase();
              return target.contains(_search.toLowerCase());
            }).toList();

      setState(() => _rows = filtered);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando liquidaciones: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial = _range ?? DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month + 1, 0, 23, 59, 59),
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      initialDateRange: initial,
      saveText: 'Aplicar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: Theme.of(context).colorScheme.copyWith(primary: Colors.purple)),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _range = picked);
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liquidaciones (Admin)'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetch,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Text('No se encontraron liquidaciones'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final s = _rows[index];
                            return _buildSettlementCard(s);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          // Status filter
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _status,
              decoration: InputDecoration(
                labelText: 'Estado',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'all', child: Text('Todos')),
                DropdownMenuItem(value: 'pending', child: Text('Pendiente')),
                DropdownMenuItem(value: 'completed', child: Text('Completada')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelada')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _status = v);
                _fetch();
              },
            ),
          ),
          const SizedBox(width: 8),
          // Date range
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range),
              label: Text(_range == null
                  ? 'Rango de fechas'
                  : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Search
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar (pagador/receptor)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) {
                setState(() => _search = v);
                _fetch();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementCard(Map<String, dynamic> s) {
    final amount = (s['amount'] as num?)?.toDouble() ?? 0.0;
    final status = (s['status'] as String?) ?? 'pending';
    final statusColor = status == 'completed'
        ? Colors.green
        : status == 'cancelled'
            ? Colors.red
            : Colors.orange;
    final payer = s['payer'] as Map<String, dynamic>?;
    final receiver = s['receiver'] as Map<String, dynamic>?;
    final receiverAccountId = s['receiver_account_id']?.toString();
    final isToPlatform = _platformAccountId != null && receiverAccountId == _platformAccountId && status == 'pending';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    status == 'completed' ? 'Completada' : status == 'cancelled' ? 'Cancelada' : 'Pendiente',
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                Text(
                  s['initiated_at'] != null
                      ? _df.format(DateTime.parse(s['initiated_at'].toString()).toLocal())
                      : '-',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.attach_money, color: Colors.purple, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${NumberFormat.currency(symbol: '\$', decimalDigits: 2).format(amount)} MXN',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (isToPlatform)
                  ElevatedButton.icon(
                    onPressed: () => _showConfirmDialog(s),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                    icon: const Icon(Icons.verified),
                    label: const Text('Confirmar recepción'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _userTile('Pagador', payer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _userTile('Receptor', receiver),
                ),
              ],
            ),
            if ((s['notes'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(s['notes'] as String),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _userTile(String label, Map<String, dynamic>? u) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                label.startsWith('Pagador') ? Icons.delivery_dining : Icons.store,
                color: label.startsWith('Pagador') ? Colors.green : Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u?['name'] ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(u?['email'] ?? '—', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void _showConfirmDialog(Map<String, dynamic> s) {
    final controller = TextEditingController();
    bool submitting = false;
    showDialog(
      context: context,
      barrierDismissible: !submitting,
      builder: (context) => StatefulBuilder(
        builder: (_, setStateDialog) => AlertDialog(
          title: const Text('Confirmar recepción'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Liquidación ID: ${s['id']}'),
              const SizedBox(height: 8),
              const Text('Ingresa el código de 6 a 8 dígitos:'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 8, // soporta 6 u 8 dígitos
                textAlign: TextAlign.center,
                decoration: const InputDecoration(border: OutlineInputBorder(), counterText: '', hintText: '000000'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting
                  ? null
                  : () {
                      Navigator.of(context).pop();
                    },
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: submitting
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.length < 6 || code.length > 8) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código inválido')));
                        return;
                      }
                      setStateDialog(() => submitting = true);
                      try {
                        debugPrint('📨 [ADMIN] confirm via FinancialService -> settlement=${s['id']} code_len=${code.length}');
                        // Log quirúrgico: leer fila para diagnóstico (no bloqueante si falla)
                        try {
                          final diag = await SupabaseConfig.client
                              .from('settlements')
                              .select('id, status, confirmation_code, code_hash')
                              .eq('id', s['id'].toString())
                              .maybeSingle();
                          debugPrint('🧪 [ADMIN] DB check -> id=${s['id']} status=${diag?['status']} code=${diag?['confirmation_code']} has_hash=${(diag?['code_hash']?.toString().isNotEmpty ?? false)}');
                        } catch (_) {}

                        // Validar contra confirmation_code y completar
                        final ok = await FinancialService().confirmSettlement(
                          settlementId: s['id'].toString(),
                          confirmationCode: code,
                        );
                        if (!ok) throw Exception('validación fallida');

                        if (mounted) Navigator.of(context).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Liquidación confirmada')),
                          );
                          _fetch();
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                      } finally {
                        setStateDialog(() => submitting = false);
                      }
                    },
              child: submitting
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    ).then((_) => controller.dispose());
  }
}
