import 'package:flutter/material.dart';
import 'package:doa_repartos/models/doa_models.dart';
import 'package:doa_repartos/screens/home/home_screen.dart';
import 'package:doa_repartos/screens/restaurants/restaurants_screen.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_profile_screen.dart';
import 'package:doa_repartos/screens/restaurant/products_management_screen.dart';
import 'package:doa_repartos/screens/restaurant/orders_management_screen.dart';
import 'package:doa_repartos/screens/admin/simple_admin_dashboard.dart';
import 'package:doa_repartos/screens/admin/admin_main_dashboard.dart';
import 'package:doa_repartos/screens/delivery/available_orders_screen.dart';
import 'package:doa_repartos/screens/delivery/my_deliveries_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_earnings_screen.dart';
import 'package:doa_repartos/screens/delivery/delivery_main_dashboard.dart';
import 'package:doa_repartos/screens/restaurant/restaurant_main_dashboard.dart';
import 'package:doa_repartos/supabase/supabase_config.dart';
import 'package:doa_repartos/services/realtime_service.dart';
import 'dart:async';

/// Navegación inteligente basada en roles de usuario
/// Dirige a cada usuario al dashboard apropiado según su rol
class NavigationService {
  /// Navega al dashboard apropiado según el rol del usuario
  static Future<void> navigateByRole(BuildContext context, UserRole role, {Map<String, dynamic>? userData}) async {
    try {
      print('🚀 NavigationService.navigateByRole called');
      print('📊 Role received: $role (${role.runtimeType})');
      print('📊 Role name: ${role.name}');
      print('👤 User data: $userData');
      
      // SEGURIDAD: Verificar que el context siga siendo válido
      if (!context.mounted) {
        print('❌ [NAVIGATION] Context no válido, cancelando navegación');
        return;
      }
      
      Widget targetScreen;
      String routeName;
      
      switch (role) {
        case UserRole.client:
          // Los clientes van al HomeScreen (catálogo de restaurantes)
          targetScreen = const HomeScreen();
          routeName = 'Cliente Dashboard (HomeScreen)';
          print('✅ CLIENTE: Navigating to HomeScreen');
          break;
          
        case UserRole.restaurant:
          // Los restaurantes van a un dashboard para gestionar su negocio
          targetScreen = const RestaurantMainDashboard();
          routeName = 'Restaurant Dashboard (RestaurantMainDashboard)';
          print('✅ RESTAURANTE: Navigating to RestaurantMainDashboard');
          break;
          
        case UserRole.delivery_agent:
          // Los repartidores van al dashboard principal con barra de navegación
          targetScreen = const DeliveryMainDashboard();
          routeName = 'Delivery Main Dashboard (DeliveryMainDashboard)';
          print('✅ REPARTIDOR: Navigating to DeliveryMainDashboard');
          break;
          
        case UserRole.admin:
          // Los admins ahora usan un shell con barra inferior y rail en desktop
          targetScreen = const AdminMainDashboard();
          routeName = 'Admin Main Dashboard (AdminMainDashboard)';
          print('✅ ADMIN: Navigating to AdminMainDashboard');
          break;
      }
      
      debugPrint('🎯 Navigating user to $routeName (Role: $role)');
      print('🔄 About to call Navigator.pushAndRemoveUntil');
      print('🏗️ Target screen type: ${targetScreen.runtimeType}');
      
      // VERIFICAR NUEVAMENTE que el context siga siendo válido
      if (!context.mounted) {
        print('❌ [NAVIGATION] Context ya no válido antes de navegación');
        return;
      }
      
      // Navegar reemplazando la pila de navegación completa con manejo de errores
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (builderContext) {
          try {
            print('🏗️ MaterialPageRoute builder called, returning: ${targetScreen.runtimeType}');
            return targetScreen;
          } catch (e) {
            print('❌ [NAVIGATION] Error en builder: $e');
            // Fallback seguro: pantalla de error mínima
            return Scaffold(
              appBar: AppBar(title: const Text('Error')),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error cargando pantalla: $routeName'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(builderContext).pushNamedAndRemoveUntil('/login', (route) => false),
                      child: const Text('Volver al Login'),
                    ),
                  ],
                ),
              ),
            );
          }
        }),
        (route) => false, // Remover todas las rutas previas
      );
      
      print('✅ Navigation completed successfully');
      
    } catch (e) {
      print('❌ [NAVIGATION] CRITICAL ERROR in navigateByRole: $e');
      print('❌ [NAVIGATION] Stack trace: ${StackTrace.current}');
      
      // Manejo de emergencia - redirigir al login
      try {
        if (context.mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } catch (e2) {
        print('❌ [NAVIGATION] DOUBLE ERROR - ni siquiera pudo navegar al login: $e2');
      }
    }
  }
  
  /// Obtiene el título del dashboard según el rol
  static String getDashboardTitle(UserRole role) {
    switch (role) {
      case UserRole.client:
        return 'Explora Restaurantes';
      case UserRole.restaurant:
        return 'Gestionar Restaurante';
      case UserRole.delivery_agent:
        return 'Dashboard Repartidor';
      case UserRole.admin:
        return 'Panel Administrativo';
    }
  }
  
  /// Obtiene el icono principal según el rol
  static IconData getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.client:
        return Icons.restaurant_menu;
      case UserRole.restaurant:
        return Icons.store;
      case UserRole.delivery_agent:
        return Icons.delivery_dining;
      case UserRole.admin:
        return Icons.admin_panel_settings;
    }
  }
  
  /// Obtiene el color del tema según el rol
  static Color getRoleColor(BuildContext context, UserRole role) {
    final colorScheme = Theme.of(context).colorScheme;
    
    switch (role) {
      case UserRole.client:
        return colorScheme.primary; // Azul para clientes
      case UserRole.restaurant:
        return const Color(0xFFE4007C); // Rosa mexicano para restaurantes (Doña repartos)
      case UserRole.delivery_agent:
        return Colors.green; // Verde para repartidores
      case UserRole.admin:
        return Colors.purple; // Morado para admins
    }
  }
}

