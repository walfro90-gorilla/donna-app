import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/doa_models.dart';
import '../../core/services/financial_service.dart';

class RestaurantBalanceScreen extends StatefulWidget {
  final int initialTabIndex;
  const RestaurantBalanceScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  State<RestaurantBalanceScreen> createState() => _RestaurantBalanceScreenState();
}

class _RestaurantBalanceScreenState extends State<RestaurantBalanceScreen> with TickerProviderStateMixin {
  final FinancialService _financialService = FinancialService();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  final TextEditingController _confirmationCodeController = TextEditingController();

  late TabController _tabController;

  DoaAccount? _account;
  List<DoaAccountTransaction> _recentTransactions = [];
  List<DoaSettlement> _pendingSettlements = [];
  List<DoaSettlement> _allSettlements = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;
  bool _isConfirmingSettlement = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialTabIndex.clamp(0, 2));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _confirmationCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _financialService.getUserAccount(),
        _financialService.getUserTransactions(limit: 10),
        _financialService.getPendingSettlementsForRestaurant(),
        _financialService.getUserSettlements(),
        _financialService.getUserFinancialStats(),
      ]);

      setState(() {
        _account = results[0] as DoaAccount?;
        _recentTransactions = results[1] as List<DoaAccountTransaction>;
        _pendingSettlements = results[2] as List<DoaSettlement>;
        _allSettlements = results[3] as List<DoaSettlement>;
        _stats = results[4] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar datos: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmSettlement(DoaSettlement settlement) async {
    debugPrint('📨 [RESTAURANT] confirmSettlement -> id=${settlement.id} amount=${settlement.amount}');
    final code = _confirmationCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa el código de confirmación')),
      );
      return;
    }

    setState(() => _isConfirmingSettlement = true);

    try {
      final success = await _financialService.confirmSettlement(
        settlementId: settlement.id,
        confirmationCode: code,
      );

      if (success) {
        debugPrint('✅ [RESTAURANT] confirmSettlement OK -> id=${settlement.id}');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Liquidación confirmada exitosamente'),
            backgroundColor: Colors.green,
          ),
        );

        _confirmationCodeController.clear();
        await _loadData();
        if (mounted) Navigator.of(context).pop();
      } else {
        debugPrint('❌ [RESTAURANT] confirmSettlement FAIL (código incorrecto) id=${settlement.id}');
        throw Exception('Código de confirmación incorrecto');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isConfirmingSettlement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance Financiero'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_pendingSettlements.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '${_pendingSettlements.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
                onPressed: () {
                  _tabController.animateTo(1);
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            const Tab(text: 'Balance'),
            Tab(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Liquidaciones'),
                    if (_pendingSettlements.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${_pendingSettlements.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Tab(text: 'Transacciones'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _account == null
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Cuenta no encontrada', style: TextStyle(fontSize: 18, color: Colors.grey)),
                      Text('Contacta con el administrador', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildBalanceTab(),
                    _buildSettlementsTab(),
                    _buildTransactionsTab(),
                  ],
                ),
    );
  }

  Widget _buildBalanceTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance actual
            _buildBalanceCard(),
            const SizedBox(height: 20),

            // CTA de liquidación si hay deuda
            if (_account!.balance < -0.01)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showInitiateSettlementDialog,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.payments),
                    label: const Text('Liquidar adeudo'),
                  ),
                ),
              ),

            // Estadísticas
            _buildStatsCards(),
            const SizedBox(height: 20),

            // Transacciones recientes
            _buildRecentTransactionsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    final balance = _account!.balance;
    const double epsilon = 0.01;
    final bool isZero = balance.abs() < epsilon;
    final bool isNegative = balance < -epsilon;

    final List<Color> gradientColors = isZero
        ? [const Color(0xFFE4007C).withValues(alpha: 0.8), const Color(0xFFE4007C)]
        : (isNegative
            ? [Colors.red.shade700, Colors.red.shade900]
            : [Colors.green.shade600, Colors.green.shade800]);
    final Color shadowColor = isZero ? Colors.blue : (isNegative ? Colors.red : Colors.green);
    final IconData leadingIcon = isZero
        ? Icons.verified
        : (isNegative ? Icons.trending_down : Icons.account_balance_wallet);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                leadingIcon,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Balance Actual',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '${_currencyFormat.format(balance)} MXN',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isZero
                ? 'Estás al día'
                : (isNegative
                    ? 'Tienes deuda por liquidar'
                    : 'Tienes dinero por cobrar'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCards() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Ingresos Totales',
            value: _currencyFormat.format(_stats['totalEarnings'] ?? 0),
            icon: Icons.trending_up,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Comisiones Pagadas',
            value: _currencyFormat.format(_stats['totalCommissions'] ?? 0),
            icon: Icons.percent,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactionsSection() {
    if (_recentTransactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transacciones Recientes',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _recentTransactions.length.clamp(0, 5),
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final transaction = _recentTransactions[index];
            return _buildTransactionTile(transaction);
          },
        ),
      ],
    );
  }

  Widget _buildSettlementsTab() {
    final myAccountId = _account?.id ?? '';
    final outgoing = _allSettlements.where((s) => s.status == SettlementStatus.pending && s.payerAccountId == myAccountId).toList();
    final incoming = _allSettlements.where((s) => s.status == SettlementStatus.pending && s.receiverAccountId == myAccountId).toList();

    if (outgoing.isEmpty && incoming.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.payment_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay liquidaciones pendientes',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            Text(
              'Aquí verás tus liquidaciones por recibir y las que enviaste a plataforma',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (incoming.isNotEmpty) ...[
            const Text('Por recibir (de repartidores)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in incoming) _buildPendingSettlementCard(s),
            const SizedBox(height: 16),
          ],
          if (outgoing.isNotEmpty) ...[
            const Text('Enviadas a plataforma (en espera de confirmación)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final s in outgoing) _buildOutgoingSettlementCard(s),
          ],
        ],
      ),
    );
  }

  Widget _buildPendingSettlementCard(DoaSettlement settlement) {
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
                Row(
                  children: [
                    Icon(Icons.delivery_dining, color: Theme.of(context).colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Repartidor',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(settlement.initiatedAt.toLocal()),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monto a recibir:',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                    Text(
                      '${_currencyFormat.format(settlement.amount)} MXN',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'Pendiente',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

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

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _showConfirmationDialog(settlement),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Confirmar Recepción',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutgoingSettlementCard(DoaSettlement settlement) {
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
                Row(
                  children: [
                    const Icon(Icons.account_balance, color: Colors.purple, size: 20),
                    const SizedBox(width: 8),
                    const Text('Plataforma', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                Text(
                  DateFormat('dd/MM/yyyy HH:mm').format(settlement.initiatedAt.toLocal()),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monto a pagar:', style: TextStyle(color: Colors.grey, fontSize: 14)),
                    Text(
                      '${_currencyFormat.format(settlement.amount)} MXN',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text('En espera de plataforma', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Código de confirmación visible y copiables
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user, color: Colors.deepPurple, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Código:',
                    style: TextStyle(fontSize: 13, color: Colors.deepPurple, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      settlement.confirmationCode.isNotEmpty ? settlement.confirmationCode : '------',
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 4),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar código',
                    icon: const Icon(Icons.copy, size: 18, color: Colors.deepPurple),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: settlement.confirmationCode));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado')), 
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            if (settlement.notes != null && settlement.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(settlement.notes!),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showConfirmationDialog(DoaSettlement settlement) {
    _confirmationCodeController.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmar Liquidación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monto: ${_currencyFormat.format(settlement.amount)} MXN',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text(
                'Ingresa el código de 6 dígitos que te proporciona el repartidor:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmationCodeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
                decoration: const InputDecoration(hintText: '000000', border: OutlineInputBorder(), counterText: ''),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: _isConfirmingSettlement ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: _isConfirmingSettlement ? null : () => _confirmSettlement(settlement),
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
              child: _isConfirmingSettlement
                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  void _showInitiateSettlementDialog() {
    final amountController = TextEditingController(
        text: (_account != null && _account!.balance < 0) ? (-_account!.balance).toStringAsFixed(2) : '0.00');
    final notesController = TextEditingController();
    bool submitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          Future<void> submit() async {
            final raw = amountController.text.trim().replaceAll(',', '.');
            final amount = double.tryParse(raw) ?? 0.0;
            if (amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Monto inválido')));
              return;
            }
            setStateDialog(() => submitting = true);
            try {
              debugPrint('📨 [RESTAURANT] initiateRestaurantSettlementToPlatform -> amount=$amount notes=${notesController.text.trim().isEmpty ? '-' : '<text>'}');
              final res = await _financialService.initiateRestaurantSettlementToPlatform(
                amount: amount,
                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
              );
              if (res == null) throw Exception('No se pudo iniciar la liquidación');
              if (mounted) {
                Navigator.of(context).pop();
                // Limpiar controladores del diálogo
                amountController.dispose();
                notesController.dispose();
              }
              if (!mounted) return;
              // Mostrar código
debugPrint('🧾 [RESTAURANT] settlement created -> id=${res['settlementId']} code=${res['code']}');
              showDialog(
                context: context,
                barrierDismissible: true,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Código de Liquidación'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Comparte este código al administrador para confirmar la recepción:'),
                      const SizedBox(height: 12),
                      Center(
                        child: SelectableText(
                          res['code'] ?? '------',
                          style: const TextStyle(fontSize: 32, letterSpacing: 6, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('ID: ${res['settlementId']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              );
              await _loadData();
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
            } finally {
              if (context.mounted) {
                setStateDialog(() => submitting = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('Liquidar adeudo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  decoration: const InputDecoration(
                    labelText: 'Monto (MXN)',
                    prefixIcon: Icon(Icons.attach_money),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notas (opcional)',
                    prefixIcon: Icon(Icons.note_alt_outlined),
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 140,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Se generará un código de 6 dígitos. Compártelo al administrador para confirmar la recepción.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              ],
            ),
            actions: [
              TextButton(
  onPressed: submitting
      ? null
      : () {
          amountController.dispose();
          notesController.dispose();
          Navigator.of(context).pop();
        },
  child: const Text('Cancelar'),
),
              ElevatedButton(
                onPressed: submitting ? null : submit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: submitting
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Crear liquidación'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (_recentTransactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_outlined, size: 80, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay transacciones',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _recentTransactions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final transaction = _recentTransactions[index];
          return _buildTransactionTile(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionTile(DoaAccountTransaction transaction) {
    final isCredit = transaction.isCredit;
    final color = isCredit ? Colors.green : Colors.red;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          transaction.type.icon,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        transaction.type.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (transaction.description != null)
            Text(
              transaction.description!,
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(
            DateFormat('dd/MM/yyyy HH:mm').format(transaction.createdAt.toLocal()),
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isCredit ? '+' : ''}${_currencyFormat.format(transaction.amount)} MXN',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
