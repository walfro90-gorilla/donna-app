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
  DoaOrder? _currentOrder;
  List<DoaOrderItem> _orderItems = [];
  // unit_price por item_id (el modelo solo expone price_at_time_of_order)
  final Map<String, double> _unitPrices = {};

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
          .select('*, product:products(id, name, description, image_url, price)')
          .eq('order_id', widget.order.id);

      final rawList = response as List;

      // Guardar unit_price por item id antes de parsear el modelo
      final unitPrices = <String, double>{};
      for (final raw in rawList) {
        final id = raw['id']?.toString() ?? '';
        final unitPrice = raw['unit_price'] != null
            ? (raw['unit_price'] as num).toDouble()
            : null;
        final priceAtOrder = raw['price_at_time_of_order'] != null
            ? (raw['price_at_time_of_order'] as num).toDouble()
            : 0.0;
        // unit_price es el precio unitario; price_at_time_of_order como fallback
        unitPrices[id] = unitPrice ?? priceAtOrder;
      }

      final items = rawList.map((item) => DoaOrderItem.fromJson(item)).toList();

      if (mounted) {
        setState(() {
          _orderItems = items;
          _unitPrices.addAll(unitPrices);
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
    final canValidatePickup = order.status == OrderStatus.readyForPickup;

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
                    child: Text(
                      '${_orderItems.length} ${_orderItems.length == 1 ? 'platillo' : 'platillos'}',
                      style: TextStyle(
                        color: Colors.orange.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
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
    final productName = item.product?.name ?? 'Platillo #${item.productId.substring(0, 6)}';
    // Usar unit_price del DB (precio por pieza), no price_at_time_of_order
    final unitPrice = _unitPrices[item.id] ?? item.priceAtTimeOfOrder;
    final totalLine = unitPrice * item.quantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cantidad — grande y visible
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.orange.shade600,
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

          // Nombre del platillo
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A1A1A),
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
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  '\$${unitPrice.toStringAsFixed(2)} c/u',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Precio total de la línea
          Text(
            '\$${totalLine.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
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
    final subtotal = order.totalAmount - (order.deliveryFee ?? 0);
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
          _buildTotalRow(
              'Envío', order.deliveryFee ?? 0, Colors.grey.shade600),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _buildTotalRow('TOTAL', order.totalAmount, Colors.green.shade700,
              large: true),
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
