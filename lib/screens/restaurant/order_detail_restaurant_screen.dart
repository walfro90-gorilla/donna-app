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
  State<OrderDetailRestaurantScreen> createState() => _OrderDetailRestaurantScreenState();
}

class _OrderDetailRestaurantScreenState extends State<OrderDetailRestaurantScreen> {
  bool _isLoading = false;
  DoaOrder? _currentOrder;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  /// Actualizar el estado del pedido
  Future<void> _updateOrderStatus(OrderStatus newStatus) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      debugPrint('🔄 Updating order ${widget.order.id} to ${newStatus.toString()}');
      
      // Usar OrderStatusHelper para tracking automático
      final user = SupabaseConfig.client.auth.currentUser;
      final success = await OrderStatusHelper.updateOrderStatus(
        widget.order.id, 
        newStatus.toString(), 
        user?.id
      );
      
      if (!success) {
        throw Exception('Failed to update order status');
      }
      
      debugPrint('✅ Order status updated with tracking');
      
      // Actualizar el pedido localmente
      setState(() {
        _currentOrder = widget.order.copyWith(status: newStatus);
      });
      
      // Mostrar confirmación
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
            backgroundColor: newStatus == OrderStatus.canceled ? Colors.red : Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Volver a la pantalla anterior después de 1.5 segundos para confirmación y rechazo
        if (newStatus == OrderStatus.confirmed || newStatus == OrderStatus.canceled) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted) Navigator.of(context).pop(true); // true indica que se actualizó
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
      appBar: AppBar(
        title: Text('Pedido #${order.id.substring(0, 8)}'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Contenido principal
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Estado del pedido
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _getStatusColor(order.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getStatusColor(order.status).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getStatusIcon(order.status),
                          color: _getStatusColor(order.status),
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getStatusText(order.status),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(order.status),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _getStatusDescription(order.status),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Información del cliente
                  _buildSectionCard('Información del Cliente', Icons.person, Colors.blue, [
                    _buildInfoRow('Nombre', order.user?.name ?? 'Sin información', Icons.person),
                    _buildInfoRow('Teléfono', order.user?.phone ?? 'No proporcionado', Icons.phone),
                    _buildInfoRow('Email', order.user?.email ?? 'No proporcionado', Icons.email),
                  ]),
                  
                  const SizedBox(height: 16),
                  
                  // Información del repartidor (si está asignado)
                  if (order.deliveryAgent != null) ...[
                    _buildSectionCard('Información del Repartidor', Icons.delivery_dining, Colors.purple, [
                      _buildInfoRow('Nombre', order.deliveryAgent?.name ?? 'Sin información', Icons.person),
                      _buildInfoRow('Teléfono', order.deliveryAgent?.phone ?? 'No proporcionado', Icons.phone),
                      _buildInfoRow('Email', order.deliveryAgent?.email ?? 'No proporcionado', Icons.email),
                    ]),
                    const SizedBox(height: 16),
                  ],
                  
                  // Detalles del pedido
                  _buildSectionCard('Detalles del Pedido', Icons.receipt_long, Colors.orange, [
                    _buildInfoRow('Fecha', _formatDateTime(order.createdAt), Icons.calendar_today),
                    _buildInfoRow('Total', '\$${order.totalAmount.toStringAsFixed(2)}', Icons.monetization_on),
                    _buildInfoRow('Items', '${order.orderItems?.length ?? 0} productos', Icons.shopping_bag),
                  ]),
                  
                  const SizedBox(height: 16),
                  
                  // Productos ordenados
                  _buildSectionCard('Productos Ordenados', Icons.fastfood, Colors.green, 
                    order.orderItems?.map((item) => _buildOrderItem(item)).toList() ?? [
                      const Text('No hay productos en este pedido', 
                        style: TextStyle(color: Colors.grey))
                    ],
                  ),

                  const SizedBox(height: 16),
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
                ],
              ),
            ),
          ),
        ],
      ),
      // Botones de acción
      bottomNavigationBar: (canModifyStatus || canMarkReady || canValidatePickup)
          ? Container(
              padding: const EdgeInsets.all(16),
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
              child: canModifyStatus ? Row(
                children: [
                  // Botón rechazar
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _showConfirmDialog(
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Botón aceptar
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _showConfirmDialog(
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
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: _isLoading 
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isLoading ? 'Procesando...' : 'Aceptar Pedido'),
                    ),
                  ),
                ],
              ) : canMarkReady ? SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _showConfirmDialog(
                    'Marcar Pedido Listo',
                    '¿El pedido está listo para que el repartidor lo recoja?',
                    () => _updateOrderStatus(OrderStatus.readyForPickup),
                    Colors.blue,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.restaurant_menu, size: 22),
                  label: Text(_isLoading ? 'Marcando...' : 'Pedido Listo para Recoger'),
                ),
              ) : canValidatePickup ? SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _showPickupCodeDialog(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isLoading 
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.key, size: 22),
                  label: Text(_isLoading ? 'Validando...' : 'Validar Código del Repartidor'),
                ),
              ) : const SizedBox.shrink(),
            )
          : null,
    );
  }

  /// Mostrar diálogo de confirmación
  void _showConfirmDialog(String title, String message, VoidCallback onConfirm, Color color) {
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
            child: const Text('Confirmar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Mostrar diálogo para validar pickup_code
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
              title: Row(
                children: [
                  Icon(Icons.key, color: Colors.purple),
                  const SizedBox(width: 8),
                  Text('Código del Repartidor'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'El repartidor debe proporcionarte un código de 4 dígitos para recoger el pedido:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    onChanged: (value) => setState(() {}), // Actualizar estado cuando cambie el texto
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                    ),
                    decoration: InputDecoration(
                      hintText: '0000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterText: '',
                    ),
                    maxLength: 4,
                    enabled: !isValidating,
                  ),
                  if (isValidating) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text('Validando código...'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isValidating ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isValidating || codeController.text.length != 4 
                    ? null 
                    : () async {
                        setState(() => isValidating = true);
                        
                        try {
                          // Verificar el código de pickup
                          final pickupCode = _currentOrder!.pickupCode;
                          final enteredCode = codeController.text;
                          
                          debugPrint('🔧 [PICKUP_VALIDATION] Pickup code from order: "$pickupCode" (${pickupCode.runtimeType})');
                          debugPrint('🔧 [PICKUP_VALIDATION] Entered code: "$enteredCode" (${enteredCode.runtimeType})');
                          debugPrint('🔧 [PICKUP_VALIDATION] Are they equal? ${pickupCode == enteredCode}');
                          
                          if (pickupCode != null && pickupCode == enteredCode) {
                            // Código correcto, actualizar status a 'on_the_way'
                            Navigator.of(context).pop(); // Cerrar diálogo
                            await _updateOrderStatus(OrderStatus.onTheWay);
                          } else {
                            // Código incorrecto
                            setState(() => isValidating = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Código incorrecto. Verifica con el repartidor.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          print('Error validating pickup code: $e');
                          setState(() => isValidating = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al validar código: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
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

  /// Construir sección con tarjeta
  Widget _buildSectionCard(String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  /// Construir fila de información
  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Construir item de pedido
  Widget _buildOrderItem(DoaOrderItem item) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.restaurant,
              color: Colors.orange.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product?.name ?? 'Producto desconocido',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  'Cantidad: ${item.quantity}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '\$${(item.priceAtTimeOfOrder * item.quantity).toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.green.shade700,
            ),
          ),
        ],
      ),
    );
  }

  /// Formatear fecha y hora
  String _formatDateTime(DateTime dateTime) {
    final d = dateTime.toLocal();
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// Obtener color del estado
  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.inPreparation:
        return Colors.purple;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.indigo;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.notDelivered:
        return Colors.red;
      case OrderStatus.canceled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Obtener icono del estado
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
        return Icons.block;
      case OrderStatus.canceled:
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }

  /// Obtener texto del estado
  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente de Aprobación';
      case OrderStatus.confirmed:
        return 'Pedido Confirmado';
      case OrderStatus.inPreparation:
        return 'En Preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para Recoger';
      case OrderStatus.assigned:
        return 'Repartidor Asignado';
      case OrderStatus.onTheWay:
        return 'En Camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'No Entregado';
      default:
        return 'Estado Desconocido';
    }
  }

  /// Obtener descripción del estado
  String _getStatusDescription(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Esperando tu confirmación';
      case OrderStatus.confirmed:
        return 'El pedido ha sido aceptado';
      case OrderStatus.inPreparation:
        return 'Se está preparando';
      case OrderStatus.readyForPickup:
        return 'Esperando al repartidor';
      case OrderStatus.assigned:
        return 'Repartidor en camino a recoger';
      case OrderStatus.onTheWay:
        return 'En ruta al cliente';
      case OrderStatus.delivered:
        return 'Completado exitosamente';
      case OrderStatus.canceled:
        return 'El pedido fue rechazado';
      case OrderStatus.notDelivered:
        return 'No se pudo entregar al cliente';
      default:
        return 'Estado no reconocido';
    }
  }
}