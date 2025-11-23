import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'dart:async';

class ActiveOrderTracker extends StatefulWidget {
  final DoaOrder order;
  final VoidCallback? onTap;
  
  const ActiveOrderTracker({
    super.key,
    required this.order,
    this.onTap,
  });

  @override
  State<ActiveOrderTracker> createState() => _ActiveOrderTrackerState();
}

class _ActiveOrderTrackerState extends State<ActiveOrderTracker>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🎬 [TRACKER] ===== initState LLAMADO =====');
    debugPrint('🎬 [TRACKER] Order ID: ${widget.order.id}');
    debugPrint('🎬 [TRACKER] Status: ${widget.order.status}');
    debugPrint('🎬 [TRACKER] Delivery ID: ${widget.order.deliveryAgentId}');
    debugPrint('🎬 [TRACKER] Delivery Name: ${widget.order.deliveryAgent?.name}');
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _progressAnimation = Tween<double>(
      begin: 0.0,
      end: _getProgressForStatus(widget.order.status),
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));
    
    _startAnimations();
  }
  
  @override
  void didUpdateWidget(ActiveOrderTracker oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    debugPrint('🔄 [TRACKER] ===== didUpdateWidget LLAMADO =====');
    debugPrint('🔄 [TRACKER] OLD - ID: ${oldWidget.order.id}, Status: ${oldWidget.order.status}, DeliveryID: ${oldWidget.order.deliveryAgentId}, DeliveryName: ${oldWidget.order.deliveryAgent?.name}');
    debugPrint('🔄 [TRACKER] NEW - ID: ${widget.order.id}, Status: ${widget.order.status}, DeliveryID: ${widget.order.deliveryAgentId}, DeliveryName: ${widget.order.deliveryAgent?.name}');
    
    // CRÍTICO: Detectar cambios en delivery agent (ID o nombre)
    final deliveryChanged = 
        oldWidget.order.deliveryAgent?.id != widget.order.deliveryAgent?.id ||
        oldWidget.order.deliveryAgent?.name != widget.order.deliveryAgent?.name;
    
    final statusChanged = oldWidget.order.status != widget.order.status;
    
    debugPrint('🔄 [TRACKER] statusChanged: $statusChanged');
    debugPrint('🔄 [TRACKER] deliveryChanged: $deliveryChanged');
    
    // Si cambió el status de la orden o el delivery agent, actualizar animaciones
    if (statusChanged || deliveryChanged) {
      debugPrint('✅ [TRACKER] ===== CAMBIO DETECTADO - ACTUALIZANDO =====');
      
      if (deliveryChanged) {
        debugPrint('🔄 [TRACKER] Delivery agent actualizado: ${oldWidget.order.deliveryAgent?.name} → ${widget.order.deliveryAgent?.name}');
        // Forzar rebuild del widget
        setState(() {});
        debugPrint('✅ [TRACKER] setState() ejecutado por cambio de delivery');
      }
      
      if (statusChanged) {
        debugPrint('🔄 [TRACKER] Status actualizado: ${oldWidget.order.status} → ${widget.order.status}');
      }
      
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: _getProgressForStatus(widget.order.status),
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ));
      
      _progressController.reset();
      _progressController.forward();
      debugPrint('✅ [TRACKER] Animación de progreso actualizada');
    } else {
      debugPrint('ℹ️ [TRACKER] Sin cambios detectados');
    }
  }

  void _startAnimations() {
    _pulseController.repeat(reverse: true);
    _progressController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  double _getProgressForStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 0.1;
      case OrderStatus.confirmed:
        return 0.3;
      case OrderStatus.inPreparation:
        return 0.5;
      case OrderStatus.readyForPickup:
        return 0.75;
      case OrderStatus.assigned:        // Nuevo status con progreso específico
        return 0.65;
      case OrderStatus.onTheWay:
        return 0.9;
      case OrderStatus.delivered:
        return 1.0;
      case OrderStatus.canceled:
        return 0.0;
      case OrderStatus.notDelivered:
        return 0.0;
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
      case OrderStatus.assigned:         // Nuevo mensaje específico
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
      case OrderStatus.assigned:         // Icono específico para asignado
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
      case OrderStatus.assigned:         // Color distintivo para asignado
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

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '--:--';
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  DateTime _getEstimatedDeliveryTime() {
    final deliveryMinutes = widget.order.restaurant?.deliveryTime ?? 30;
    return widget.order.createdAt.add(Duration(minutes: deliveryMinutes));
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🎨 [TRACKER] ===== build() LLAMADO =====');
    debugPrint('🎨 [TRACKER] Order ID: ${widget.order.id}');
    debugPrint('🎨 [TRACKER] Status: ${widget.order.status}');
    debugPrint('🎨 [TRACKER] Delivery ID: ${widget.order.deliveryAgentId}');
    debugPrint('🎨 [TRACKER] Delivery Name: ${widget.order.deliveryAgent?.name}');
    
    final statusColor = _getStatusColor(widget.order.status);
    
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header con status y tiempo
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getStatusIcon(widget.order.status),
                              color: statusColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pedido #${widget.order.id.substring(0, 8).toUpperCase()}',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                  ),
                                ),
                                Text(
                                  _getStatusText(widget.order.status),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Estimado',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              Text(
                                _formatTime(_getEstimatedDeliveryTime()),
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Barra de progreso
                      AnimatedBuilder(
                        animation: _progressAnimation,
                        builder: (context, child) {
                          return Column(
                            children: [
                              LinearProgressIndicator(
                                value: _progressAnimation.value,
                                backgroundColor: statusColor.withValues(alpha: 0.2),
                                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                                minHeight: 6,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Progreso',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  Text(
                                    '${(_progressAnimation.value * 100).round()}%',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Código de confirmación (solo cuando está en camino)
                      if (widget.order.status == OrderStatus.onTheWay && 
                          widget.order.confirmCode != null && 
                          widget.order.confirmCode!.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange.withValues(alpha: 0.8),
                                Colors.deepOrange.withValues(alpha: 0.6),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Código de Confirmación',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Compártelo con el repartidor',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  widget.order.confirmCode!,
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[700],
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Información del restaurante y repartidor
                      Row(
                        children: [
                          // Restaurante
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.restaurant,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Restaurante',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.order.restaurant?.name ?? 'Cargando...',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(width: 12),
                          
                          // Repartidor
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.delivery_dining,
                                        size: 16,
                                        color: Theme.of(context).colorScheme.secondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Repartidor',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    // Fallback: si ya hay delivery_agent_id pero aún no llega el join, mostrar asignado
                                    widget.order.deliveryAgent?.name 
                                      ?? (widget.order.deliveryAgentId != null 
                                          ? 'Repartidor asignado'
                                          : 'Asignando...'),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Botón de acción
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: widget.onTap,
                          icon: const Icon(Icons.track_changes),
                          label: const Text('Track Your Order'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: statusColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}