/// Dashboard original (deprecated - usar RestaurantMainDashboard)
class RestaurantDashboardScreen extends StatefulWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  State<RestaurantDashboardScreen> createState() => _RestaurantDashboardScreenState();
}

class _RestaurantDashboardScreenState extends State<RestaurantDashboardScreen> {
  bool isRestaurantAvailable = true; // Estado de disponibilidad del restaurante
  Map<String, int> orderStats = {
    'newOrders': 0,        // Pedidos nuevos por aceptar
    'activeOrders': 0,     // Pedidos en proceso (confirmed, in_preparation, ready)
    'completedOrders': 0,  // Pedidos completados hoy
  };
  bool isLoadingStats = true;
  DoaRestaurant? _restaurant;

  @override
  void initState() {
    super.initState();
    _loadRestaurantData();
  }

  /// Cargar datos del restaurante y estadísticas de pedidos
  Future<void> _loadRestaurantData() async {
    setState(() => isLoadingStats = true);
    
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) return;

      print('📊 [RESTAURANT DASHBOARD] Loading data for user: ${currentUser.id}');

      // Obtener información del restaurante
      final restaurantResponse = await SupabaseConfig.client
          .from('restaurants')
          .select()
          .eq('user_id', currentUser.id)
          .maybeSingle();
      
