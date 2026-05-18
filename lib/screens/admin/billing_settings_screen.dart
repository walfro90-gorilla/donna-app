import 'package:flutter/material.dart';
import 'package:doa_repartos/core/services/admin_service.dart';
import 'package:doa_repartos/core/services/billing_service.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Configuración global del modo de cobro.
/// Permite alternar entre 'commission' y 'subscription' + bootstrap inicial.
class BillingSettingsScreen extends StatefulWidget {
  const BillingSettingsScreen({super.key});

  @override
  State<BillingSettingsScreen> createState() => _BillingSettingsScreenState();
}

class _BillingSettingsScreenState extends State<BillingSettingsScreen> {
  final _admin = AdminService();

  bool _loading = true;
  bool _saving = false;
  BillingModeConfig? _config;
  int _accountsWithoutSubscription = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final mode = await BillingService.instance.getMode(force: true);
      // Para el badge "bootstrap pendiente" consultamos cuántas subscripciones existen.
      final subs = await _admin.listSubscriptions();
      // No tenemos un endpoint para "cuentas totales", aproximamos: el bootstrap RPC es idempotente.
      // Mostramos cuántas suscripciones hay actualmente.
      if (!mounted) return;
      setState(() {
        _config = mode;
        _accountsWithoutSubscription = subs.length;
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

  Future<void> _setMode(String mode) async {
    if (_config?.mode == mode) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambiar modo de cobro'),
        content: Text(
          mode == 'subscription'
              ? 'Pasarás al modo de RENTA MENSUAL. Las próximas órdenes no cobrarán comisión y los restaurantes/repartidores deberán pagar cuota fija.'
              : 'Volverás al modo de COMISIÓN POR PEDIDO. Las cuotas mensuales dejarán de cobrarse.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cambiar')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await _admin.setBillingMode(mode);
      BillingService.instance.invalidate();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modo actualizado a "$mode"'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _bootstrap() async {
    setState(() => _saving = true);
    try {
      final created = await _admin.bootstrapSubscriptions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Suscripciones creadas: $created'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modelo de cobro')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _modeCard(),
                const SizedBox(height: 16),
                _bootstrapCard(),
                const SizedBox(height: 16),
                _settingsInfoCard(),
              ],
            ),
    );
  }

  Widget _modeCard() {
    final mode = _config?.mode ?? 'commission';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modo activo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'commission',
                  icon: Icon(Icons.percent),
                  label: Text('Comisión por pedido'),
                ),
                ButtonSegment(
                  value: 'subscription',
                  icon: Icon(Icons.event_repeat),
                  label: Text('Renta mensual'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: _saving
                  ? null
                  : (s) {
                      if (s.isNotEmpty) _setMode(s.first);
                    },
            ),
            const SizedBox(height: 12),
            Text(
              mode == 'subscription'
                  ? 'Las nuevas órdenes no cobran comisión. Restaurantes y repartidores pagan cuota mensual fija.'
                  : 'Las nuevas órdenes cobran comisión por restaurante. No se cobra cuota mensual.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _bootstrapCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bootstrap inicial', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Crea suscripciones para todos los restaurantes y repartidores que aún no tengan. Operación idempotente y segura.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _bootstrap,
                  icon: const Icon(Icons.playlist_add_check),
                  label: const Text('Aplicar bootstrap'),
                ),
                const SizedBox(width: 12),
                Text(
                  'Suscripciones existentes: $_accountsWithoutSubscription',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsInfoCard() {
    final c = _config;
    if (c == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Parámetros del modo subscription', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _row('Cuota restaurante', '\$${c.subscriptionFeeRestaurant.toStringAsFixed(0)} MXN / mes'),
            _row('Cuota repartidor', '\$${c.subscriptionFeeDelivery.toStringAsFixed(0)} MXN / mes'),
            _row('Días de gracia', '${c.graceDays} días'),
            const SizedBox(height: 12),
            const Text(
              'Para editar estos valores actualiza public.platform_settings desde la consola SQL.',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 160, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}
