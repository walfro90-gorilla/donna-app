import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/screens/reviews/review_screen.dart';

/// Pantalla de detalles de pedido para restaurantes
class OrderDetailRestaurantScreen extends StatefulWidget {
  final DoaOrder order;

  const OrderDetailRestaurantScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailRestaurantScreen> createState() =>
      _OrderDetailRestaurantScreenState();
}

class _OrderDetailRestaurantScreenState
    extends State<OrderDetailRestaurantScreen> {
  bool _isLoading = false;
  bool _isLoadingItems = true;
  bool _isRemovingItem = false;
  DoaOrder? _currentOrder;
  List<DoaOrderItem> _orderItems = [];
  // unit_price por item_id (el modelo solo expone price_at_time_of_order)
  final Map<String, double> _unitPrices = {};
  // IDs de ítems quitados por la cocina
  final Set<String> _removedItemIds = {};
  // Modificadores seleccionados por item: itemId → lista de opciones
  final Map<String, List<DoaOrderItemModifier>> _itemModifiers = {};

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _loadOrderItems();
  }

  /// Carga los items del pedido con el nombre del producto desde Supabase
  Future<void> _loadOrderItems() async {
    try {
      final response = await SupabaseConfig.client
          .from('order_items')
          .select('*, product:products(id, name, description, image_url, price), order_item_modifiers(*)')
          .eq('order_id', widget.order.id);

      final rawList = response as List;

      // Guardar unit_price por item id antes de parsear el modelo
      final unitPrices = <String, double>{};
      final modifiersByItem = <String, List<DoaOrderItemModifier>>{};
      for (final raw in rawList) {
        final id = raw['id']?.toString() ?? '';
        final unitPrice = raw['unit_price'] != null
            ? (raw['unit_price'] as num).toDouble()
            : null;
        final priceAtOrder = raw['price_at_time_of_order'] != null
            ? (raw['price_at_time_of_order'] as num).toDouble()
            : 0.0;
        // unit_price default es 0.00 en DB — usar solo si es > 0, sino fallback a price_at_time_of_order
        unitPrices[id] = (unitPrice != null && unitPrice > 0) ? unitPrice : priceAtOrder;

        // Parsear modificadores del item
        final rawMods = raw['order_item_modifiers'];
        if (rawMods is List && rawMods.isNotEmpty) {
          modifiersByItem[id] = rawMods
              .map((m) => DoaOrderItemModifier.fromJson(m as Map<String, dynamic>))
              .toList();
        }
      }

      final items = rawList.map((item) => DoaOrderItem.fromJson(item)).toList();

      // Cargar IDs de ítems ya quitados en DB
      // Comparación defensiva: el campo puede llegar como bool true o string 'true'
      final removedIds = <String>{};
      for (final raw in rawList) {
        final val = raw['is_removed'];
        if (val == true || val == 'true') {
          removedIds.add(raw['id'].toString());
        }
      }

      if (mounted) {
        setState(() {
          _orderItems = items;
          _unitPrices.addAll(unitPrices);
          _removedItemIds.addAll(removedIds);
          _itemModifiers.addAll(modifiersByItem);
          _isLoadingItems = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [ORDER_DETAIL] Error cargando items: $e');
      if (mounted) {
        setState(() {
          _orderItems = widget.order.orderItems ?? [];
          _isLoadingItems = false;
        });
      }
    }
  }

  /// Actualizar el estado del pedido
  Future<void> _updateOrderStatus(OrderStatus newStatus) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final user = SupabaseConfig.client.auth.currentUser;
      final success = await OrderStatusHelper.updateOrderStatus(
          widget.order.id, newStatus.toString(), user?.id);

      if (!success) {
        throw Exception('Failed to update order status');
      }

      setState(() {
        _currentOrder = widget.order.copyWith(status: newStatus);
      });

      final String message = newStatus == OrderStatus.confirmed
          ? '✅ Pedido aceptado correctamente'
          : newStatus == OrderStatus.canceled
              ? '❌ Pedido rechazado'
              : newStatus == OrderStatus.readyForPickup
                  ? '📦 Pedido marcado como listo para recoger'
                  : '✅ Estado actualizado';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor:
                newStatus == OrderStatus.canceled ? Colors.red : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        if (newStatus == OrderStatus.confirmed ||
            newStatus == OrderStatus.canceled) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) Navigator.of(context).pop(true);
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error updating order status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al actualizar el pedido. Inténtalo de nuevo.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _currentOrder!;
    final canModifyStatus = order.status == OrderStatus.pending;
    final canMarkReady = order.status == OrderStatus.assigned;
    final canValidatePickup = order.status == OrderStatus.readyForPickup ||
        order.status == OrderStatus.arrivedAtRestaurant;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(
          'Pedido #${order.id.substring(0, 8).toUpperCase()}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Banner de estado
          _buildStatusBanner(order.status),

          // Contenido principal
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── SECCIÓN COCINA (lo más importante primero) ───
                  _buildKitchenSection(),

                  const SizedBox(height: 12),

                  // Notas especiales del cliente
                  if (order.orderNotes != null &&
                      order.orderNotes!.trim().isNotEmpty)
                    _buildNotesCard(order.orderNotes!),

                  const SizedBox(height: 12),

                  // Dirección de entrega
                  if (order.deliveryAddress != null)
                    _buildDeliveryAddressCard(order.deliveryAddress!),

                  const SizedBox(height: 12),

                  // Info del cliente (compacta)
                  _buildClientCard(order),

                  const SizedBox(height: 12),

                  // Resumen económico
                  _buildTotalCard(order),

                  const SizedBox(height: 12),

                  // Botón de calificación
                  if (order.status == OrderStatus.delivered)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ReviewScreen(orderId: order.id),
                            ),
                          );
                        },
                        icon: const Icon(Icons.stars_rounded),
                        label: const Text('Calificar al repartidor'),
                      ),
                    ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          (canModifyStatus || canMarkReady || canValidatePickup)
              ? _buildActionBar(
                  canModifyStatus, canMarkReady, canValidatePickup)
              : null,
    );
  }

  // ─────────────────────────────────────────────
  //  BANNER DE ESTADO
  // ─────────────────────────────────────────────
  Widget _buildStatusBanner(OrderStatus status) {
    final color = _getStatusColor(status);
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          Icon(_getStatusIcon(status), color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getStatusText(status),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                Text(
                  _getStatusDescription(status),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  SECCIÓN COCINA — lo que hay que preparar
  // ─────────────────────────────────────────────
  Widget _buildKitchenSection() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade300, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header cocina
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Icon(Icons.restaurant_menu,
                    color: Colors.white, size: 26),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '¿QUÉ PREPARAR?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (!_isLoadingItems)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Builder(builder: (_) {
                      final active = _orderItems
                          .where((i) => !_removedItemIds.contains(i.id))
                          .length;
                      final total = _orderItems.length;
                      final label = _removedItemIds.isEmpty
                          ? '$total ${total == 1 ? 'platillo' : 'platillos'}'
                          : '$active de $total platillos';
                      return Text(
                        label,
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),

          // Lista de items
          if (_isLoadingItems)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.orange),
                    SizedBox(height: 12),
                    Text('Cargando platillos...',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else if (_orderItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No hay platillos registrados en este pedido.',
                style: TextStyle(color: Colors.grey, fontSize: 15),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _orderItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _buildKitchenItem(_orderItems[index], index + 1),
            ),
        ],
      ),
    );
  }

  Widget _buildKitchenItem(DoaOrderItem item, int number) {
    final isRemoved = _removedItemIds.contains(item.id);
    final productName = item.product?.name ?? 'Platillo #${item.productId.substring(0, 6)}';
    final mods = _itemModifiers[item.id] ?? [];
    final note = item.notes;

    return Opacity(
      opacity: isRemoved ? 0.45 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cantidad — grande y visible
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isRemoved ? Colors.grey.shade400 : Colors.orange.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${item.quantity}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'pzas',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 14),

            // Nombre del platillo + opciones + nota
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isRemoved ? Colors.grey.shade500 : const Color(0xFF1A1A1A),
                      decoration: isRemoved ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.grey.shade500,
                    ),
                  ),
                  if (item.product?.description != null &&
                      item.product!.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        item.product!.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // ── Opciones seleccionadas ──────────────────────────────
                  if (mods.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: mods.map((m) {
                        final label = m.priceDelta > 0
                            ? '${m.name}  +\$${m.priceDelta.toStringAsFixed(0)}'
                            : m.name;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade300, width: 1),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  // ── Nota libre del cliente ──────────────────────────────
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 4),

            // Botón quitar (solo en órdenes activas y si no está ya quitado)
            if (!isRemoved && _canRemoveItems())
              IconButton(
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.red, size: 26),
                tooltip: 'Quitar del pedido',
                onPressed: _isRemovingItem
                    ? null
                    : () => _showRemoveItemDialog(item),
              ),

            // Badge QUITADO si ya fue removido
            if (isRemoved)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'QUITADO',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// La cocina puede quitar ítems mientras la orden esté activa (no entregada/cancelada)
  bool _canRemoveItems() {
    final s = _currentOrder?.status;
    return s == OrderStatus.pending ||
        s == OrderStatus.confirmed ||
        s == OrderStatus.inPreparation ||
        s == OrderStatus.assigned;
  }

  // ─────────────────────────────────────────────
  //  NOTAS ESPECIALES
  // ─────────────────────────────────────────────
  Widget _buildNotesCard(String notes) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.yellow.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.shade600, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade700, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOTA DEL CLIENTE',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.orange.shade800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DIRECCIÓN DE ENTREGA
  // ─────────────────────────────────────────────
  Widget _buildDeliveryAddressCard(String address) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on, color: Colors.red.shade400, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dirección de entrega',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  address,
                  style: const TextStyle(
                      fontSize: 15, color: Color(0xFF1A1A1A), height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  INFO CLIENTE (compacta)
  // ─────────────────────────────────────────────
  Widget _buildClientCard(DoaOrder order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blue.shade50,
            radius: 22,
            child: Icon(Icons.person, color: Colors.blue.shade400, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.user?.name ?? 'Cliente',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (order.user?.phone != null)
                  Text(
                    order.user!.phone!,
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          // Fecha/hora del pedido
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatTime(order.createdAt),
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                _formatDate(order.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  RESUMEN ECONÓMICO
  // ─────────────────────────────────────────────
  Widget _buildTotalCard(DoaOrder order) {
    // Subtotal desde el precio real del producto en DB (products.price),
    // ignorando price_at_time_of_order que puede tener comisión aplicada.
    // Fallback a totalAmount - deliveryFee si los items aún no cargaron.
    final double subtotal;
    if (!_isLoadingItems && _orderItems.isNotEmpty) {
      subtotal = _orderItems
          .where((i) => !_removedItemIds.contains(i.id))
          .fold(0.0, (sum, i) {
        final productPrice = i.product?.price ?? (_unitPrices[i.id] ?? i.priceAtTimeOfOrder);
        final modsTotal = (_itemModifiers[i.id] ?? [])
            .fold(0.0, (ms, m) => ms + m.priceDelta);
        return sum + ((productPrice + modsTotal) * i.quantity);
      });
    } else {
      subtotal = order.totalAmount - (order.deliveryFee ?? 0);
    }
    final deliveryFee = order.deliveryFee ?? 0;
    final total = subtotal + deliveryFee;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _buildTotalRow('Subtotal', subtotal, Colors.black87),
          const SizedBox(height: 6),
          _buildTotalRow('Envío', deliveryFee, Colors.grey.shade600),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _buildTotalRow('TOTAL', total, Colors.green.shade700, large: true),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                order.paymentMethod == PaymentMethod.card
                    ? Icons.credit_card
                    : Icons.payments_outlined,
                size: 18,
                color: Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Text(
                order.paymentMethod == PaymentMethod.card
                    ? 'Pago con tarjeta'
                    : 'Pago en efectivo',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount, Color color,
      {bool large = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: large ? 16 : 14,
                fontWeight: large ? FontWeight.bold : FontWeight.normal,
                color: color)),
        Text('\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: large ? 18 : 14,
                fontWeight: large ? FontWeight.bold : FontWeight.normal,
                color: color)),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  BARRA DE ACCIONES
  // ─────────────────────────────────────────────
  Widget _buildActionBar(
      bool canModifyStatus, bool canMarkReady, bool canValidatePickup) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: canModifyStatus
          ? Row(
              children: [
                // Rechazar
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _showConfirmDialog(
                              'Rechazar Pedido',
                              '¿Estás seguro de que quieres rechazar este pedido?',
                              () => _updateOrderStatus(OrderStatus.canceled),
                              Colors.red,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.close, size: 22),
                    label: const Text('Rechazar',
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                // Aceptar
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _showConfirmDialog(
                              'Aceptar Pedido',
                              '¿Confirmas que quieres aceptar este pedido?',
                              () => _updateOrderStatus(OrderStatus.confirmed),
                              Colors.green,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.check, size: 22),
                    label: Text(
                      _isLoading ? 'Procesando...' : 'Aceptar Pedido',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            )
          : canMarkReady
              ? SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _showConfirmDialog(
                              'Marcar Pedido Listo',
                              '¿El pedido está listo para que el repartidor lo recoja?',
                              () => _updateOrderStatus(
                                  OrderStatus.readyForPickup),
                              Colors.blue,
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.restaurant_menu, size: 22),
                    label: Text(
                      _isLoading ? 'Marcando...' : '¡Pedido Listo para Recoger!',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                )
              : canValidatePickup
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed:
                            _isLoading ? null : () => _showPickupCodeDialog(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.key, size: 22),
                        label: Text(
                          _isLoading
                              ? 'Validando...'
                              : 'Validar Código del Repartidor',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
    );
  }

  // ─────────────────────────────────────────────
  //  QUITAR ÍTEM DE LA ORDEN
  // ─────────────────────────────────────────────

  /// Marca el ítem como quitado en DB y recalcula el total del pedido
  Future<void> _removeOrderItem(DoaOrderItem item) async {
    setState(() => _isRemovingItem = true);
    try {
      // 1. Marcar is_removed = true en order_items
      await SupabaseConfig.client
          .from('order_items')
          .update({'is_removed': true}).eq('id', item.id);

      // 2. Recalcular subtotal con los ítems activos restantes
      final activeItems = _orderItems.where(
          (i) => !_removedItemIds.contains(i.id) && i.id != item.id);
      final newSubtotal = activeItems.fold(0.0, (sum, i) {
        final price = _unitPrices[i.id] ?? i.priceAtTimeOfOrder;
        return sum + (price * i.quantity);
      });
      final deliveryFee = _currentOrder!.deliveryFee ?? 0.0;
      final newTotal = newSubtotal + deliveryFee;

      // 3. Actualizar orders.total_amount
      // (subtotal es columna generada: GREATEST(total_amount - delivery_fee, 0), no se puede escribir)
      await SupabaseConfig.client
          .from('orders')
          .update({'total_amount': newTotal}).eq('id', widget.order.id);

      // 4. Actualizar estado local
      setState(() {
        _removedItemIds.add(item.id);
        _currentOrder = _currentOrder!.copyWith(totalAmount: newTotal);
      });

      // 5. Ofrecer pausar el producto
      if (mounted) _showPauseProductDialog(item);
    } catch (e) {
      debugPrint('❌ [ORDER_DETAIL] Error quitando ítem: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error al quitar el ítem. Inténtalo de nuevo.'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isRemovingItem = false);
    }
  }

  /// Pausa el producto (is_available = false) para que no se pueda pedir
  Future<void> _pauseProduct(String productId, String productName) async {
    try {
      await SupabaseConfig.client
          .from('products')
          .update({'is_available': false}).eq('id', productId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$productName pausado — ya no aparece en el menú'),
            backgroundColor: Colors.orange.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [ORDER_DETAIL] Error pausando producto: $e');
    }
  }

  /// Dialog 1: Confirmar quitar el ítem del pedido
  void _showRemoveItemDialog(DoaOrderItem item) {
    final name = item.product?.name ?? 'este ítem';
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.remove_circle_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('¿Quitar del pedido?'),
          ],
        ),
        content: Text(
          '¿Seguro que quieres quitar "$name"?\n\nEl cliente recibirá el pedido sin este ítem.',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _removeOrderItem(item);
            },
            child: const Text('Quitar ítem'),
          ),
        ],
      ),
    );
  }

  /// Dialog 2: Ofrecer pausar el producto tras quitarlo
  void _showPauseProductDialog(DoaOrderItem item) {
    final name = item.product?.name ?? 'este producto';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.pause_circle_outline, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('¿Pausar producto?'),
          ],
        ),
        content: Text(
          '"$name" fue quitado del pedido.\n\n¿Quieres pausarlo para que los clientes no puedan pedirlo mientras no está disponible?',
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ítem "$name" quitado del pedido'),
                  backgroundColor: Colors.grey.shade700,
                ),
              );
            },
            child: const Text('No, solo quitar'),
          ),
          FilledButton.icon(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.orange.shade700),
            icon: const Icon(Icons.pause_circle),
            label: const Text('Sí, pausar'),
            onPressed: () {
              Navigator.of(context).pop();
              _pauseProduct(item.productId, name);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  DIÁLOGOS
  // ─────────────────────────────────────────────
  void _showConfirmDialog(
      String title, String message, VoidCallback onConfirm, Color color) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onConfirm();
            },
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: const Text('Confirmar',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showPickupCodeDialog() async {
    final TextEditingController codeController = TextEditingController();
    bool isValidating = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.key, color: Colors.purple),
                  SizedBox(width: 8),
                  Text('Código del Repartidor'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'El repartidor debe darte un código de 4 dígitos para recoger el pedido:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (value) => setState(() {}),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4.0,
                        ),
                    decoration: InputDecoration(
                      hintText: '0000',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      counterText: '',
                    ),
                    maxLength: 4,
                    enabled: !isValidating,
                  ),
                  if (isValidating) ...[
                    const SizedBox(height: 16),
                    const Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 8),
                          Text('Validando código...'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isValidating
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isValidating || codeController.text.length != 4
                      ? null
                      : () async {
                          setState(() => isValidating = true);
                          try {
                            final pickupCode = _currentOrder!.pickupCode;
                            final enteredCode = codeController.text;

                            if (pickupCode != null &&
                                pickupCode == enteredCode) {
                              Navigator.of(context).pop();
                              await _updateOrderStatus(OrderStatus.onTheWay);
                            } else {
                              setState(() => isValidating = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Código incorrecto. Verifica con el repartidor.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() => isValidating = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error al validar código: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Validar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────
  String _formatTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange.shade700;
      case OrderStatus.confirmed:
        return Colors.blue.shade600;
      case OrderStatus.inPreparation:
        return Colors.purple.shade600;
      case OrderStatus.readyForPickup:
        return Colors.teal.shade600;
      case OrderStatus.assigned:
        return Colors.amber.shade700;
      case OrderStatus.arrivedAtRestaurant:
        return Colors.deepOrange.shade600;
      case OrderStatus.arrivedAtClient:
        return Colors.deepPurple.shade600;
      case OrderStatus.onTheWay:
        return Colors.indigo.shade600;
      case OrderStatus.delivered:
        return Colors.green.shade600;
      case OrderStatus.notDelivered:
      case OrderStatus.canceled:
        return Colors.red.shade600;
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.hourglass_empty;
      case OrderStatus.confirmed:
        return Icons.check_circle;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.takeout_dining;
      case OrderStatus.assigned:
        return Icons.person_pin_circle;
      case OrderStatus.arrivedAtRestaurant:
        return Icons.storefront;
      case OrderStatus.arrivedAtClient:
        return Icons.location_on;
      case OrderStatus.onTheWay:
        return Icons.local_shipping;
      case OrderStatus.delivered:
        return Icons.done_all;
      case OrderStatus.notDelivered:
      case OrderStatus.canceled:
        return Icons.cancel;
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Esperando tu confirmación';
      case OrderStatus.confirmed:
        return 'Pedido Confirmado';
      case OrderStatus.inPreparation:
        return 'En Preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para Recoger';
      case OrderStatus.assigned:
        return 'Repartidor Asignado';
      case OrderStatus.arrivedAtRestaurant:
        return 'Repartidor en Restaurante';
      case OrderStatus.arrivedAtClient:
        return 'Repartidor en Domicilio';
      case OrderStatus.onTheWay:
        return 'En Camino al Cliente';
      case OrderStatus.delivered:
        return 'Entregado ✓';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'No Entregado';
    }
  }

  String _getStatusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Acepta o rechaza este pedido';
      case OrderStatus.confirmed:
        return 'Empieza a prepararlo';
      case OrderStatus.inPreparation:
        return 'Se está cocinando';
      case OrderStatus.readyForPickup:
        return 'Esperando al repartidor';
      case OrderStatus.assigned:
        return 'Repartidor viene en camino';
      case OrderStatus.arrivedAtRestaurant:
        return 'El repartidor llegó a recoger';
      case OrderStatus.arrivedAtClient:
        return 'El repartidor llegó al cliente';
      case OrderStatus.onTheWay:
        return 'El repartidor lleva el pedido';
      case OrderStatus.delivered:
        return 'Completado exitosamente';
      case OrderStatus.canceled:
        return 'El pedido fue rechazado';
      case OrderStatus.notDelivered:
        return 'No se pudo entregar';
    }
  }
}
