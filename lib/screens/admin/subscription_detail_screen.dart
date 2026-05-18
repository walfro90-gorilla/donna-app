import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/core/services/admin_service.dart';
import 'package:doa_repartos/models/doa_models.dart';

class SubscriptionDetailScreen extends StatefulWidget {
  final DoaSubscription subscription;
  const SubscriptionDetailScreen({super.key, required this.subscription});

  @override
  State<SubscriptionDetailScreen> createState() => _SubscriptionDetailScreenState();
}

class _SubscriptionDetailScreenState extends State<SubscriptionDetailScreen> {
  final _admin = AdminService();
  final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
  final _date  = DateFormat('dd/MM/yyyy HH:mm');

  bool _loading = true;
  List<DoaSubscriptionInvoice> _invoices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _admin.listInvoicesForSubscription(widget.subscription.id);
      if (!mounted) return;
      setState(() {
        _invoices = list;
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

  Future<void> _markPaid(DoaSubscriptionInvoice inv) async {
    final result = await showDialog<({String method, String reference, String notes})>(
      context: context,
      builder: (_) => const _MarkPaidDialog(),
    );
    if (result == null) return;
    try {
      await _admin.markInvoicePaid(
        invoiceId: inv.id,
        method: result.method,
        reference: result.reference.isEmpty ? null : result.reference,
        notes: result.notes.isEmpty ? null : result.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago registrado'), backgroundColor: Colors.green),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _waive(DoaSubscriptionInvoice inv) async {
    final notes = await _promptText('Perdonar invoice', 'Motivo (opcional)');
    if (notes == null) return;
    try {
      await _admin.waiveInvoice(invoiceId: inv.id, notes: notes.isEmpty ? null : notes);
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _extendGrace() async {
    final extra = await _promptInt('Extender gracia', 'Días adicionales');
    if (extra == null || extra <= 0) return;
    try {
      await _admin.extendGrace(
        subscriptionId: widget.subscription.id,
        extraDays: extra,
      );
      if (!mounted) return;
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<String?> _promptText(String title, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Confirmar')),
        ],
      ),
    );
  }

  Future<int?> _promptInt(String title, String label) async {
    final ctrl = TextEditingController(text: '7');
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(ctrl.text)),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.subscription;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.displayName),
        actions: [
          IconButton(
            tooltip: 'Extender gracia',
            icon: const Icon(Icons.update),
            onPressed: _extendGrace,
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
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(s),
                const SizedBox(height: 16),
                Text('Historial de invoices', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (_invoices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Sin invoices')),
                  )
                else
                  ..._invoices.map(_invoiceTile),
              ],
            ),
    );
  }

  Widget _headerCard(DoaSubscription s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(s.status.displayName),
                  backgroundColor: s.status.color.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(s.role == 'restaurant' ? 'Restaurante' : 'Repartidor'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            _row('Cuota mensual', _money.format(s.monthlyFee)),
            _row('Periodo actual', '${_date.format(s.currentPeriodStart)} → ${_date.format(s.currentPeriodEnd)}'),
            if (s.lastPaidAt != null) _row('Último pago', _date.format(s.lastPaidAt!)),
            if (s.suspendedAt != null) _row('Suspendida desde', _date.format(s.suspendedAt!)),
            if (s.userEmail != null) _row('Email', s.userEmail!),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Widget _invoiceTile(DoaSubscriptionInvoice inv) {
    final isPayable = inv.status == InvoiceStatus.pending || inv.status == InvoiceStatus.overdue;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(inv.status.displayName),
                  backgroundColor: inv.status.color.withValues(alpha: 0.15),
                  visualDensity: VisualDensity.compact,
                ),
                const Spacer(),
                Text(_money.format(inv.amount), style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 6),
            Text('Periodo: ${_date.format(inv.periodStart)} → ${_date.format(inv.periodEnd)}'),
            Text('Vence: ${_date.format(inv.dueDate)}'),
            if (inv.paidAt != null) Text('Pagada: ${_date.format(inv.paidAt!)}'),
            if (inv.paymentMethod != null) Text('Método: ${inv.paymentMethod}'),
            if (inv.paymentReference != null) Text('Ref: ${inv.paymentReference}'),
            if (inv.notes != null && inv.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Notas: ${inv.notes}', style: const TextStyle(color: Colors.grey)),
              ),
            if (isPayable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => _markPaid(inv),
                    icon: const Icon(Icons.check),
                    label: const Text('Marcar pagada'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _waive(inv),
                    icon: const Icon(Icons.do_not_disturb_alt),
                    label: const Text('Perdonar'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarkPaidDialog extends StatefulWidget {
  const _MarkPaidDialog();

  @override
  State<_MarkPaidDialog> createState() => _MarkPaidDialogState();
}

class _MarkPaidDialogState extends State<_MarkPaidDialog> {
  String _method = 'spei';
  final _reference = TextEditingController();
  final _notes = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar pago'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Método'),
              items: const [
                DropdownMenuItem(value: 'spei', child: Text('SPEI')),
                DropdownMenuItem(value: 'mp_recurring', child: Text('MercadoPago recurrente')),
                DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
                DropdownMenuItem(value: 'other', child: Text('Otro')),
              ],
              onChanged: (v) => setState(() => _method = v ?? 'spei'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Referencia (CLABE/folio)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            method: _method,
            reference: _reference.text.trim(),
            notes: _notes.text.trim(),
          )),
          child: const Text('Confirmar pago'),
        ),
      ],
    );
  }
}
