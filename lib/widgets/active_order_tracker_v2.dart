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

  // Pasos del flujo normal de entrega (en orden)
  static const _flowSteps = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.inPreparation,
    OrderStatus.readyForPickup,
    OrderStatus.onTheWay,
    OrderStatus.delivered,
  ];

  int get _currentStepIndex {
    final s = widget.order.status;
    // assigned se muestra como readyForPickup
    final effective = s == OrderStatus.assigned ? OrderStatus.readyForPickup : s;
    return _flowSteps.indexOf(effective);
  }

  bool get _isCancelled =>
      widget.order.status == OrderStatus.canceled ||
      widget.order.status == OrderStatus.notDelivered;

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.restaurant, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.order.restaurant?.name ?? 'Restaurante',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pedido #${widget.order.id.substring(0, 8).toUpperCase()}  ·  ${_getTimeInfo()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, _) => Transform.scale(
                      scale: (_isCancelled || widget.order.status == OrderStatus.delivered)
                          ? 1.0
                          : _pulseAnimation.value,
                      child: Icon(
                        _isCancelled
                            ? Icons.cancel_outlined
                            : widget.order.status == OrderStatus.delivered
                                ? Icons.check_circle
                                : Icons.access_time_filled,
                        color: statusColor,
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // ── Badge de estado actual ───────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getStatusText(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // ── Timeline de pasos ────────────────────────────────────
              if (!_isCancelled) _buildStepTimeline(context, statusColor, isDark),

              if (_isCancelled) ...[
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.red.shade400, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      widget.order.status == OrderStatus.canceled
                          ? 'Este pedido fue cancelado.'
                          : 'No se pudo completar la entrega.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ],

              // ── Repartidor (cuando está asignado) ───────────────────
              if (widget.order.deliveryAgent != null &&
                  !_isCancelled &&
                  widget.order.status != OrderStatus.delivered) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.delivery_dining,
                        size: 20,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.order.deliveryAgent!.name ?? 'Repartidor',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.order.deliveryAgent!.phone?.isNotEmpty == true)
                            Text(
                              widget.order.deliveryAgent!.phone!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  ],
                ),
              ],

              // ── Código de confirmación ───────────────────────────────
              if (widget.order.status == OrderStatus.onTheWay &&
                  widget.order.confirmCode != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: isDark ? 0.15 : 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.pin_outlined, color: Colors.orange.shade700, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Código de confirmación',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.order.confirmCode!,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade800,
                          letterSpacing: 6.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Muéstraselo al repartidor al recibir tu pedido',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              // ── Histórico de estados ────────────────────────────────
              if (widget.showHistoricalSteps && statusHistory.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Historial',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                ...statusHistory.map((update) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 5, color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _getStatusTextForHistory(update.status),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        _getTimeAgo(update.createdAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
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

  Widget _buildStepTimeline(BuildContext context, Color statusColor, bool isDark) {
    final theme = Theme.of(context);
    final currentIdx = _currentStepIndex;

    final steps = [
      (icon: Icons.receipt_long_outlined, label: 'Recibido'),
      (icon: Icons.thumb_up_alt_outlined, label: 'Confirmado'),
      (icon: Icons.restaurant_menu_outlined, label: 'Preparando'),
      (icon: Icons.inventory_2_outlined, label: 'Listo'),
      (icon: Icons.delivery_dining_outlined, label: 'En camino'),
      (icon: Icons.home_outlined, label: 'Entregado'),
    ];

    return SizedBox(
      height: 72,
      child: Row(
        children: List.generate(steps.length, (i) {
          final isDone = currentIdx >= 0 && i <= currentIdx;
          final isActive = i == currentIdx;
          final isLast = i == steps.length - 1;

          final dotColor = isDone ? statusColor : theme.colorScheme.onSurface.withValues(alpha: 0.18);
          final lineColor = (i < currentIdx) ? statusColor : theme.colorScheme.onSurface.withValues(alpha: 0.12);

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: isActive ? 34 : 28,
                        height: isActive ? 34 : 28,
                        decoration: BoxDecoration(
                          color: isDone ? dotColor : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: dotColor,
                            width: isActive ? 2.5 : 1.5,
                          ),
                          boxShadow: isActive
                              ? [BoxShadow(color: statusColor.withValues(alpha: 0.3), blurRadius: 8, spreadRadius: 1)]
                              : [],
                        ),
                        child: Icon(
                          steps[i].icon,
                          size: isActive ? 16 : 13,
                          color: isDone
                              ? Colors.white
                              : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        steps[i].label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          color: isDone
                              ? statusColor
                              : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: lineColor,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
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