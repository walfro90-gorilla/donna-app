import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/doa_models.dart';
import '../../core/services/financial_service.dart';
import '../../core/session/session_manager.dart';
import 'settlement_screen.dart';

class DeliveryBalanceScreen extends StatefulWidget {
  const DeliveryBalanceScreen({Key? key}) : super(key: key);

  @override
  State<DeliveryBalanceScreen> createState() => _DeliveryBalanceScreenState();
}

class _DeliveryBalanceScreenState extends State<DeliveryBalanceScreen> {
  final FinancialService _financialService = FinancialService();
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  DoaAccount? _account;
  List<DoaAccountTransaction> _recentTransactions = [];
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Cargar datos en paralelo
      final results = await Future.wait([
        _financialService.getUserAccount(),
        _financialService.getUserTransactions(limit: 10),
        _financialService.getUserFinancialStats(),
      ]);

      setState(() {
        _account = results[0] as DoaAccount?;
        _recentTransactions = results[1] as List<DoaAccountTransaction>;
        _stats = results[2] as Map<String, dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar datos: $e')),
      );
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Balance'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // No mostrar botón de navegación hacia atrás
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _isLoading
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
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Balance actual
                        _buildBalanceCard(),
                        const SizedBox(height: 20),

                        // Estadísticas
                        _buildStatsCards(),
                        const SizedBox(height: 20),

                        // Botones de acción
                        _buildActionButtons(),
                        const SizedBox(height: 20),

                        // Transacciones recientes
                        _buildTransactionsSection(),
                      ],
                    ),
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
        ? [Colors.blue.shade600, Colors.blue.shade800]
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
                    ? 'Debes dinero a restaurantes'
                    : 'Tienes dinero disponible'),
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
            title: 'Ganancias Totales',
            value: _currencyFormat.format(_stats['totalEarnings'] ?? 0),
            icon: Icons.trending_up,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Liquidaciones Pendientes',
            value: '${_stats['pendingSettlements'] ?? 0}',
            icon: Icons.pending,
            color: Colors.orange,
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

  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettlementScreen(),
                ),
              );
            },
            icon: const Icon(Icons.payment),
            label: const Text('Liquidar Efectivo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              // TODO: Navegar a historial completo de transacciones
            },
            icon: const Icon(Icons.history),
            label: const Text('Ver Historial Completo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.purple,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Transacciones Recientes',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _recentTransactions.isEmpty
            ? Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'No hay transacciones recientes',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTransactions.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final transaction = _recentTransactions[index];
                  return _buildTransactionTile(transaction);
                },
              ),
      ],
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