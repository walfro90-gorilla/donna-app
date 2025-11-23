import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/review_service.dart';
import 'package:doa_repartos/screens/reviews/review_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  bool _loading = true;
  List<DoaOrder> _orders = [];
  final _reviewService = const ReviewService();
  final Map<String, bool> _orderReviewedCache = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        setState(() => _loading = false);
        return;
      }
      final data = await DoaRepartosService.getOrdersWithDetails(userId: user!.id);
      final orders = data.map((o) => DoaOrder.fromJson(o)).toList();
      _orders = orders;

      // Pre-chequear cuáles ya tienen reseña por este autor
      for (final o in orders) {
        if (o.status == OrderStatus.delivered) {
          final reviewed = await _reviewService.hasAnyReviewByAuthorForOrder(orderId: o.id, authorId: user.id);
          _orderReviewedCache[o.id] = reviewed;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar pedidos: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openReview(DoaOrder order) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        minChildSize: 0.3,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (_, __) => ReviewScreen(orderId: order.id),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis Pedidos')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _orders.isEmpty
                  ? ListView(children: const [SizedBox(height: 200), Center(child: Text('No tienes pedidos aún'))])
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final o = _orders[i];
                        final canRate = o.status == OrderStatus.delivered;
                        final reviewed = _orderReviewedCache[o.id] ?? false;
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _statusColor(o.status).withValues(alpha: 0.1),
                              child: Icon(_statusIcon(o.status), color: _statusColor(o.status)),
                            ),
                            title: Text(o.restaurant?.name ?? 'Restaurante', maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_statusText(o.status), style: TextStyle(color: _statusColor(o.status))),
                              Text(_formatDate(o.createdAt), style: Theme.of(context).textTheme.bodySmall),
                            ]),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('\$${o.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                if (canRate && !reviewed)
                                  OutlinedButton(
                                    onPressed: () => _openReview(o),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: const Size(0, 28),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      side: BorderSide(color: Theme.of(context).colorScheme.primary),
                                      foregroundColor: Theme.of(context).colorScheme.primary,
                                      shape: const StadiumBorder(),
                                    ),
                                    child: const Text('Calificar'),
                                  )
                                else if (canRate && reviewed)
                                  const Text('Calificado', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600))
                                else
                                  const SizedBox.shrink(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.lightBlue;
      case OrderStatus.inPreparation:
        return Colors.blue;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.purple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.canceled:
        return Colors.red;
      case OrderStatus.notDelivered:
        return Colors.red;
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.done_all;
      case OrderStatus.assigned:
        return Icons.person_pin_circle;
      case OrderStatus.onTheWay:
        return Icons.delivery_dining;
      case OrderStatus.delivered:
        return Icons.check_circle;
      case OrderStatus.canceled:
        return Icons.cancel;
      case OrderStatus.notDelivered:
        return Icons.block;
    }
  }

  String _statusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmado';
      case OrderStatus.inPreparation:
        return 'En preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para recoger';
      case OrderStatus.assigned:
        return 'Repartidor asignado';
      case OrderStatus.onTheWay:
        return 'En camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'No Entregado';
    }
  }

  String _formatDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
    if (diff.inDays == 0) {
    return 'Hoy ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Ayer';
    } else if (diff.inDays < 7) {
      return 'Hace ${diff.inDays} días';
    }
  return '${local.day}/${local.month}/${local.year}';
  }
}