      if (restaurantResponse != null) {
        _restaurant = DoaRestaurant.fromJson(restaurantResponse);
        print('🏪 [RESTAURANT] Found restaurant: ${_restaurant!.name} (${_restaurant!.id})');
        
        // Cargar estadísticas de pedidos solo si tenemos restaurante
        await _loadOrderStats();
      } else {
        print('⚠️ [RESTAURANT] No restaurant found for user');
      }
      
    } catch (e) {
      print('❌ [RESTAURANT DASHBOARD] Error loading data: $e');
    } finally {
      setState(() => isLoadingStats = false);
    }
  }

  /// Cargar estadísticas de pedidos del restaurante
  Future<void> _loadOrderStats() async {
    if (_restaurant == null) return;
    
    try {
      print('📊 [RESTAURANT] Loading order stats for restaurant: ${_restaurant!.id}');

      // Pedidos nuevos (pending) - por aceptar
      final newOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .eq('status', 'pending');

      print('📊 [RESTAURANT] New orders found: ${newOrdersResponse.length}');

      // Pedidos activos (confirmed, in_preparation, ready_for_pickup)
      final activeOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup']);

      print('📊 [RESTAURANT] Active orders found: ${activeOrdersResponse.length}');

      // Pedidos completados hoy (delivered)
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day).toIso8601String();
      final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();
      
      final completedOrdersResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('restaurant_id', _restaurant!.id)
          .eq('status', 'delivered')
          .gte('created_at', todayStart)
          .lte('created_at', todayEnd);

      print('📊 [RESTAURANT] Completed orders today: ${completedOrdersResponse.length}');

      setState(() {
        orderStats = {
          'newOrders': (newOrdersResponse as List).length,
          'activeOrders': (activeOrdersResponse as List).length,
          'completedOrders': (completedOrdersResponse as List).length,
        };
      });

      print('📊 [RESTAURANT] Final order stats: $orderStats');
    } catch (e) {
      print('❌ [RESTAURANT] Error loading order stats: $e');
    }
  }

  /// Toggle de disponibilidad del restaurante
  void _toggleAvailability() async {
    // TODO: En futuras versiones, actualizar el estado en la base de datos
    setState(() => isRestaurantAvailable = !isRestaurantAvailable);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isRestaurantAvailable 
            ? '🟢 Tu restaurante está ahora DISPONIBLE para recibir pedidos'
            : '🔴 Tu restaurante está ahora NO DISPONIBLE para pedidos'
        ),
        backgroundColor: isRestaurantAvailable ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(NavigationService.getDashboardTitle(UserRole.restaurant)),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.restaurant),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadRestaurantData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📊 Actualizando estadísticas...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header de bienvenida con botón de disponibilidad
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: NavigationService.getRoleColor(context, UserRole.restaurant).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: NavigationService.getRoleColor(context, UserRole.restaurant).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        NavigationService.getRoleIcon(UserRole.restaurant),
                        size: 32,
                        color: NavigationService.getRoleColor(context, UserRole.restaurant),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _restaurant?.name ?? 'Mi Restaurante',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: NavigationService.getRoleColor(context, UserRole.restaurant),
                          ),
                        ),
                      ),
                      // Botón toggle de disponibilidad
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (isRestaurantAvailable ? Colors.green : Colors.red).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (isRestaurantAvailable ? Colors.green : Colors.red).withValues(alpha: 0.3),
                          ),
                        ),
                        child: GestureDetector(
                          onTap: _toggleAvailability,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isRestaurantAvailable ? Icons.check_circle : Icons.pause_circle,
                                size: 16,
                                color: isRestaurantAvailable ? Colors.green : Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isRestaurantAvailable ? 'DISPONIBLE' : 'NO DISPONIBLE',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isRestaurantAvailable ? Colors.green : Colors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gestiona tu restaurante, productos y pedidos desde aquí.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Contadores de pedidos esenciales
            if (isLoadingStats)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_restaurant != null) ...[
              Row(
                children: [
                  Expanded(
                    child: _buildOrderStatCard(
                      'Nuevos',
                      'Por aceptar',
                      orderStats['newOrders']!,
                      Colors.orange,
                      Icons.pending_actions,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildOrderStatCard(
                      'En Curso',
                      'Preparando/Listos',
                      orderStats['activeOrders']!,
                      Colors.blue,
                      Icons.restaurant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildOrderStatCard(
                      'Terminados',
                      'Completados hoy',
                      orderStats['completedOrders']!,
                      Colors.green,
                      Icons.check_circle,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
            ],
            
            const SizedBox(height: 24),
            
            // Opciones del dashboard
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildDashboardCard(
                    context,
                    title: 'Mi Restaurante',
                    subtitle: 'Información y configuración',
                    icon: Icons.store_outlined,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RestaurantProfileScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Productos',
                    subtitle: 'Gestionar menú',
                    icon: Icons.restaurant_menu_outlined,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProductsManagementScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Pedidos',
                    subtitle: 'Pedidos recibidos',
                    icon: Icons.receipt_long_outlined,
                    badge: orderStats['newOrders']! > 0 ? orderStats['newOrders']!.toString() : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const OrdersManagementScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Estadísticas',
                    subtitle: 'Análisis y reportes',
                    icon: Icons.analytics_outlined,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Próximamente: Estadísticas')),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Botón temporal para ver como cliente
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                ),
                icon: const Icon(Icons.visibility),
                label: const Text('Ver como Cliente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Widget para mostrar estadísticas de pedidos
  Widget _buildOrderStatCard(
    String title,
    String subtitle,
    int count,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 9,
              color: color.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: NavigationService.getRoleColor(context, UserRole.restaurant),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard específico para repartidores
class DeliveryDashboardScreen extends StatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  State<DeliveryDashboardScreen> createState() => _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState extends State<DeliveryDashboardScreen> {
  bool isAvailable = true;
  Map<String, int> stats = {
    'availableOrders': 0,
    'activeDeliveries': 0,
    'todayDeliveries': 0,
  };
  bool isLoadingStats = true;
  StreamSubscription<void>? _realtimeSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('🚚 [DELIVERY-DASHBOARD] ===== INICIALIZANDO DELIVERY DASHBOARD =====');
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol del usuario al iniciar
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _verifyUserRole();
    });
    
    _loadDashboardStats();
    _setupRealtimeUpdates();
  }
  
  /// Verificar que el usuario actual sea un repartidor
  Future<void> _verifyUserRole() async {
    try {
      debugPrint('🔍 [DELIVERY-DASHBOARD] ===== VERIFICANDO TIPO DE USUARIO =====');
      
      final user = SupabaseConfig.client.auth.currentUser;
      if (user?.emailConfirmedAt == null) {
        debugPrint('❌ [DELIVERY-DASHBOARD] Usuario no autenticado');
        return;
      }
      
      debugPrint('👤 [DELIVERY-DASHBOARD] Usuario ID: ${user!.id}');
      debugPrint('📧 [DELIVERY-DASHBOARD] Usuario Email: ${user.email}');
      
      // Verificar rol del usuario en la BD
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();
          
      final userRole = userData['role'] as String?;
      debugPrint('👑 [DELIVERY-DASHBOARD] Usuario Role: $userRole');
      
      if (userRole != 'repartidor') {
        debugPrint('❌ [DELIVERY-DASHBOARD] ===== ERROR CRÍTICO: USUARIO NO ES REPARTIDOR =====');
        debugPrint('❌ [DELIVERY-DASHBOARD] Usuario role: $userRole, pero dashboard es para repartidor');
        debugPrint('❌ [DELIVERY-DASHBOARD] DETENIENDO CARGA COMPLETA DE DATOS');
        
        // Limpiar timers y servicios
        _refreshTimer?.cancel();
        _realtimeSubscription?.cancel();
        
        // Mostrar error y redirigir a login
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error: Este dashboard es solo para repartidores. Tu rol actual: $userRole'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
          
          // Redirigir al login después de un breve delay
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
            }
          });
        }
        return;
      }
      
      debugPrint('✅ [DELIVERY-DASHBOARD] ===== USUARIO REPARTIDOR VERIFICADO =====');
      
    } catch (e) {
      debugPrint('❌ [DELIVERY-DASHBOARD] Error verificando rol de usuario: $e');
    }
  }

  @override
  void dispose() {
    _realtimeSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Configurar actualizaciones en tiempo real usando el sistema de instancias por usuario
  Future<void> _setupRealtimeUpdates() async {
    final user = SupabaseConfig.client.auth.currentUser;
    if (user?.emailConfirmedAt == null) {
      debugPrint('❌ [DELIVERY-DASHBOARD] Usuario no autenticado en setup realtime');
      return;
    }
    
    // ✅ PROTECCIÓN CRÍTICA: Verificar rol antes de configurar tiempo real
    try {
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', user!.id)
          .single();
          
      final userRole = userData['role'] as String?;
      
      if (userRole != 'repartidor') {
        debugPrint('❌ [DELIVERY-DASHBOARD] SETUP CANCELADO: Usuario no es repartidor (rol: $userRole)');
        return;
      }
    } catch (e) {
      debugPrint('❌ [DELIVERY-DASHBOARD] Error verificando rol en setup: $e');
      return;
    }
    
    debugPrint('🎯 [DELIVERY-DASHBOARD] ===== CONFIGURANDO TIEMPO REAL PARA REPARTIDOR =====');
    debugPrint('🎯 [DELIVERY-DASHBOARD] Usuario: ${user.id}');
    
    final realtimeService = RealtimeNotificationService.forUser(user.id);
    debugPrint('🎯 [DELIVERY-DASHBOARD] Service inicializado: ${realtimeService.isInitialized}');
    
    // Inicializar si es necesario
    if (!realtimeService.isInitialized) {
      debugPrint('🚀 [DELIVERY-DASHBOARD] Inicializando servicio tiempo real...');
      realtimeService.initialize().then((_) {
        debugPrint('✅ [DELIVERY-DASHBOARD] Servicio inicializado exitosamente');
      }).catchError((error) {
        debugPrint('❌ [DELIVERY-DASHBOARD] Error inicializando servicio: $error');
      });
    }
    
    // Escuchar actualizaciones generales que afecten las estadísticas del repartidor
    _realtimeSubscription = realtimeService.orderUpdates.listen((_) {
      debugPrint('🔔 [DELIVERY-DASHBOARD] Actualización de órdenes recibida');
      _loadDashboardStats();
    });
    
    // Timer de respaldo para actualizar estadísticas cada 30 segundos
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      debugPrint('⏰ [DELIVERY-DASHBOARD] Actualizando estadísticas (timer)');
      _loadDashboardStats();
    });
    
    debugPrint('✅ [DELIVERY-DASHBOARD] Sistema de tiempo real configurado para repartidor');
  }

  Future<void> _loadDashboardStats() async {
    // Solo mostrar loading si es la primera carga
    final showLoading = stats['availableOrders'] == 0 && stats['activeDeliveries'] == 0;
    if (showLoading && mounted) {
      setState(() => isLoadingStats = true);
    }
    
    try {
      final currentUser = SupabaseAuth.currentUser;
      if (currentUser == null) {
        debugPrint('❌ [DELIVERY-DASHBOARD] Usuario no autenticado para stats');
        return;
      }
      
      // ✅ PROTECCIÓN CRÍTICA: Verificar rol antes de cargar estadísticas
      final userData = await SupabaseConfig.client
          .from('users')
          .select('role')
          .eq('id', currentUser.id)
          .single();
          
      final userRole = userData['role'] as String?;
      
      if (userRole != 'repartidor') {
        debugPrint('❌ [DELIVERY-DASHBOARD] STATS CANCELADAS: Usuario no es repartidor (rol: $userRole)');
        return;
      }

      debugPrint('📊 [DELIVERY-DASHBOARD] ===== CARGANDO ESTADÍSTICAS PARA REPARTIDOR =====');
      debugPrint('📊 [DELIVERY-DASHBOARD] Usuario: ${currentUser.id}');

      // CORRECCIÓN: Solo pedidos ya aceptados por el restaurante (sin 'pending')
      final availableResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .inFilter('status', ['confirmed', 'in_preparation', 'ready_for_pickup'])
          .isFilter('delivery_agent_id', null);

      debugPrint('📦 [DELIVERY-DASHBOARD] Pedidos disponibles: ${availableResponse.length}');
      debugPrint('✅ [DELIVERY-DASHBOARD] ¡CORRECTO! Solo pedidos aceptados por restaurante');

      // Entregas activas del repartidor (corregir estados)
      final activeResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status')
          .eq('delivery_agent_id', currentUser.id)
          .inFilter('status', ['en_camino', 'out_for_delivery']);

      debugPrint('🚚 [DELIVERY-DASHBOARD] Entregas activas: ${activeResponse.length}');

      // Entregas de hoy (corregir campo y estado)
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day).toIso8601String();
      final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String();
      
      final todayResponse = await SupabaseConfig.client
          .from('orders')
          .select('id, status, delivery_time')
          .eq('delivery_agent_id', currentUser.id)
          .eq('status', 'entregado')
          .gte('delivery_time', todayStart)
          .lte('delivery_time', todayEnd);

      debugPrint('✅ [DELIVERY-DASHBOARD] Entregas de hoy: ${todayResponse.length}');

      if (mounted) {
        setState(() {
          stats = {
            'availableOrders': (availableResponse as List).length,
            'activeDeliveries': (activeResponse as List).length,
            'todayDeliveries': (todayResponse as List).length,
          };
          if (showLoading) isLoadingStats = false;
        });
      }

      debugPrint('📊 [DELIVERY-DASHBOARD] Estadísticas finales: $stats');
      
      // Mostrar notificación si hay nuevos pedidos disponibles
      if (!showLoading && (availableResponse as List).isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🔔 ${(availableResponse as List).length} ${(availableResponse as List).length == 1 ? "pedido disponible" : "pedidos disponibles"}!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      
    } catch (e) {
      debugPrint('❌ [DELIVERY-DASHBOARD] Error cargando estadísticas: $e');
      if (showLoading && mounted) {
        setState(() => isLoadingStats = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(NavigationService.getDashboardTitle(UserRole.delivery_agent)),
        backgroundColor: NavigationService.getRoleColor(context, UserRole.delivery_agent),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              debugPrint('🔄 [DELIVERY-DASHBOARD] Refresh manual solicitado');
              _loadDashboardStats();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔄 Actualizando dashboard...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          debugPrint('🔄 [DELIVERY-DASHBOARD] Pull-to-refresh activado');
          await _loadDashboardStats();
          debugPrint('✅ [DELIVERY-DASHBOARD] Pull-to-refresh completado');
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header de bienvenida
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: NavigationService.getRoleColor(context, UserRole.delivery_agent).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          NavigationService.getRoleIcon(UserRole.delivery_agent),
                          size: 32,
                          color: NavigationService.getRoleColor(context, UserRole.delivery_agent),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '¡Bienvenido, Repartidor!',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: NavigationService.getRoleColor(context, UserRole.delivery_agent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Encuentra pedidos disponibles para entregar y gestiona tus entregas.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Estado de disponibilidad
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (isAvailable ? Colors.green : Colors.red).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (isAvailable ? Colors.green : Colors.red).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isAvailable ? Icons.check_circle : Icons.pause_circle,
                      color: isAvailable ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      isAvailable ? 'Disponible para entregas' : 'No disponible',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: (isAvailable ? Colors.green : Colors.red).shade800,
                      ),
                    ),
                    const Spacer(),
                    Switch(
                      value: isAvailable,
                      onChanged: (value) {
                        setState(() => isAvailable = value);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(value ? 'Ahora estás disponible para entregas' : 'Ahora no estás disponible'),
                            backgroundColor: value ? Colors.green : Colors.orange,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Estadísticas rápidas
              if (isLoadingStats)
                const Center(child: CircularProgressIndicator())
              else ...[
                Row(
                  children: [
                    Expanded(child: _buildStatCard('Disponibles', stats['availableOrders']!, Colors.blue, Icons.local_shipping)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('En Camino', stats['activeDeliveries']!, Colors.orange, Icons.route)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard('Hoy', stats['todayDeliveries']!, Colors.green, Icons.check_circle)),
                  ],
                ),
                
                const SizedBox(height: 24),
              ],
              
              // Opciones del dashboard
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  _buildDashboardCard(
                    context,
                    title: 'Pedidos Disponibles',
                    subtitle: 'Tomar nuevos pedidos',
                    icon: Icons.local_shipping_outlined,
                    badge: stats['availableOrders']! > 0 ? stats['availableOrders']!.toString() : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AvailableOrdersScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Mis Entregas',
                    subtitle: 'Entregas activas e historial',
                    icon: Icons.route_outlined,
                    badge: stats['activeDeliveries']! > 0 ? stats['activeDeliveries']!.toString() : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MyDeliveriesScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Ganancias',
                    subtitle: 'Ingresos y estadísticas',
                    icon: Icons.attach_money_outlined,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeliveryEarningsScreen()),
                    ),
                  ),
                  _buildDashboardCard(
                    context,
                    title: 'Mi Perfil',
                    subtitle: 'Información personal',
                    icon: Icons.person_outlined,
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Próximamente: Perfil de Repartidor')),
                      );
                    },
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Tips para repartidores
              Container(
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
                        const Icon(Icons.tips_and_updates, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Consejos del Día',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('💡 Mantente activo durante las horas pico para más pedidos'),
                    const SizedBox(height: 4),
                    const Text('⚡ Acepta pedidos rápidamente para mayor visibilidad'),
                    const SizedBox(height: 4),
                    const Text('😊 Sé puntual y amable para obtener mejores reseñas'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, int value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildDashboardCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    String? badge,
  }) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    size: 32,
                    color: NavigationService.getRoleColor(context, UserRole.delivery_agent),
                  ),
                  if (badge != null)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

