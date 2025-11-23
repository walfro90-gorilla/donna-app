import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/core/utils/order_status_helper.dart';
import 'package:doa_repartos/widgets/image_upload_field.dart';
import 'package:file_picker/file_picker.dart';
import 'package:doa_repartos/services/storage_service.dart';
// SupabaseConfig already imported above
import 'package:doa_repartos/screens/reviews/review_screen.dart';
import 'package:doa_repartos/services/location_tracking_service.dart';
import 'package:url_launcher/url_launcher.dart';

class DeliveryOrderDetailScreen extends StatefulWidget {
  final Map<String, dynamic> delivery;

  const DeliveryOrderDetailScreen({
    super.key,
    required this.delivery,
  });

  @override
  State<DeliveryOrderDetailScreen> createState() => _DeliveryOrderDetailScreenState();
}

class _DeliveryOrderDetailScreenState extends State<DeliveryOrderDetailScreen> {
  Map<String, dynamic>? orderDetails;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrderDetails();
  }

  Future<void> _loadOrderDetails() async {
    try {
      final response = await SupabaseConfig.client
          .from('orders')
          .select('''
            *,
            restaurants:restaurant_id (
              id,
              name,
              phone,
              address,
              location_lat,
              location_lon,
              location_place_id,
              user:user_id (
                full_name,
                phone,
                email
              )
            ),
            user:user_id (
              full_name,
              phone,
              email
            ),
            delivery_agent_user:users!delivery_agent_id(
              name,
              phone,
              email
            ),
            items:order_items (
              id,
              quantity,
              price,
              product_id,
              product:products (
                name,
                description,
                image_url
              )
            )
          ''')
          .eq('id', widget.delivery['id'])
          .single();

      if (mounted) {
        setState(() {
          orderDetails = response;
          isLoading = false;
        });
        final status = (response['status'] as String?) ?? '';
        if (status == 'assigned' || status == 'ready_for_pickup' || status == 'on_the_way' || status == 'en_camino') {
          // Start tracking for active delivery states
          LocationTrackingService.instance.start(orderId: response['id'].toString());
        } else if (status == 'delivered' || status == 'entregado') {
          // Ensure tracking is stopped if already delivered
          LocationTrackingService.instance.stop();
        }
      }
    } catch (e) {
      print('Error loading order details: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Pedido #${widget.delivery['id'].toString().substring(0, 8)}'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (orderDetails == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Pedido #${widget.delivery['id'].toString().substring(0, 8)}'),
        ),
        body: const Center(
          child: Text('Error al cargar los detalles del pedido'),
        ),
      );
    }

    final order = orderDetails!;
    final restaurant = order['restaurants'];
    final client = order['user'];
    final items = order['items'] as List<dynamic>? ?? [];
    final status = order['status'] as String;
    final pickupCode = order['pickup_code']?.toString();
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido #${order['id'].toString().substring(0, 8)}'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado del pedido
            _buildStatusCard(status),
            
            const SizedBox(height: 16),
            
            // Código de pickup (solo si está disponible y status es assigned o ready_for_pickup)
            if (pickupCode != null && (status == 'assigned' || status == 'ready_for_pickup')) ...[
              _buildPickupCodeCard(pickupCode),
              const SizedBox(height: 16),
            ],
            
            // Información del restaurante
            _buildRestaurantCard(restaurant),
            
            const SizedBox(height: 16),
            
            // Información del cliente
            _buildClientCard(client),
            
            const SizedBox(height: 16),
            
            // Detalles del pedido
            _buildOrderDetailsCard(order, items),
            
            const SizedBox(height: 16),
            
            // Productos ordenados
            _buildProductsCard(items),
            
            const SizedBox(height: 24),
            
            // Botones de acción
            _buildActionButtons(status),
            const SizedBox(height: 12),
            if (status == 'delivered' || status == 'entregado')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReviewScreen(orderId: order['id'].toString()),
                      ),
                    );
                  },
                  icon: const Icon(Icons.stars_rounded),
                  label: const Text('Calificar esta entrega'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(String status) {
    Color statusColor;
    String statusText;
    String statusDescription;
    
    switch (status) {
      case 'assigned':
        statusColor = Colors.amber;
        statusText = 'Asignado';
        statusDescription = 'Ve al restaurante a recoger el pedido';
        break;
      case 'ready_for_pickup':
        statusColor = Colors.blue;
        statusText = 'Listo para Recoger';
        statusDescription = 'El pedido está listo en el restaurante';
        break;
      case 'on_the_way':
      case 'en_camino':
        statusColor = Colors.orange;
        statusText = 'En Camino';
        statusDescription = 'Dirigiéndote al cliente para la entrega';
        break;
      case 'not_delivered':
        statusColor = Colors.red;
        statusText = 'No Entregado';
        statusDescription = 'El pedido fue marcado como no entregado';
        break;
      case 'delivered':
      case 'entregado':
        statusColor = Colors.green;
        statusText = 'Entregado';
        statusDescription = 'Pedido entregado exitosamente';
        break;
      default:
        statusColor = Colors.grey;
        statusText = status.toUpperCase();
        statusDescription = 'Estado del pedido';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withValues(alpha: 0.1), statusColor.withValues(alpha: 0.05)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  statusText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusDescription,
            style: TextStyle(
              color: statusColor.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupCodeCard(String pickupCode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.purple.withValues(alpha: 0.1),
            Colors.purple.withValues(alpha: 0.05),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.key, color: Colors.purple, size: 24),
              const SizedBox(width: 8),
              Text(
                'Código para Restaurante',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              pickupCode,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
                letterSpacing: 8.0,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Muestra este código al restaurante para recoger el pedido',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.purple.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantCard(dynamic restaurant) {
    final restaurantData = restaurant ?? {};
    final restaurantUser = restaurantData['user'];
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Información del Restaurante',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.orange.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.business, 'Nombre', 
              restaurantUser?['full_name'] ?? restaurantData['name'] ?? 'Restaurante no disponible'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.phone, 'Teléfono', 
              restaurantUser?['phone'] ?? restaurantData['phone'] ?? 'No proporcionado'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.location_on, 'Dirección', 
              restaurantData['address'] ?? 'No proporcionada'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final lat = (restaurantData['location_lat'] as num?)?.toDouble();
                final lon = (restaurantData['location_lon'] as num?)?.toDouble();
                if (lat != null && lon != null) {
                  _openDirectionsToLatLng(lat, lon);
                  return;
                }
                final addr = (restaurantData['address'] ?? '') as String;
                if (addr.isEmpty) return;
                _openDirections(addr);
              },
              icon: const Icon(Icons.directions),
              label: const Text('Ir al Restaurante'),
            ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.email, 'Email', 
              restaurantUser?['email'] ?? 'No proporcionado'),
        ],
      ),
    );
  }

  Widget _buildClientCard(dynamic client) {
    final clientData = client ?? {};
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'Información del Cliente',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.blue.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.person, 'Nombre', 
              clientData['full_name'] ?? 'Cliente no disponible'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.phone, 'Teléfono', 
              clientData['phone'] ?? 'No proporcionado'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.email, 'Email', 
              clientData['email'] ?? 'No proporcionado'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.location_on, 'Dirección de Entrega', 
              orderDetails!['delivery_address'] ?? 'No proporcionada'),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                final lat = (orderDetails!['delivery_lat'] as num?)?.toDouble();
                final lon = (orderDetails!['delivery_lon'] as num?)?.toDouble();
                if (lat != null && lon != null) {
                  _openDirectionsToLatLng(lat, lon);
                  return;
                }
                final coords = _parseLatLngString(orderDetails!['delivery_latlng']?.toString());
                if (coords != null) {
                  _openDirectionsToLatLng(coords[0], coords[1]);
                  return;
                }
                final addr = (orderDetails!['delivery_address'] ?? '') as String;
                if (addr.isEmpty) return;
                _openDirections(addr);
              },
              icon: const Icon(Icons.directions),
              label: const Text('Ir al Cliente'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsCard(Map<String, dynamic> order, List<dynamic> items) {
    final createdAt = DateTime.parse(order['created_at']);
    final totalAmount = (order['total_amount'] ?? 0.0).toDouble();
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Detalles del Pedido',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.orange.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.calendar_today, 'Fecha', _formatDateTime(createdAt)),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.attach_money, 'Total', '\$${totalAmount.toStringAsFixed(2)}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.shopping_cart, 'Items', '${items.length} productos'),
          if (order['order_notes'] != null && order['order_notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildInfoRow(Icons.note, 'Notas', order['order_notes'].toString()),
          ],
        ],
      ),
    );
  }

  Widget _buildProductsCard(List<dynamic> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_menu, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Productos Ordenados',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.green.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map((item) {
            final product = item['product'] ?? {};
            final quantity = item['quantity'] ?? 1;
            final price = (item['price'] ?? 0.0).toDouble();
            
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.restaurant, color: Colors.orange, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product['name'] ?? 'Producto sin nombre',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          'Cantidad: $quantity',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '\$${price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(String status) {
    switch (status) {
      case 'assigned':
      case 'ready_for_pickup':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time, color: Colors.blue, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    status == 'assigned' ? 'Ve al Restaurante' : 'Esperando Validación',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                status == 'assigned' 
                  ? 'Dirígete al restaurante y muestra el código púrpura para recoger el pedido.'
                  : 'Muestra el código púrpura al restaurante. El pedido se marcará automáticamente como "En Camino" cuando el restaurante valide el código.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        );
      case 'on_the_way':
      case 'en_camino':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _showConfirmCodeDialog(),
                icon: const Icon(Icons.pin, color: Colors.white),
                label: const Text(
                  'Confirmar Entrega con Código',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _showNotDeliveredBottomSheet,
                icon: const Icon(Icons.report_gmailerrorred, color: Colors.red),
                label: const Text(
                  'Marcar como NO Entregado',
                  style: TextStyle(fontSize: 15),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        );
      default:
        return Container();
    }
  }


  Future<void> _showConfirmCodeDialog() async {
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
                  Icon(Icons.pin, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('Código de Confirmación'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Solicita al cliente el código de 3 dígitos para confirmar la entrega:',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4.0,
                    ),
                    decoration: InputDecoration(
                      hintText: '000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      counterText: '',
                    ),
                    maxLength: 3,
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
                  onPressed: isValidating || codeController.text.length != 3 
                    ? null 
                    : () async {
                        setState(() => isValidating = true);
                        
                        try {
                          // Verificar el código de confirmación
                          final confirmCode = orderDetails!['confirm_code']?.toString();
                          
                          if (confirmCode == codeController.text) {
                            // Código correcto, marcar como entregado
                            final result = await OrderStatusHelper.updateOrderStatus(
                              orderDetails!['id'], 
                              'delivered',
                            );
                            
                            if (result && mounted) {
                              Navigator.of(context).pop(); // Cerrar diálogo
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('¡Pedido entregado correctamente!'),
                                  backgroundColor: Colors.green,
                                ),
                              );

                              // Stop tracking upon delivery
                              LocationTrackingService.instance.stop();
                              
                              // Recargar y regresar
                              _loadOrderDetails();
                            }
                          } else {
                            // Código incorrecto
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Código incorrecto. Verifica con el cliente.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                            setState(() => isValidating = false);
                          }
                        } catch (e) {
                          print('Error validating confirm code: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al validar código: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                          setState(() => isValidating = false);
                        }
                      },
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =============== Not Delivered Flow ===============
  void _showNotDeliveredBottomSheet() {
    String? selectedReason;
    final TextEditingController notesController = TextEditingController();
    PlatformFile? selectedFile;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.report, color: Colors.red),
                          const SizedBox(width: 8),
                          Text(
                            'Marcar pedido como NO entregado',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Motivo', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _reasonChip(
                            setState,
                            selectedReason,
                            'client_no_show',
                            'Cliente no salió',
                            Icons.door_front_door,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                          _reasonChip(
                            setState,
                            selectedReason,
                            'fake_address',
                            'Dirección falsa/incorrecta',
                            Icons.location_off,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                          _reasonChip(
                            setState,
                            selectedReason,
                            'other',
                            'Otro',
                            Icons.help_outline,
                            (newVal) => setState(() => selectedReason = newVal),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ImageUploadField(
                        label: 'Foto de evidencia',
                        icon: Icons.camera_alt,
                        isRequired: true,
                        helpText: 'Toma o sube una foto como evidencia (obligatorio).',
                        onImageSelected: (file) {
                          setState(() => selectedFile = file);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notas (opcional)',
                          hintText: 'Ej. Toqué varias veces, llamé y no contestaron',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (selectedReason == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Selecciona un motivo'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }
                                  if (selectedFile == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('La foto de evidencia es obligatoria'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  setState(() => isSubmitting = true);
                                  try {
                                    final userId = SupabaseConfig.client.auth.currentUser?.id;
                                    if (userId == null) {
                                      throw 'Sesión expirada. Vuelve a iniciar sesión.';
                                    }
                                    final orderId = orderDetails!['id'].toString();
                                    // 1) Subir evidencia a storage
                                    final photoUrl = await StorageService.uploadDeliveryEvidence(
                                      userId: userId,
                                      orderId: orderId,
                                      file: selectedFile!,
                                    );
                                    if (photoUrl == null) {
                                      throw 'No se pudo subir la evidencia';
                                    }

                                    // 2) Llamar RPC para marcar no entregado
                                    final ok = await DoaRepartosService.markOrderNotDelivered(
                                      orderId: orderId,
                                      deliveryAgentId: userId,
                                      reason: selectedReason!,
                                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                      photoUrl: photoUrl,
                                    );

                                    if (ok && mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Pedido marcado como NO entregado'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                      // Stop tracking and refresh details
                                      LocationTrackingService.instance.stop();
                                      await _loadOrderDetails();
                                    } else {
                                      throw 'La operación no pudo completarse';
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Error: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) setState(() => isSubmitting = false);
                                  }
                                },
                          icon: isSubmitting
                              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.report_gmailerrorred, color: Colors.white),
                          label: Text(isSubmitting ? 'Enviando...' : 'Confirmar NO Entrega'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _reasonChip(
      void Function(void Function()) setState,
      String? selected,
      String value,
      String label,
      IconData icon,
      void Function(String?) onSelect,
      ) {
    final bool isSelected = selected == value;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey[700]),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (v) => onSelect(v ? value : null),
      selectedColor: Colors.red,
      backgroundColor: Colors.red.withValues(alpha: 0.08),
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.red),
      shape: StadiumBorder(side: BorderSide(color: isSelected ? Colors.red : Colors.red.withValues(alpha: 0.6))),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }

  String _formatDateTime(DateTime dateTime) {
  final d = dateTime.toLocal();
  return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openDirections(String destination) async {
    final encoded = Uri.encodeComponent(destination);
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$encoded');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  Future<void> _openDirectionsToLatLng(double lat, double lon) async {
    final url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lon');
    try {
      final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  List<double>? _parseLatLngString(String? latlng) {
    if (latlng == null) return null;
    final parts = latlng.split(',');
    if (parts.length != 2) return null;
    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());
    if (lat == null || lon == null) return null;
    return [lat, lon];
  }
}