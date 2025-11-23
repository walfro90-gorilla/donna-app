import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/widgets/active_order_tracker.dart';

class MultiOrderTracker extends StatefulWidget {
  final List<DoaOrder> orders;
  final void Function(DoaOrder)? onOrderSelected;
  final void Function(DoaOrder)? onTapOrder;

  const MultiOrderTracker({
    super.key,
    required this.orders,
    this.onOrderSelected,
    this.onTapOrder,
  });

  @override
  State<MultiOrderTracker> createState() => _MultiOrderTrackerState();
}

class _MultiOrderTrackerState extends State<MultiOrderTracker> {
  String? _selectedOrderId;

  @override
  void initState() {
    super.initState();
    if (widget.orders.isNotEmpty) {
      _selectedOrderId = widget.orders.first.id;
    }
  }

  @override
  void didUpdateWidget(covariant MultiOrderTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    debugPrint('🔄 [MULTI_TRACKER] ===== didUpdateWidget LLAMADO =====');
    debugPrint('🔄 [MULTI_TRACKER] oldWidget.orders.length: ${oldWidget.orders.length}');
    debugPrint('🔄 [MULTI_TRACKER] widget.orders.length: ${widget.orders.length}');
    debugPrint('🔄 [MULTI_TRACKER] _selectedOrderId: $_selectedOrderId');
    
    final stillExists = widget.orders.any((o) => o.id == _selectedOrderId);
    debugPrint('🔄 [MULTI_TRACKER] ¿Orden seleccionada aún existe? $stillExists');
    
    if (!stillExists) {
      debugPrint('⚠️ [MULTI_TRACKER] Orden seleccionada ya no existe, seleccionando primera');
      _selectedOrderId = widget.orders.isNotEmpty ? widget.orders.first.id : null;
      if (_selectedOrderId != null) {
        final selected = widget.orders.firstWhere((o) => o.id == _selectedOrderId);
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onOrderSelected?.call(selected));
      }
    }
    
    // CRÍTICO: SIEMPRE verificar si hay cambios en los datos
    // NO usar else - esto hace que no detecte cambios cuando stillExists es true
    if (_selectedOrderId != null && widget.orders.isNotEmpty && oldWidget.orders.isNotEmpty) {
      final oldOrder = oldWidget.orders.firstWhere((o) => o.id == _selectedOrderId, orElse: () => oldWidget.orders.first);
      final newOrder = widget.orders.firstWhere((o) => o.id == _selectedOrderId, orElse: () => widget.orders.first);
      
      debugPrint('🔍 [MULTI_TRACKER] ===== COMPARANDO ÓRDENES =====');
      debugPrint('🔍 [MULTI_TRACKER] OLD - ID: ${oldOrder.id}, Status: ${oldOrder.status}, DeliveryID: ${oldOrder.deliveryAgentId}, DeliveryName: ${oldOrder.deliveryAgent?.name}');
      debugPrint('🔍 [MULTI_TRACKER] NEW - ID: ${newOrder.id}, Status: ${newOrder.status}, DeliveryID: ${newOrder.deliveryAgentId}, DeliveryName: ${newOrder.deliveryAgent?.name}');
      
      // Detectar cambios en status, delivery agent ID o nombre
      final statusChanged = oldOrder.status != newOrder.status;
      final deliveryIdChanged = oldOrder.deliveryAgentId != newOrder.deliveryAgentId;
      final deliveryNameChanged = oldOrder.deliveryAgent?.name != newOrder.deliveryAgent?.name;
      
      debugPrint('🔍 [MULTI_TRACKER] statusChanged: $statusChanged');
      debugPrint('🔍 [MULTI_TRACKER] deliveryIdChanged: $deliveryIdChanged');
      debugPrint('🔍 [MULTI_TRACKER] deliveryNameChanged: $deliveryNameChanged');
      
      if (statusChanged || deliveryIdChanged || deliveryNameChanged) {
        debugPrint('🔄 [MULTI_TRACKER] ===== CAMBIO DETECTADO - FORZANDO REBUILD =====');
        debugPrint('📊 Status: ${oldOrder.status} → ${newOrder.status} (cambió: $statusChanged)');
        debugPrint('🚚 Delivery ID: ${oldOrder.deliveryAgentId} → ${newOrder.deliveryAgentId} (cambió: $deliveryIdChanged)');
        debugPrint('👤 Delivery Name: ${oldOrder.deliveryAgent?.name} → ${newOrder.deliveryAgent?.name} (cambió: $deliveryNameChanged)');
        
        // CRÍTICO: Forzar rebuild para que ActiveOrderTracker reciba la orden actualizada
        setState(() {});
        debugPrint('✅ [MULTI_TRACKER] setState() ejecutado');
      } else {
        debugPrint('ℹ️ [MULTI_TRACKER] No se detectaron cambios en los datos');
      }
    } else {
      debugPrint('⚠️ [MULTI_TRACKER] No se puede comparar órdenes (IDs o listas vacías)');
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.inPreparation:
        return Colors.purple;
      case OrderStatus.readyForPickup:
        return Colors.green;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.canceled:
        return Colors.red;
      case OrderStatus.notDelivered:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.orders.isEmpty) return const SizedBox.shrink();

    final selected = _selectedOrderId != null
        ? widget.orders.firstWhere((o) => o.id == _selectedOrderId, orElse: () => widget.orders.first)
        : widget.orders.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.orders.length > 1) ...[
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: widget.orders.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final order = widget.orders[index];
                final selectedChip = order.id == _selectedOrderId;
                final dotColor = _statusColor(order.status);

                return ChoiceChip(
                  selected: selectedChip,
                  onSelected: (val) {
                    setState(() => _selectedOrderId = order.id);
                    widget.onOrderSelected?.call(order);
                  },
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          order.restaurant?.name ?? 'Pedido',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('#${order.id.substring(0, 6).toUpperCase()}', style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
                  labelStyle: TextStyle(
                    color: selectedChip
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        ActiveOrderTracker(
          // CRÍTICO: Key único que incluye status + delivery para forzar rebuild cuando cambien
          key: ValueKey('tracker_${selected.id}_${selected.status}_${selected.deliveryAgent?.name ?? "null"}_${selected.deliveryAgentId ?? "null"}'),
          order: selected,
          onTap: () => widget.onTapOrder?.call(selected),
        ),
      ],
    );
  }
}
