import 'package:flutter/material.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/auth/login_screen.dart';
import 'package:doa_repartos/screens/orders/my_orders_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_onboarding_dashboard.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DoaUser? _currentUser;
  bool _isLoading = true;
  List<DoaOrder> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = SupabaseConfig.client.auth.currentUser;
      if (user != null) {
        // Obtener datos completos del usuario
        Map<String, dynamic>? userData = await DoaRepartosService.getUserById(user.id);
        // Si es repartidor, preferir perfil consolidado para incluir profile_image_url y docs
        try {
          final baseRole = userData?['role']?.toString() ?? '';
          if (baseRole == 'repartidor') {
            final merged = await DoaRepartosService.getDeliveryAgentByUserId(user.id);
            if (merged != null) userData = merged;
          }
        } catch (_) {}
        if (userData != null) {
          _currentUser = DoaUser.fromJson(userData);
        }

        // Obtener pedidos recientes
        final ordersData = await DoaRepartosService.getOrdersWithDetails(userId: user.id);
        _recentOrders = ordersData.map((o) => DoaOrder.fromJson(o)).take(5).toList();
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cargando datos: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      await SupabaseAuth.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cerrando sesión: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Configuración próximamente')),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Información del usuario
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              backgroundImage: (_currentUser?.profileImageUrl != null && _currentUser!.profileImageUrl!.isNotEmpty)
                                  ? NetworkImage(_currentUser!.profileImageUrl!)
                                  : null,
                              child: (_currentUser?.profileImageUrl == null || _currentUser!.profileImageUrl!.isEmpty)
                                  ? Text(
                                      _currentUser?.name?.substring(0, 1).toUpperCase() ??
                                      _currentUser?.email.substring(0, 1).toUpperCase() ?? 'U',
                                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            
                            const SizedBox(height: 16),
                            
                            Text(
                              _currentUser?.name ?? 'Usuario',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            
                            const SizedBox(height: 4),
                            
                            Text(
                              _currentUser?.email ?? '',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                            
                            if (_currentUser?.phone != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _currentUser!.phone!,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 16),
                            
                            // Tipo de usuario
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _getUserRoleText(_currentUser?.role ?? UserRole.client),
                                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Opciones del menú
                    Card(
                      child: Column(
                        children: [
                          if ((_currentUser?.role ?? UserRole.client) == UserRole.delivery_agent) ...[
                            _ProfileMenuItem(
                              icon: Icons.assignment_ind_outlined,
                              title: 'Mis documentos',
                              subtitle: 'Sube y administra tus documentos',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const DeliveryOnboardingDashboard()),
                                );
                              },
                            ),
                            const Divider(height: 1),
                          ],
                          _ProfileMenuItem(
                            icon: Icons.history,
                            title: 'Mis Pedidos',
                            subtitle: 'Ver historial de pedidos',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                              );
                            },
                          ),
                          
                          const Divider(height: 1),

                          if ((_currentUser?.role ?? UserRole.client) == UserRole.restaurant) ...[
                            _ProfileMenuItem(
                              icon: Icons.store_outlined,
                              title: 'Mi Restaurante',
                              subtitle: 'Gestionar información del negocio',
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const RestaurantProfileScreen()),
                                );
                              },
                            ),
                            const Divider(height: 1),
                          ],
                          
                          _ProfileMenuItem(
                            icon: Icons.location_on_outlined,
                            title: 'Direcciones',
                            subtitle: 'Gestionar direcciones de entrega',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Direcciones próximamente')),
                              );
                            },
                          ),
                          
                          const Divider(height: 1),
                          
                          _ProfileMenuItem(
                            icon: Icons.payment_outlined,
                            title: 'Métodos de Pago',
                            subtitle: 'Gestionar tarjetas y métodos',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Métodos de pago próximamente')),
                              );
                            },
                          ),
                          
                          const Divider(height: 1),
                          
                          _ProfileMenuItem(
                            icon: Icons.favorite_outline,
                            title: 'Favoritos',
                            subtitle: 'Restaurantes y productos favoritos',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Favoritos próximamente')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Pedidos recientes
                    if (_recentOrders.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pedidos Recientes',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const MyOrdersScreen()),
                              );
                            },
                            child: const Text('Ver todos'),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 8),
                      
                      Card(
                        child: Column(
                          children: _recentOrders.map((order) {
                            final isLast = _recentOrders.last == order;
                            return Column(
                              children: [
                                _OrderItem(order: order),
                                if (!isLast) const Divider(height: 1),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                    ],
                    
                    // Ayuda y soporte
                    Card(
                      child: Column(
                        children: [
                          _ProfileMenuItem(
                            icon: Icons.help_outline,
                            title: 'Ayuda y Soporte',
                            subtitle: 'Preguntas frecuentes y contacto',
                            onTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Ayuda próximamente')),
                              );
                            },
                          ),
                          
                          const Divider(height: 1),
                          
                          _ProfileMenuItem(
                            icon: Icons.info_outline,
                            title: 'Acerca de',
                            subtitle: 'Información de la app',
                            onTap: () {
                              showAboutDialog(
                                context: context,
                                applicationName: 'DOA Repartos',
                                applicationVersion: '1.0.0',
                                applicationIcon: Icon(
                                  Icons.delivery_dining,
                                  size: 32,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                children: [
                                  const Text(
                                    'Tu app de delivery favorita. Comida deliciosa en la comodidad de tu hogar.',
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Cerrar sesión
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Cerrar Sesión'),
                              content: const Text('¿Estás seguro que deseas cerrar sesión?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _logout();
                                  },
                                  child: const Text('Cerrar Sesión'),
                                ),
                              ],
                            ),
                          );
                        },
                        icon: const Icon(Icons.logout),
                        label: const Text('Cerrar Sesión'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  String _getUserRoleText(UserRole role) {
    switch (role) {
      case UserRole.client:
        return 'Cliente';
      case UserRole.restaurant:
        return 'Restaurante';
      case UserRole.delivery_agent:
        return 'Repartidor';
      case UserRole.admin:
        return 'Administrador';
    }
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _OrderItem extends StatelessWidget {
  final DoaOrder order;

  const _OrderItem({required this.order});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: _getStatusColor(order.status).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          _getStatusIcon(order.status),
          color: _getStatusColor(order.status),
          size: 20,
        ),
      ),
      title: Text(
        order.restaurant?.name ?? 'Restaurante',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _getStatusText(order.status),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: _getStatusColor(order.status),
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            _formatDate(order.createdAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      trailing: Text(
        '\\\$${order.totalAmount.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.lightBlue;
      case OrderStatus.inPreparation:
        return Colors.blue;
      case OrderStatus.readyForPickup:
        return Colors.teal;
      case OrderStatus.assigned:
        return Colors.amber;
      case OrderStatus.onTheWay:
        return Colors.purple;
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
        return Icons.schedule;
      case OrderStatus.confirmed:
        return Icons.check;
      case OrderStatus.inPreparation:
        return Icons.restaurant;
      case OrderStatus.readyForPickup:
        return Icons.done_all;
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

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pendiente';
      case OrderStatus.confirmed:
        return 'Confirmado';
      case OrderStatus.inPreparation:
        return 'En preparación';
      case OrderStatus.readyForPickup:
        return 'Listo para recoger';
      case OrderStatus.assigned:
        return 'Repartidor asignado';
      case OrderStatus.onTheWay:
        return 'En camino';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.notDelivered:
        return 'No Entregado';
    }
  }

  String _formatDate(DateTime date) {
  final local = date.toLocal();
  final now = DateTime.now();
  final difference = now.difference(local);
    
    if (difference.inDays == 0) {
    return 'Hoy ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Ayer';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} días atrás';
    } else {
    return '${local.day}/${local.month}/${local.year}';
    }
  }
}