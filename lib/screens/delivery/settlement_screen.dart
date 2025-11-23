import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/doa_models.dart';
import '../../core/services/financial_service.dart';
import '../../supabase/supabase_config.dart';

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({Key? key}) : super(key: key);

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with TickerProviderStateMixin {
  final FinancialService _financialService = FinancialService();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  late TabController _tabController;

  List<DoaAccount> _restaurantAccounts = [];
  List<DoaSettlement> _settlements = [];
  DoaAccount? _selectedRestaurant;
  bool _isLoading = true;
  bool _isCreatingSettlement = false;
  double _minRequired = 0.0;
  final Map<String, String> _restaurantNameByUserId = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint('🧭 [SETTLEMENT_UI] _loadData() start');
      final results = await Future.wait([
        _financialService.getRestaurantsWithDebtForCurrentDelivery(),
        _financialService.getUserSettlements(),
        _financialService.getRequiredMinPaymentForCurrentUser(),
      ]);

      final accounts = results[0] as List<DoaAccount>;
      final settlements = results[1] as List<DoaSettlement>;
      final minRequired = (results[2] as double);
      debugPrint('🧭 [SETTLEMENT_UI] accounts=${accounts.length}, settlements=${settlements.length}, minRequired=$minRequired');
      if (accounts.isNotEmpty) {
        for (final a in accounts.take(5)) {
          debugPrint('🧭 [SETTLEMENT_UI] account sample -> id=${a.id}, userId=${a.userId}, type=${a.accountType}, balance=${a.balance}');
        }
      }

      // Build names map for dropdown (user-friendly)
      if (accounts.isNotEmpty) {
        final userIds = accounts.map((a) => a.userId).toSet().toList();
        try {
          debugPrint('🧭 [SETTLEMENT_UI] fetching restaurant names for userIds: ${userIds.take(5).toList()} (total ${userIds.length})');
          final rows = await SupabaseConfig.client
              .from('restaurants')
              .select('user_id, name')
              .inFilter('user_id', userIds);
          debugPrint('🧭 [SETTLEMENT_UI] restaurant name rows: ${rows.length}');
          _restaurantNameByUserId.clear();
          for (final r in rows) {
            final uid = r['user_id']?.toString();
            final name = r['name']?.toString() ?? 'Restaurante';
            debugPrint('🧭 [SETTLEMENT_UI] mapping user_id=$uid -> name=$name');
            if (uid != null) _restaurantNameByUserId[uid] = name;
          }
        } on PostgrestException catch (e) {
          debugPrint('❌ [SETTLEMENT_UI] error fetching restaurants names: code=${e.code}, message=${e.message}, details=${e.details}, hint=${e.hint}');
        } catch (e) {
          debugPrint('❌ [SETTLEMENT_UI] unknown error fetching restaurants names: $e');
        }
      }

      setState(() {
        _restaurantAccounts = accounts;
        _settlements = settlements;
        _minRequired = minRequired;
        // Auto-fill amount with the minimum required (adeudo total)
        _amountController.text = _minRequired.toStringAsFixed(2);
        _isLoading = false;
      });
      debugPrint('🧭 [SETTLEMENT_UI] _loadData() done. dropdown items=${_restaurantAccounts.length}, namesMapped=${_restaurantNameByUserId.length}');
    } catch (e) {
      debugPrint('❌ [SETTLEMENT_UI] _loadData() error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar datos: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createSettlement() async {
    if (_selectedRestaurant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un restaurante')),
      );
      return;
    }

    final rawAmount = _amountController.text.trim();
    final amount = double.tryParse(rawAmount);
    if (amount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido')),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto debe ser mayor a 0.00')),
      );
      return;
    }
    if (amount < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto mínimo es 0.01 MXN')),
      );
      return;
    }
    if (amount > 1000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El monto máximo permitido es 1,000,000.00 MXN')),
      );
      return;
    }

    setState(() => _isCreatingSettlement = true);

    try {
      final settlement = await _financialService.createSettlement(
        receiverAccountId: _selectedRestaurant!.id,
        amount: amount,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (settlement != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liquidación creada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );

        // Limpiar formulario
        _amountController.clear();
        _notesController.clear();
        setState(() => _selectedRestaurant = null);

        // Recargar datos
        await _loadData();

        // Cambiar a la pestaña de liquidaciones
        _tabController.animateTo(1);
      } else {
        throw Exception('Error al crear la liquidación');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isCreatingSettlement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liquidaciones'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Nueva Liquidación'),
            Tab(text: 'Mis Liquidaciones'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildNewSettlementTab(),
                _buildSettlementsListTab(),
              ],
            ),
    );
  }

  Widget _buildNewSettlementTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crear Nueva Liquidación',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Liquida el efectivo que tienes que entregar a un restaurante',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),

          // Selección de restaurante
          const Text(
            'Seleccionar Restaurante',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<DoaAccount>(
            value: _selectedRestaurant,
            decoration: InputDecoration(
              hintText: 'Selecciona un restaurante',
              prefixIcon: const Icon(Icons.restaurant),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabled: true,
            ),
            items: _restaurantAccounts.map((account) {
              final displayName = _restaurantNameByUserId[account.userId] ?? 'Restaurante';
              return DropdownMenuItem(
                value: account,
                child: Text(displayName),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedRestaurant = value);
            },
          ),
          const SizedBox(height: 20),

          // Monto
          const Text(
            'Monto a Liquidar',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountController,
            readOnly: false, // Permitimos editar para liquidación parcial o total
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00',
              helperText: _minRequired > 0
                  ? 'Sugerido: ${_currencyFormat.format(_minRequired)} MXN (puedes editar)'
                  : 'No tienes adeudo pendiente',
              helperMaxLines: 2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.attach_money),
              suffixText: 'MXN',
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              LengthLimitingTextInputFormatter(12),
            ],
          ),
          const SizedBox(height: 20),

          // Notas opcionales
          const Text(
            'Notas (Opcional)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Agrega notas sobre esta liquidación...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.note),
            ),
          ),
          const SizedBox(height: 32),

          // Botón crear liquidación
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isCreatingSettlement || _minRequired <= 0 ? null : _createSettlement,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isCreatingSettlement
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Crear Liquidación',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementsListTab() {
    if (_settlements.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No tienes liquidaciones',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Crea tu primera liquidación en la pestaña anterior',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _settlements.length,
        itemBuilder: (context, index) {
          final settlement = _settlements[index];
          return _buildSettlementCard(settlement);
        },
      ),
    );
  }

  Widget _buildSettlementCard(DoaSettlement settlement) {
    final statusColor = settlement.status.color;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    settlement.status.displayName,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(settlement.initiatedAt.toLocal()),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.attach_money, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${_currencyFormat.format(settlement.amount)} MXN',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (settlement.status == SettlementStatus.pending) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.qr_code_2,
                            color: Colors.orange, size: 24),
                        const SizedBox(width: 8),
                        const Text(
                          'Código de Confirmación',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      settlement.confirmationCode,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Muestra este código al restaurante',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
            if (settlement.notes != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  settlement.notes!,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
            if (settlement.completedAt != null) ...[
              const SizedBox(height: 12),
              Text(
                'Completada: ${DateFormat('dd/MM/yyyy HH:mm').format(settlement.completedAt!.toLocal())}',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
