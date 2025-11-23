import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'dart:async';

/// 📦 Active Order Tracker V2 - Con soporte para order_status_updates
/// Versión mejorada con timestamps precisos y histórico de cambios
class ActiveOrderTrackerV2 extends StatefulWidget {
  final DoaOrder order;
  final VoidCallback? onTap;
  final bool showHistoricalSteps;
  
  const ActiveOrderTrackerV2({
    super.key,
    required this.order,
    this.onTap,
    this.showHistoricalSteps = false,
  });

  @override
  State<ActiveOrderTrackerV2> createState() => _ActiveOrderTrackerV2State();
}

class _ActiveOrderTrackerV2State extends State<ActiveOrderTrackerV2>
    with TickerProviderStateMixin {
  
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _progressAnimation;
  
  List<OrderStatusUpdate> statusHistory = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    
    // debugPrint('📦 [TRACKER_V2] ===== TRACKER V2 WIDGET CREADO =====');
    // debugPrint('📦 [TRACKER_V2] Order ID: ${widget.order.id}');
    debugPrint('📦 [TRACKER_V2] Status: ${widget.order.status}');
    // debugPrint('🔐 [TRACKER_V2] Confirm Code: ${widget.order.confirmCode}');
    debugPrint('🚚 [TRACKER_V2] Delivery ID: ${widget.order.deliveryAgentId}');
    // debugPrint('👤 [TRACKER_V2] Delivery Agent Object: ${widget.order.deliveryAgent}');
    debugPrint('👤 [TRACKER_V2] Delivery Name: ${widget.order.deliveryAgent?.name}');
    
    _initAnimations();
    _loadStatusHistory();
    _startPeriodicRefresh();
  }

  void _initAnimations() {
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
      end: _getProgressValue(),
    ).animate(CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    ));
    
    // Iniciar animaciones
    _pulseController.repeat(reverse: true);
    _progressController.forward();
  }

  /// Cargar histórico de status desde order_status_updates
  Future<void> _loadStatusHistory() async {
    try {
      final response = await SupabaseConfig.client
          .from('order_status_updates')
          .select('*')
          .eq('order_id', widget.order.id)
          .order('created_at', ascending: true);
      
      if (response != null && response is List) {
        final history = response.map((item) => OrderStatusUpdate.fromJson(item)).toList();
        
        if (mounted) {
          setState(() {
            statusHistory = history;
          });
          debugPrint('📦 [TRACKER_V2] Status history loaded: ${history.length} entries');
        }
      }
      
    } catch (e) {
      debugPrint('❌ [TRACKER_V2] Error loading status history: $e');
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadStatusHistory();
      }
    });
  }

  @override
  void didUpdateWidget(ActiveOrderTrackerV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.order.status != widget.order.status) {
      debugPrint('📦 [TRACKER_V2] Status: ${oldWidget.order.status} -> ${widget.order.status}');
      // debugPrint('🔐 [TRACKER_V2] Confirm Code en update: ${widget.order.confirmCode}');
      debugPrint('🚚 [TRACKER_V2] Delivery ID: ${widget.order.deliveryAgentId}');
      // debugPrint('👤 [TRACKER_V2] Delivery Agent Object en update: ${widget.order.deliveryAgent}');
      debugPrint('👤 [TRACKER_V2] Delivery Name: ${widget.order.deliveryAgent?.name}');
      
      // Actualizar animación de progreso
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: _getProgressValue(),
      ).animate(CurvedAnimation(
        parent: _progressController,
        curve: Curves.easeInOut,
      ));
      
      _progressController.forward();
      _loadStatusHistory(); // Refrescar histórico
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  double _getProgressValue() {
    switch (widget.order.status) {
      case OrderStatus.pending:
        return 0.15;
      case OrderStatus.confirmed:
        return 0.3;
      case OrderStatus.inPreparation:
        return 0.5;
      case OrderStatus.readyForPickup:
        return 0.75;
      case OrderStatus.assigned:
        return 0.65;
      case OrderStatus.onTheWay:
        return 0.9;
      case OrderStatus.delivered:
        return 1.0;
      case OrderStatus.canceled:
        return 0.0;
      case OrderStatus.notDelivered:
        return 0.0;
      default:
        return 0.15;
    }
  }

  Color _getStatusColor() {
    switch (widget.order.status) {
      case OrderStatus.pending:
        return Colors.orange.shade400;
      case OrderStatus.confirmed:
        return Colors.blue.shade500;
      case OrderStatus.inPreparation:
        return Colors.purple.shade500;
      case OrderStatus.readyForPickup:
        return Colors.green.shade600;
      case OrderStatus.assigned:
        return Colors.amber.shade600;
      case OrderStatus.onTheWay:
        return Colors.indigo.shade600;
      case OrderStatus.delivered:
        return Colors.green.shade700;
      case OrderStatus.canceled:
        return Colors.red.shade500;
      case OrderStatus.notDelivered:
        return Colors.red.shade500;
      default:
        return Colors.grey.shade500;
    }
  }

  String _getStatusText() {
    switch (widget.order.status) {
      case OrderStatus.pending:
        return 'Pedido Recibido';
      case OrderStatus.confirmed:
        return 'Pedido Confirmado';
      case OrderStatus.inPreparation:
        return 'Preparando Comida';
      case OrderStatus.readyForPickup:
        return 'Listo para Recoger';
      case OrderStatus.assigned:
        return 'Repartidor Asignado';
      case OrderStatus.onTheWay:
        return 'En Camino a Ti';
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

  String _getTimeInfo() {
    if (statusHistory.isEmpty) {
    return 'Hace ${_getTimeAgo(widget.order.createdAt)}';
    }
    
    // Buscar el timestamp del status actual
    final currentStatusUpdate = statusHistory.lastWhere(
      (update) => update.status == widget.order.status,
      orElse: () => statusHistory.last,
    );
    
  return 'Hace ${_getTimeAgo(currentStatusUpdate.createdAt)}';
  }

  String _getTimeAgo(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
    
    if (difference.inMinutes < 1) {
      return 'unos segundos';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes} min';
    } else if (difference.inDays < 1) {
      return '${difference.inHours} h';
    } else {
      return '${difference.inDays} días';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header con restaurante y tiempo
              Row(
                children: [
                  Icon(
                    Icons.restaurant,
                    color: _getStatusColor(),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.order.restaurant?.name ?? 'Restaurante',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _getTimeInfo(),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: widget.order.status == OrderStatus.delivered 
                            ? 1.0 
                            : _pulseAnimation.value,
                        child: Icon(
                          widget.order.status == OrderStatus.delivered
                              ? Icons.check_circle
                              : Icons.access_time_filled,
                          color: _getStatusColor(),
                          size: 32,
                        ),
                      );
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Status actual
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _getStatusColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _getStatusText(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(),
                      ),
                    ),
                  ),
                  Text(
                    'Pedido #${widget.order.id.substring(0, 8)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
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
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Progreso',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                          Text(
                            '${(_progressAnimation.value * 100).toInt()}%',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              
              // Código de confirmación (cuando está en camino)
              if (widget.order.status == OrderStatus.onTheWay && widget.order.confirmCode != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Container(
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
                      Row(
                        children: [
                          Icon(
                            Icons.pin,
                            color: Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Código de Confirmación',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          widget.order.confirmCode!,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                            letterSpacing: 4.0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Comparte este código con el repartidor para confirmar la entrega',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
              
              // Histórico de estados (opcional)
              if (widget.showHistoricalSteps && statusHistory.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                Text(
                  'Histórico del Pedido',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...statusHistory.map((update) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 6,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getStatusTextForHistory(update.status),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        _getTimeAgo(update.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getStatusTextForHistory(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pedido realizado';
      case OrderStatus.confirmed:
        return 'Confirmado por restaurante';
      case OrderStatus.inPreparation:
        return 'Comenzó preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para recoger';
      case OrderStatus.assigned:
        return 'Repartidor asignado';
      case OrderStatus.onTheWay:
        return 'En camino';
      case OrderStatus.delivered:
        return 'Entregado exitosamente';
      case OrderStatus.canceled:
        return 'Pedido cancelado';
      case OrderStatus.notDelivered:
        return 'No se pudo entregar';
      default:
        return status.toString();
    }
  }
}