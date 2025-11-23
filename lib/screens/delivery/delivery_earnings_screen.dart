import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/services/navigation_service.dart';

class DeliveryEarningsScreen extends StatefulWidget {
  const DeliveryEarningsScreen({super.key});

  @override
  State<DeliveryEarningsScreen> createState() => _DeliveryEarningsScreenState();
}

class _DeliveryEarningsScreenState extends State<DeliveryEarningsScreen> {
  Map<String, dynamic> stats = {};
  List<Map<String, dynamic>> recentDeliveries = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDeliveryStats();
  }

  Future<void> _loadDeliveryStats() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      print('📊 [DELIVERY] Loading delivery statistics...');
      
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        throw Exception('Usuario no autenticado');
      }

      // Obtener estadísticas de entregas
      final response = await SupabaseConfig.client
          .from('orders')
          .select('*')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'entregado');

      print('📦 [DELIVERY] Stats response: $response');

      if (response is List) {
        final deliveries = List<Map<String, dynamic>>.from(response);
        
        // Calcular estadísticas
        final totalDeliveries = deliveries.length;
        final totalEarnings = deliveries.fold<double>(
          0.0, 
          (sum, order) => sum + ((order['delivery_fee'] ?? 3.0) as num).toDouble()
        );
        
        // Estadísticas de hoy
        final today = DateTime.now();
        final todayDeliveries = deliveries.where((order) {
          final deliveryTime = DateTime.parse(order['delivery_time'] ?? order['created_at']);
          return deliveryTime.year == today.year &&
                 deliveryTime.month == today.month &&
                 deliveryTime.day == today.day;
        }).toList();
        
        final todayEarnings = todayDeliveries.fold<double>(
          0.0,
          (sum, order) => sum + ((order['delivery_fee'] ?? 3.0) as num).toDouble()
        );
        
        // Estadísticas de la semana
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final weekDeliveries = deliveries.where((order) {
          final deliveryTime = DateTime.parse(order['delivery_time'] ?? order['created_at']);
          return deliveryTime.isAfter(weekStart);
        }).toList();
        
        final weekEarnings = weekDeliveries.fold<double>(
          0.0,
          (sum, order) => sum + ((order['delivery_fee'] ?? 3.0) as num).toDouble()
        );

        setState(() {
          stats = {
            'totalDeliveries': totalDeliveries,
            'totalEarnings': totalEarnings,
            'todayDeliveries': todayDeliveries.length,
            'todayEarnings': todayEarnings,
            'weekDeliveries': weekDeliveries.length,
            'weekEarnings': weekEarnings,
            'averageEarningsPerDelivery': totalDeliveries > 0 ? totalEarnings / totalDeliveries : 0.0,
          };
          recentDeliveries = deliveries.take(5).toList();
          isLoading = false;
        });
        
        print('✅ [DELIVERY] Stats loaded successfully');
      }
    } catch (e) {
      print('❌ [DELIVERY] Error loading stats: $e');
      setState(() {
        errorMessage = 'Error al cargar estadísticas: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ganancias y Estadísticas'),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDeliveryStats,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error al cargar estadísticas',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        errorMessage!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.red,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadDeliveryStats,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadDeliveryStats,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header con ganancias principales
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                NavigationService.getRoleColor(context, UserRole.delivery_agent),
                                NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.attach_money, color: Colors.white, size: 32),
                              const SizedBox(height: 8),
                              Text(
                                '\$${(stats['totalEarnings'] ?? 0.0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'Ganancias Totales',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${stats['totalDeliveries'] ?? 0} entregas completadas',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Estadísticas por periodo
                        Text(
                          'Resumen de Entregas',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'Hoy',
                                '${stats['todayDeliveries'] ?? 0}',
                                '\$${(stats['todayEarnings'] ?? 0.0).toStringAsFixed(2)}',
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                'Esta Semana',
                                '${stats['weekDeliveries'] ?? 0}',
                                '\$${(stats['weekEarnings'] ?? 0.0).toStringAsFixed(2)}',
                                Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Promedio por entrega
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.trending_up, color: Colors.purple),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Promedio por Entrega',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '\$${(stats['averageEarningsPerDelivery'] ?? 0.0).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Entregas recientes
                        Text(
                          'Entregas Recientes',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        if (recentDeliveries.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.inbox, size: 48, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No hay entregas completadas aún',
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ),
                          )
                        else
                          ...recentDeliveries.map((delivery) => _buildRecentDeliveryCard(delivery)),
                        
                        const SizedBox(height: 24),
                        
                        // Consejos para ganar más
                        Container(
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
                                  const Icon(Icons.lightbulb, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Consejos para Ganar Más',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text('• Mantente activo durante horas pico (12-2 PM, 7-9 PM)'),
                              const SizedBox(height: 4),
                              const Text('• Acepta pedidos rápidamente para mayor visibilidad'),
                              const SizedBox(height: 4),
                              const Text('• Sé puntual y amable para obtener mejores reseñas'),
                              const SizedBox(height: 4),
                              const Text('• Familiarízate con las rutas más rápidas'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatCard(String title, String deliveries, String earnings, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            deliveries,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            'entregas',
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            earnings,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDeliveryCard(Map<String, dynamic> delivery) {
    final deliveryTime = DateTime.parse(delivery['delivery_time'] ?? delivery['created_at']);
    final earnings = (delivery['delivery_fee'] ?? 3.0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ),
        title: Text(
          'Pedido #${delivery['id'].toString().substring(0, 8)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(_formatDateTime(deliveryTime)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '+\$${earnings.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);

    if (difference.inMinutes < 60) {
      return 'Hace ${difference.inMinutes} min';
    } else if (difference.inHours < 24) {
      return 'Hace ${difference.inHours} horas';
    } else {
    return '${local.day}/${local.month} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
    }
  }
}