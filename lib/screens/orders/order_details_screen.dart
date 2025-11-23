import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:doa_repartos/screens/reviews/review_screen.dart';
import 'package:doa_repartos/services/review_service.dart';
import 'package:doa_repartos/widgets/live_delivery_map.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';
import 'package:doa_repartos/core/events/event_bus.dart';

class OrderDetailsScreen extends StatefulWidget {
  final DoaOrder order;

  const OrderDetailsScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late DoaOrder _order;
  bool _isLoading = false;
    StreamSubscription<DoaOrder>? _orderUpdatesSub;
  bool _hasMyReview = false;
  bool _checkingReview = false;
  StreamSubscription<DataUpdatedEvent>? _reviewEventSub;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
      // Iniciar realtime para actualizaciones del pedido
      try {
        final rt = RealtimeNotificationService();
        // Si aún no está inicializado, inicializar en background
        if (!rt.isInitialized) {
          // ignore: discarded_futures
          rt.initialize();
        }
        _orderUpdatesSub = rt.orderUpdates.listen((updated) {
          if (!mounted) return;
          if (updated.id == _order.id) {
            setState(() {
              _order = updated;
            });
            debugPrint('📡 [ORDER_DETAILS] Realtime update recibido para ${_order.id} (status=${_order.status})');
          }
        });
      } catch (e) {
        debugPrint('⚠️ [ORDER_DETAILS] No se pudo iniciar realtime: $e');
      }
    _refreshOrderDetails();
    // Verificar si ya existe reseña del usuario para esta orden
    _checkIfAlreadyReviewed();

