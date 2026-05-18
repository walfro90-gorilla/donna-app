import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:doa_repartos/core/services/billing_service.dart';
import 'package:doa_repartos/models/doa_models.dart';

/// Envuelve un screen para bloquearlo si la cuenta del usuario está suspended
/// en modo subscription. Muestra una pantalla con info de la cuota pendiente.
///
/// Si el modo es 'commission' o la suscripción no está suspended, renderiza el child tal cual.
///
/// Refresca el estado:
///   - al montar
///   - cuando la app vuelve a primer plano (AppLifecycleState.resumed)
///   - cada [refreshInterval] (por defecto 2 min)
class SubscriptionGuard extends StatefulWidget {
  final Widget child;
  final Duration refreshInterval;
  const SubscriptionGuard({
    super.key,
    required this.child,
    this.refreshInterval = const Duration(minutes: 2),
  });

  @override
  State<SubscriptionGuard> createState() => _SubscriptionGuardState();
}

class _SubscriptionGuardState extends State<SubscriptionGuard> with WidgetsBindingObserver {
  bool _loading = true;
  bool _blocked = false;
  DoaSubscription? _subscription;
  DoaSubscriptionInvoice? _nextInvoice;
  BillingModeConfig? _mode;
  Timer? _periodicTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    _periodicTimer = Timer.periodic(widget.refreshInterval, (_) => _check(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check(silent: true);
    }
  }

  Future<void> _check({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final mode = await BillingService.instance.getMode(force: true);
      if (!mode.isSubscription) {
        if (!mounted) return;
        setState(() {
          _mode = mode;
          _blocked = false;
          _loading = false;
        });
        return;
      }
      final status = await BillingService.instance.getMySubscriptionStatus();
      if (!mounted) return;
      setState(() {
        _mode = mode;
        _subscription = status.subscription;
        _nextInvoice = status.nextInvoice;
        _blocked = status.subscription?.status == SubscriptionStatus.suspended;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _blocked = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_blocked) return widget.child;
    return _SuspendedScreen(
      subscription: _subscription,
      nextInvoice: _nextInvoice,
      mode: _mode,
      onRetry: _check,
    );
  }
}

class _SuspendedScreen extends StatelessWidget {
  final DoaSubscription? subscription;
  final DoaSubscriptionInvoice? nextInvoice;
  final BillingModeConfig? mode;
  final VoidCallback onRetry;

  const _SuspendedScreen({
    required this.subscription,
    required this.nextInvoice,
    required this.mode,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');
    final date = DateFormat('dd/MM/yyyy');
    final fee = subscription?.monthlyFee ?? mode?.subscriptionFeeRestaurant ?? 999;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suscripción suspendida'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 96, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Tu cuenta está suspendida',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Para reactivar el acceso a la plataforma, debes pagar la cuota mensual de ${money.format(fee)} MXN.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (nextInvoice != null) ...[
                const SizedBox(height: 24),
                Card(
                  color: Colors.red.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Factura pendiente',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Periodo: ${date.format(nextInvoice!.periodStart)} → ${date.format(nextInvoice!.periodEnd)}'),
                        Text('Venció el: ${date.format(nextInvoice!.dueDate)}'),
                        Text('Monto: ${money.format(nextInvoice!.amount)} MXN'),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Realiza el pago por transferencia SPEI y contacta a Doña para que registren tu pago.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Ya pagué, verificar de nuevo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
