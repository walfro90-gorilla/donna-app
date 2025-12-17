import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:intl/intl.dart';

/// Screen to view the full ledger (all transactions) of an account
class AdminAccountLedgerScreen extends StatefulWidget {
  final DoaAccount account;
  final String ownerName;

  const AdminAccountLedgerScreen({
    super.key,
    required this.account,
    required this.ownerName,
  });

  @override
  State<AdminAccountLedgerScreen> createState() => _AdminAccountLedgerScreenState();
}

class _AdminAccountLedgerScreenState extends State<AdminAccountLedgerScreen> {
  bool _loading = false;
  List<DoaAccountTransaction> _transactions = [];
  bool _hasMore = true;
  int _page = 0;
  final int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !_loading && _hasMore) {
        _loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final start = _page * _pageSize;
      final end = start + _pageSize - 1;

      final res = await SupabaseConfig.client
          .from('account_transactions')
          .select()
          .eq('account_id', widget.account.id)
          .order('created_at', ascending: false)
          .range(start, end);

      final List<DoaAccountTransaction> newTx = (res as List)
          .map((e) => DoaAccountTransaction.fromJson(e))
          .toList();

      if (mounted) {
        setState(() {
          if (_page == 0) _transactions = newTx;
          else _transactions.addAll(newTx);
          
          _page++;
          if (newTx.length < _pageSize) _hasMore = false;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading ledger: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Historial Financiero Completo'),
            Text(widget.ownerName, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '\$${widget.account.balance.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _page = 0;
          _hasMore = true;
          await _loadTransactions();
        },
        child: _transactions.isEmpty && !_loading
            ? const Center(child: Text('No hay transacciones'))
            : ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _transactions.length + (_hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == _transactions.length) {
                    return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
                  }
                  final t = _transactions[index];
                  final isPositive = t.amount >= 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: t.type.color.withOpacity(0.1),
                      child: Icon(t.type.icon, color: t.type.color, size: 20),
                    ),
                    title: Text(t.type.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_formatDate(t.createdAt)),
                        if (t.description != null && t.description!.isNotEmpty)
                          Text(t.description!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                      ],
                    ),
                    trailing: Text(
                      '${isPositive ? '+' : ''}\$${t.amount.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isPositive ? Colors.green : Colors.red,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final local = d.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(local);
  }
}