    // Escuchar evento global para cuando se envía una reseña desde otro lugar (p. ej., HomeScreen)
    try {
      _reviewEventSub = EventBus.instance.on<DataUpdatedEvent>().listen((evt) {
        if (evt.dataType == 'review_submitted') {
          final orderId = evt.data['order_id']?.toString();
          if (orderId == _order.id) {
            // Revalidar inmediatamente el estado del botón
            _checkIfAlreadyReviewed();
          }
        }
      });
    } catch (e) {
      debugPrint('⚠️ [ORDER_DETAILS] No se pudo suscribir a eventos de reseña: $e');
    }
  }

    @override
    void dispose() {
      _orderUpdatesSub?.cancel();
    _reviewEventSub?.cancel();
      super.dispose();
    }

  Future<void> _refreshOrderDetails() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🔄 [ORDER_DETAILS] Actualizando detalles de pedido ${_order.id}');
      
      // ✅ OPTIMIZADO: Usar RPC que devuelve JSON completo
      final response = await SupabaseConfig.client
          .rpc('get_order_full_details', params: {'order_id_param': _order.id});

      debugPrint('🔍 [ORDER_DETAILS] Response type: ${response.runtimeType}');
      
      if (response != null) {
        // La nueva función devuelve directamente jsonb, convertir a Map
        final Map<String, dynamic> jsonData = Map<String, dynamic>.from(response as Map);
        
        final updatedOrder = DoaOrder.fromJson(jsonData);
        
        if (mounted) {
          setState(() {
            _order = updatedOrder;
          });
          debugPrint('✅ [ORDER_DETAILS] Pedido actualizado exitosamente');
          debugPrint('📦 [ORDER_DETAILS] Items: ${_order.orderItems?.length ?? 0}');
          debugPrint('🏪 [ORDER_DETAILS] Restaurant: ${_order.restaurant?.name ?? 'N/A'}');
          debugPrint('🚚 [ORDER_DETAILS] Delivery Agent: ${_order.deliveryAgent?.name ?? 'N/A'}');
          debugPrint('📱 [ORDER_DETAILS] Status: ${_order.status}');
        }
        // Al actualizar los detalles, revalidar estado de reseña
        unawaited(_checkIfAlreadyReviewed());
      }
    } catch (e) {
      debugPrint('❌ [ORDER_DETAILS] Error actualizando pedido: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error actualizando pedido: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _checkIfAlreadyReviewed() async {
    final userId = SupabaseConfig.auth.currentUser?.id;
    if (userId == null) return;
    if (!mounted) return;
    setState(() => _checkingReview = true);
    try {
      final has = await const ReviewService().hasAnyReviewByAuthorForOrder(
        orderId: _order.id,
        authorId: userId,
      );
      if (mounted) setState(() => _hasMyReview = has);
    } catch (e) {
      debugPrint('⚠️ [ORDER_DETAILS] No se pudo verificar reseña existente: $e');
    } finally {
      if (mounted) setState(() => _checkingReview = false);
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Esperando confirmación del restaurante';
      case OrderStatus.confirmed:
        return 'Pedido confirmado, preparando tu orden';
      case OrderStatus.inPreparation:
        return 'Tu comida se está preparando';
      case OrderStatus.readyForPickup:
        return 'Tu pedido está listo, esperando repartidor';
      case OrderStatus.assigned:
        return 'Repartidor asignado, va camino al restaurante';
      case OrderStatus.onTheWay:
        return 'En camino hacia tu dirección';
      case OrderStatus.delivered:
        return 'Pedido entregado ¡Disfruta tu comida!';
      case OrderStatus.canceled:
        return 'Pedido cancelado';
      case OrderStatus.notDelivered:
        return 'No se pudo entregar el pedido';
    }
  }

  Color _getStatusColor(OrderStatus status) {
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

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.hourglass_empty;
      case OrderStatus.confirmed:
        return Icons.check_circle_outline;
      case OrderStatus.inPreparation:
        return Icons.restaurant_menu;
      case OrderStatus.readyForPickup:
        return Icons.fastfood;
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

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
  final d = dateTime.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dateTime) {
  final d = dateTime.toLocal();
  return '${d.day}/${d.month}/${d.year}';
  }

  /// Abrir dirección en Google Maps
  Future<void> _openMaps(String address) async {
    try {
      // Limpiar y codificar la dirección para la URL
      final encodedAddress = Uri.encodeComponent(address);
      final url = 'https://www.google.com/maps/search/?api=1&query=$encodedAddress';
      final uri = Uri.parse(url);
      
      debugPrint('📍 [ORDER_DETAILS] Abriendo Google Maps para: $address');
      debugPrint('📍 [ORDER_DETAILS] URL: $url');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo abrir el mapa para: $address'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [ORDER_DETAILS] Error abriendo Google Maps: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error abriendo el mapa: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(_order.status);
    // Calcular totales de forma robusta
    final itemsTotal = (_order.orderItems ?? [])
        .fold<double>(0.0, (sum, it) {
      final unit = (it.priceAtTimeOfOrder > 0)
          ? it.priceAtTimeOfOrder
          : (it.product?.price ?? 0.0);
      return sum + (unit * (it.quantity));
    });
    final deliveryFee = _order.deliveryFee
        ?? _order.restaurant?.deliveryFee
        ?? 35.0; // Fallback a $35 según requerimiento
    // Si viene total_amount desde DB, usarlo para mantener consistencia contable
    final displayedSubtotal = (_order.totalAmount > 0)
        ? (_order.totalAmount - deliveryFee).clamp(0, double.infinity)
        : itemsTotal;
    final displayedTotal = (_order.totalAmount > 0)
        ? _order.totalAmount
        : (itemsTotal + deliveryFee);

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${_order.id.substring(0, 8).toUpperCase()}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshOrderDetails,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshOrderDetails,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Estado del pedido
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      statusColor.withValues(alpha: 0.1),
                      statusColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getStatusIcon(_order.status),
                      color: statusColor,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getStatusText(_order.status),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pedido realizado el ${_formatDate(_order.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Mostrar el mapa desde que el repartidor acepta la orden hasta que esté en camino
              // - assigned: siempre mostrar
              // - ready_for_pickup: mostrar solo si ya hay repartidor asignado (evita mostrar si aún no hay driver)
              // - on_the_way: siempre mostrar
              // - delivered: NO mostrar (orden ya completada, no necesitamos el minimapa)
              if (({
                    OrderStatus.assigned,
                    OrderStatus.onTheWay,
                  }.contains(_order.status)) ||
                  (_order.status == OrderStatus.readyForPickup && _order.deliveryAgentId != null)) ...[
                _SectionCard(
                  title: 'Seguimiento en vivo',
                  icon: Icons.map,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Se removieron las miniaturas de productos sobre el mapa por solicitud
                      SizedBox(
                        height: 220,
                        child: LiveDeliveryMap(
                          orderId: _order.id,
                          // Client delivery coordinates (house icon)
                          // Priority: use delivery_lat/delivery_lon (correct fields), fallback to deliveryLatlng (legacy)
                          deliveryLatlng: (() {
                            if (_order.deliveryLat != null && _order.deliveryLon != null) {
                              return '${_order.deliveryLat},${_order.deliveryLon}';
                            }
                            return _order.deliveryLatlng;
                          })(),
                          // Restaurant coordinates (restaurant icon)
                          restaurantLatlng: (() {
                            final r = _order.restaurant;
                            if (r != null && r.latitude != null && r.longitude != null) {
                              return '${r.latitude},${r.longitude}';
                            }
                            return null;
                          })(),
                          // Show restaurant before pickup; after pickup show client's home
                          showClientDestination: _order.status == OrderStatus.onTheWay || _order.status == OrderStatus.delivered,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vemos la posición del repartidor en tiempo real.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Información del restaurante
              _SectionCard(
                title: 'Restaurante',
                icon: Icons.restaurant,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _order.restaurant?.name ?? 'Restaurante no disponible',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_order.restaurant?.formattedAddress?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _openMaps(_order.restaurant!.formattedAddress!),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _order.restaurant!.formattedAddress!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_order.restaurant?.user?.phone?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tel: ${_order.restaurant!.user!.phone!}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Información del repartidor
              if (_order.deliveryAgent != null || 
                  _order.status == OrderStatus.assigned || 
                  _order.status == OrderStatus.onTheWay || 
                  _order.status == OrderStatus.delivered) ...[
                _SectionCard(
                  title: 'Repartidor',
                  icon: Icons.delivery_dining,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _order.deliveryAgent?.name ?? 'Asignando repartidor...',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_order.deliveryAgent?.phone?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Tel: ${_order.deliveryAgent!.phone!}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ] else if (_order.deliveryAgent == null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Buscando el mejor repartidor para ti...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Productos pedidos
              _SectionCard(
                title: 'Productos',
                icon: Icons.shopping_bag,
                child: Column(
                  children: (_order.orderItems ?? []).map((item) {
                    final unitPrice = (item.priceAtTimeOfOrder > 0)
                        ? item.priceAtTimeOfOrder
                        : (item.product?.price ?? 0.0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                '${item.quantity}x',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.product?.name ?? 'Producto no disponible',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (item.product?.description != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.product?.description ?? '',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            '\$${(item.quantity * unitPrice).toStringAsFixed(2)}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Dirección de entrega
              _SectionCard(
                title: 'Dirección de entrega',
                icon: Icons.location_on,
                child: GestureDetector(
                  onTap: _order.deliveryAddress != null 
                      ? () => _openMaps(_order.deliveryAddress!)
                      : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _order.deliveryAddress ?? 'No especificada',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: _order.deliveryAddress != null 
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            decoration: _order.deliveryAddress != null 
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                      if (_order.deliveryAddress != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.launch,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Resumen del pedido
              _SectionCard(
                title: 'Resumen del pedido',
                icon: Icons.receipt,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal:', style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          '\$${(displayedSubtotal).toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Costo de envío:', style: Theme.of(context).textTheme.bodyMedium),
                        Text(
                          '\$${(deliveryFee).toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total:',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '\$${(displayedTotal).toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Código de confirmación (cuando está en camino)
              if (_order.status == OrderStatus.onTheWay && _order.confirmCode != null) ...[
                const SizedBox(height: 16),
                _SectionCard(
                  title: 'Código de Confirmación',
                  icon: Icons.pin,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.orange.withValues(alpha: 0.1),
                          Colors.orange.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            _order.confirmCode!,
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                              letterSpacing: 6.0,
                              fontSize: 32,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.orange.shade700,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Comparte este código con el repartidor para confirmar la entrega de tu pedido',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              if (_order.status == OrderStatus.delivered) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _hasMyReview
                        ? null
                        : () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ReviewScreen(orderId: _order.id),
                              ),
                            );
                            // Tras volver del flujo de reseña, revalidar
                            await _checkIfAlreadyReviewed();
                          },
                    icon: const Icon(Icons.stars_rounded),
                    label: Text(_hasMyReview ? 'Ya calificado' : 'Calificar experiencia'),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}